## Mummy HTTP transport for MCP servers
## Integrates fully with existing server.nim mechanisms

import mummy, mummy/routers, json, strutils, strformat, options, tables, times
import server, types, protocol
import auth, cors  # Import shared modules

type
  MummyTransport* = ref object
    server: McpServer
    router: Router
    httpServer: Server
    port: int
    host: string
    authConfig*: AuthConfig
    allowedOrigins*: seq[string]  # For DNS rebinding protection
    connections*: Table[string, Request]  # Active streaming connections

proc newMummyTransport*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig(), allowedOrigins: seq[string] = @[]): MummyTransport =
  var defaultOrigins = if allowedOrigins.len == 0: @["http://localhost", "https://localhost", "http://127.0.0.1", "https://127.0.0.1"] else: allowedOrigins
  var transport = MummyTransport(
    server: server,
    router: Router(),
    port: port,
    host: host,
    authConfig: authConfig,
    allowedOrigins: defaultOrigins,
    connections: initTable[string, Request]()
  )
  return transport
proc validateOrigin(transport: MummyTransport, request: Request): bool =
  ## Validate Origin header to prevent DNS rebinding attacks
  if "Origin" notin request.headers:
    return true  # Allow requests without Origin header (e.g., from curl)
  
  let origin = request.headers["Origin"]
  return origin in transport.allowedOrigins

proc supportsStreaming(request: Request): bool =
  ## Check if client supports SSE streaming via Accept header
  if "Accept" notin request.headers:
    return false
  
  let acceptHeader = request.headers["Accept"]
  return "text/event-stream" in acceptHeader

proc getSessionId(request: Request): string =
  ## Extract session ID from Mcp-Session-Id header if present
  if "Mcp-Session-Id" in request.headers:
    return request.headers["Mcp-Session-Id"]
  return ""

proc validateAuthentication(transport: MummyTransport, request: Request): tuple[valid: bool, errorCode: int, errorMsg: string] =
  ## Validate authentication using shared auth module
  validateRequest(transport.authConfig, request)

proc handleJsonRequest(transport: MummyTransport, request: Request, jsonRpcRequest: JsonRpcRequest, sessionId: string) {.gcsafe.} =
  ## Handle regular JSON response mode
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  headers["Content-Type"] = "application/json"
  
  if sessionId != "":
    headers["Mcp-Session-Id"] = sessionId
  
  # Use the existing server's request handler
  let response = transport.server.handleRequest(jsonRpcRequest)
  
  # Only send a response if it's not empty (i.e., not a notification)
  if response.id.kind != jridString or response.id.str != "":
    # Custom JSON serialization to exclude null fields (same as stdio transport)
    var responseJson = newJObject()
    responseJson["jsonrpc"] = %response.jsonrpc
    responseJson["id"] = %response.id
    if response.result.isSome():
      responseJson["result"] = response.result.get()
    if response.error.isSome():
      responseJson["error"] = %response.error.get()
    
    request.respond(200, headers, $responseJson)
  else:
    # For notifications, just return 204 No Content
    request.respond(204, headers, "")

proc formatSseEvent(eventType: string, data: JsonNode, id: string = ""): string =
  ## Format data as Server-Sent Event
  var lines: seq[string] = @[]
  if id != "":
    lines.add("id: " & id)
  if eventType != "":
    lines.add("event: " & eventType)
  lines.add("data: " & $data)
  lines.add("")  # Empty line terminates the event
  return lines.join("\n")

proc handleStreamingRequest(transport: MummyTransport, request: Request, jsonRpcRequest: JsonRpcRequest, sessionId: string) {.gcsafe.} =
  ## Handle SSE streaming mode
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  headers["Content-Type"] = "text/event-stream"
  headers["Cache-Control"] = "no-cache"
  headers["Connection"] = "keep-alive"
  headers["Transfer-Encoding"] = "chunked"
  
  if sessionId != "":
    headers["Mcp-Session-Id"] = sessionId
  
  # Handle the request
  let response = transport.server.handleRequest(jsonRpcRequest)
  
  # Send response as SSE event if not a notification
  if response.id.kind != jridString or response.id.str != "":
    var responseJson = newJObject()
    responseJson["jsonrpc"] = %response.jsonrpc
    responseJson["id"] = %response.id
    if response.result.isSome():
      responseJson["result"] = response.result.get()
    if response.error.isSome():
      responseJson["error"] = %response.error.get()
    
    let eventData = formatSseEvent("message", responseJson, $now().toTime().toUnix())
    # Note: For proper SSE streaming, we need to send the event data
    # Since Mummy doesn't provide direct chunk writing, we'll send the entire SSE response
    request.respond(200, headers, eventData)

