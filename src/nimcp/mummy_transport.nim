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

import mummy, mummy/routers, json, strutils, strformat, options, tables
import server, types, protocol, auth, cors, http_common

# Thread-local storage for current HTTP request (safe for concurrent requests)
var currentHTTPRequest {.threadvar.}: Request

type
  MummyTransport* = ref object
    base*: HttpServerBase
    connections*: Table[string, Request]  # Active streaming connections

# Forward declaration for the notification sending function
proc sendNotification(transport: MummyTransport, request: Request, notificationType: string, data: JsonNode) {.gcsafe.}

proc httpNotificationWrapper(ctx: McpRequestContext, notificationType: string, data: JsonNode) {.gcsafe.} =
  ## Wrapper function for HTTP notification sending that matches function pointer signature
  let transport = cast[MummyTransport](ctx.transport.httpTransport)
  if currentHTTPRequest != nil:
    transport.sendNotification(currentHTTPRequest, notificationType, data)
  else:
    echo "HTTP notification requested but no current request context"

proc newMummyTransport*(port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig(), allowedOrigins: seq[string] = @[]): MummyTransport =
  var transport = MummyTransport(
    base: newHttpServerBase(port, host, authConfig, allowedOrigins),
    connections: initTable[string, Request]()
  )
  return transport
proc validateOrigin(transport: MummyTransport, request: Request): bool =
  ## Validate Origin header to prevent DNS rebinding attacks
  return transport.base.validateOrigin(request)

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
  return transport.base.validateAuthentication(request)

proc handleJsonRequest(transport: MummyTransport, server: McpServer, request: Request, jsonRpcRequest: JsonRpcRequest, sessionId: string) {.gcsafe.} =
  ## Handle regular JSON response mode
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  headers["Content-Type"] = "application/json"
  
  if sessionId != "":
    headers["Mcp-Session-Id"] = sessionId
  
  # Set thread-local request context for notifications
  currentHTTPRequest = request
  
  # Use the existing server's request handler with transport access
  let capabilities = {tcEvents, tcUnicast}
  let mcpTransport = McpTransport(kind: tkHttp, capabilities: capabilities, 
    httpTransport: cast[pointer](transport), httpSendNotification: httpNotificationWrapper)
  let response = server.handleRequest(mcpTransport, jsonRpcRequest)
  
  # Only send a response if it's not empty (i.e., not a notification)
  if response.id.kind != jridString or response.id.str != "":
    request.respond(200, headers, $response)
  else:
    # For notifications, just return 204 No Content
    request.respond(204, headers, "")


proc handleStreamingRequest(transport: MummyTransport, server: McpServer, request: Request, jsonRpcRequest: JsonRpcRequest, sessionId: string) {.gcsafe.} =
  ## Handle Streamable HTTP mode (MCP specification)
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  headers["Content-Type"] = "application/json"
  headers["Cache-Control"] = "no-cache"
  
  if sessionId != "":
    headers["Mcp-Session-Id"] = sessionId
    # Add this connection to the streaming connections table for notifications
    transport.connections[sessionId] = request
  
  # Set thread-local request context for notifications
  currentHTTPRequest = request
  
  try:
    # Handle the request with transport access
    let capabilities = {tcEvents, tcUnicast}
    let mcpTransport = McpTransport(kind: tkHttp, capabilities: capabilities, 
      httpTransport: cast[pointer](transport), httpSendNotification: httpNotificationWrapper)
    let response = server.handleRequest(mcpTransport, jsonRpcRequest)
    
    # Send regular JSON response (not SSE format) for streamable HTTP
    if response.id.kind != jridString or response.id.str != "":
      request.respond(200, headers, $response)
    else:
      # For notifications, return 204 No Content
      request.respond(204, headers, "")
  finally:
    # Remove connection after handling request
    if sessionId != "" and sessionId in transport.connections:
      transport.connections.del(sessionId)

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
      let errorMsg = if authResult.errorCode in transport.base.authConfig.customErrorResponses:
                      transport.base.authConfig.customErrorResponses[authResult.errorCode]
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

proc sendNotification(transport: MummyTransport, request: Request, notificationType: string, data: JsonNode) {.gcsafe.} =
  ## Send MCP notification to HTTP client
  ## Note: HTTP transport has limited notification support due to request-response nature
  ## Notifications are only possible during active request processing
  
  # For HTTP transport, notifications are typically sent as part of the response
  # In this case, we'll just log the notification as HTTP is request-response based
  echo fmt"HTTP notification for current request: {notificationType} - {data}"
  
  # In a real implementation, you might want to:
  # 1. Queue the notification to be sent with the response
  # 2. Use WebSocket upgrade for real-time notifications
  # 3. Use SSE for server-sent events
  # 4. Send notifications via a separate channel (email, webhook, etc.)

proc sendNotificationToSession*(transport: MummyTransport, sessionId: string, notificationType: string, data: JsonNode) {.gcsafe.} =
  ## Send MCP notification to specific session
  ## Note: HTTP transport has limited notification support due to request-response nature
  ## This method logs the notification as HTTP cannot send real-time notifications
  echo fmt"HTTP notification for session {sessionId}: {notificationType} - {data}"
  
  # In practice, HTTP transport would need:
  # 1. A persistent connection (WebSocket/SSE)
  # 2. A notification queue system
  # 3. Alternative delivery methods (webhooks, email, etc.)

proc setupRoutes(transport: MummyTransport, server: McpServer) =
  # Handle all MCP requests on the root path
  transport.base.router.get("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(server, request))
  transport.base.router.post("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(server, request))
  transport.base.router.options("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(server, request))

proc serve*(transport: MummyTransport, server: McpServer) =
  ## Serve the HTTP server and serve MCP requests
  transport.setupRoutes(server)
  transport.base.httpServer = newServer(transport.base.router)
  
  echo fmt"Starting MCP HTTP server at http://{transport.base.host}:{transport.base.port}"
  echo "Press Ctrl+C to stop the server"
  
  transport.base.httpServer.serve(Port(transport.base.port), transport.base.host)

