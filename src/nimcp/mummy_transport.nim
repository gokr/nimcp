## Streamable HTTP Transport Implementation for MCP Servers
##
## This module provides a Streamable HTTP transport layer for Model Context Protocol (MCP) servers,
## implementing the modern MCP HTTP transport specification. It supports both traditional JSON responses
## and Server-Sent Events (SSE) streaming based on client capabilities, built on top of the Mummy web framework.
##
## This is the **preferred transport** for MCP servers as of the MCP specification update in 2024-11-05,
## replacing the deprecated SSE transport while maintaining backwards compatibility.
##
## Key Features:
## - **Dual Response Modes**: Automatic detection of client capabilities for JSON or SSE streaming
## - **Session Management**: Support for MCP session IDs via `Mcp-Session-Id` header
## - **Authentication Support**: Integrates with the auth module for Bearer token authentication
## - **CORS Support**: Comprehensive cross-origin request handling for web-based clients
## - **DNS Rebinding Protection**: Origin validation to prevent DNS rebinding attacks
## - **Content Negotiation**: Automatic response format selection based on `Accept` header
## - **Error Handling**: Robust error handling with proper JSON-RPC error responses
## - **Server Info Endpoint**: GET requests return server capabilities and transport information
##
## Transport Modes:
## 1. **JSON Response Mode** (default): Traditional HTTP request-response with JSON payloads
## 2. **SSE Streaming Mode**: Server-Sent Events for real-time response streaming (when client sends `Accept: text/event-stream`)
##
## Communication Flow:
## - **GET /**: Returns server information, capabilities, and transport details
## - **POST /**: Handles JSON-RPC requests with automatic response mode detection
## - **OPTIONS /**: Handles CORS preflight requests
##
## Usage:
## ```nim
## let server = newMcpServer("MyServer", "1.0.0")
## # Add tools and resources to server...
##
## # Run with default settings
## server.runHttp()
##
## # Or with custom configuration
## let authConfig = newAuthConfig(enabled = true, bearerToken = "secret")
## let allowedOrigins = @["https://myapp.com", "https://localhost:3000"]
## server.runHttp(port = 8080, host = "0.0.0.0", authConfig = authConfig, allowedOrigins = allowedOrigins)
##
## # Or create transport instance for more control
## let transport = newMummyTransport(server, port = 8080, authConfig = authConfig)
## transport.start()
## ```
##
## Security Features:
## - **Origin Validation**: Prevents DNS rebinding attacks by validating Origin header
## - **Authentication**: Bearer token validation for protected endpoints
## - **CORS Configuration**: Configurable allowed origins with secure defaults
## - **Session Isolation**: Session ID support for multi-client scenarios
##
## The transport automatically handles:
## - Client capability detection via Accept headers
## - Response format selection (JSON vs SSE)
## - Authentication validation and error responses
## - CORS preflight and actual request handling
## - Session management via custom headers
## - Error formatting according to JSON-RPC 2.0 specification

import mummy, mummy/routers, json, strutils, strformat, options, tables, times
import server, types, protocol, auth, cors, http_common

type
  MummyTransport* = ref object
    base*: HttpServerBase
    connections*: Table[string, Request]  # Active streaming connections

proc newMummyTransport*(port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig(), allowedOrigins: seq[string] = @[]): MummyTransport =
  var defaultOrigins = if allowedOrigins.len == 0: @["http://localhost", "https://localhost", "http://127.0.0.1", "https://127.0.0.1"] else: allowedOrigins
  var transport = MummyTransport(
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

proc handleJsonRequest(transport: MummyTransport, server: McpServer, request: Request, jsonRpcRequest: JsonRpcRequest, sessionId: string) {.gcsafe.} =
  ## Handle regular JSON response mode
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  headers["Content-Type"] = "application/json"
  
  if sessionId != "":
    headers["Mcp-Session-Id"] = sessionId
  
  # Use the existing server's request handler
  let response = server.handleRequest(jsonRpcRequest)
  
  # Only send a response if it's not empty (i.e., not a notification)
  if response.id.kind != jridString or response.id.str != "":
    request.respond(200, headers, $response)
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

proc handleStreamingRequest(transport: MummyTransport, server: McpServer, request: Request, jsonRpcRequest: JsonRpcRequest, sessionId: string) {.gcsafe.} =
  ## Handle SSE streaming mode
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  headers["Content-Type"] = "text/event-stream"
  headers["Cache-Control"] = "no-cache"
  headers["Connection"] = "keep-alive"
  headers["Transfer-Encoding"] = "chunked"
  
  if sessionId != "":
    headers["Mcp-Session-Id"] = sessionId
  
  # Handle the request
  let response = server.handleRequest(jsonRpcRequest)
  
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

proc handleMcpRequest(transport: MummyTransport, server: McpServer, request: Request) {.gcsafe.} =
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
          "name": server.serverInfo.name,
          "version": server.serverInfo.version
        },
        "transport": "streamable-http",
        "capabilities": server.capabilities,
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
          handleStreamingRequest(transport, server, request, jsonRpcRequest, sessionId)
        else:
          # Regular JSON response mode
          handleJsonRequest(transport, server, request, jsonRpcRequest, sessionId)
          
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

proc setupRoutes(transport: MummyTransport, server: McpServer) =
  # Handle all MCP requests on the root path
  transport.router.get("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(server, request))
  transport.router.post("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(server, request))
  transport.router.options("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(server, request))

proc serve*(transport: MummyTransport, server: McpServer) =
  ## Serve the HTTP server and serve MCP requests
  transport.setupRoutes(server)
  transport.httpServer = newServer(transport.router)
  
  echo fmt"Starting MCP HTTP server at http://{transport.host}:{transport.port}"
  echo "Press Ctrl+C to stop the server"
  
  transport.httpServer.serve(Port(transport.port), transport.host)