proc handleMcpRequest(transport: MummyTransport, request: Request) {.gcsafe.} =
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  
  # DNS rebinding protection (skip for OPTIONS requests)
  if request.httpMethod != "OPTIONS" and not transport.validateOrigin(request):
    headers["Content-Type"] = "text/plain"
    request.respond(403, headers, "Forbidden: Invalid origin")
    return
  
  # Authentication validation (skip for OPTIONS requests)
  if request.httpMethod != "OPTIONS":
    let authResult = validateAuthentication(transport, request)
    if not authResult.valid:
      headers["Content-Type"] = "text/plain"
      let errorMsg = if authResult.errorCode in transport.authConfig.customErrorResponses:
                      transport.authConfig.customErrorResponses[authResult.errorCode]
                    else:
                      authResult.errorMsg
      request.respond(authResult.errorCode, headers, errorMsg)
      return
  
  # Determine response mode based on Accept header
  let streamingSupported = supportsStreaming(request)
  let sessionId = getSessionId(request)
  
  case request.httpMethod:
    of "OPTIONS":
      request.respond(204, headers, "")
      
    of "GET":
      # Return server info for GET requests
      headers["Content-Type"] = "application/json"
      let info = %*{
        "server": {
          "name": transport.server.serverInfo.name,
          "version": transport.server.serverInfo.version
        },
        "transport": "streamable-http",
        "capabilities": transport.server.capabilities,
        "streaming": streamingSupported
      }
      if sessionId != "":
        headers["Mcp-Session-Id"] = sessionId
      request.respond(200, headers, $info)
      
    of "POST":
      try:
        if request.body.len == 0:
          headers["Content-Type"] = "application/json"
          let errorResponse = createJsonRpcError(
            JsonRpcId(kind: jridString, str: ""), 
            InvalidRequest, 
            "Empty request body"
          )
          request.respond(400, headers, $(%errorResponse))
          return
        
        # Parse the JSON-RPC request using the existing protocol parser
        let jsonRpcRequest = parseJsonRpcMessage(request.body)
        
        # Handle based on streaming support
        if streamingSupported:
          # SSE streaming mode
          handleStreamingRequest(transport, request, jsonRpcRequest, sessionId)
        else:
          # Regular JSON response mode
          handleJsonRequest(transport, request, jsonRpcRequest, sessionId)
          
      except JsonParsingError as e:
        headers["Content-Type"] = "application/json"
        let errorResponse = createParseError(details = e.msg)
        request.respond(400, headers, $(%errorResponse))
      except Exception as e:
        headers["Content-Type"] = "application/json"
        let errorResponse = createInternalError(JsonRpcId(kind: jridString, str: ""), e.msg)
        request.respond(500, headers, $(%errorResponse))
        
    else:
      request.respond(405, headers, "Method not allowed")

# These functions were moved before handleMcpRequest
    # For now, we'll use the basic response mechanism

proc setupRoutes(transport: MummyTransport) =
  # Handle all MCP requests on the root path
  transport.router.get("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(request))
  transport.router.post("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(request))
  transport.router.options("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(request))

proc start*(transport: MummyTransport) =
  ## Start the HTTP server and serve MCP requests
  transport.setupRoutes()
  transport.httpServer = newServer(transport.router)
  
  echo fmt"Starting MCP HTTP server at http://{transport.host}:{transport.port}"
  echo "Press Ctrl+C to stop the server"
  
  transport.httpServer.serve(Port(transport.port), transport.host)

proc runHttp*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig(), allowedOrigins: seq[string] = @[]) =
  ## Convenience function to run an MCP server over Streamable HTTP
  let transport = newMummyTransport(server, port, host, authConfig, allowedOrigins)
  transport.start()

# Transport operations are now handled by the unified polymorphic procedures in types.nim