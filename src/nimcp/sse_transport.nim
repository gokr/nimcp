## Server-Sent Events (SSE) Transport Implementation for MCP Servers
##
## This module provides a Server-Sent Events (SSE) based transport layer for Model Context Protocol (MCP) servers.
## It implements bidirectional communication using SSE for server-to-client messaging and HTTP POST for client-to-server
## requests, built on top of the Mummy web framework.
##
## **DEPRECATION NOTICE**: SSE transport is deprecated in the MCP specification as of 2024-11-05.
## The preferred transport is now Streamable HTTP (see [`mummy_transport.nim`](mummy_transport.nim:1)).
## This transport is maintained for backwards compatibility with existing clients.
##
## Key Features:
## - **Bidirectional Communication**: SSE event stream for server-to-client, HTTP POST for client-to-server
## - **Real-time Updates**: Server can push notifications and responses to clients via SSE
## - **Connection Management**: Maintains a pool of active SSE connections with unique IDs
## - **Authentication Support**: Integrates with the auth module for Bearer token authentication
## - **CORS Support**: Handles cross-origin requests for web-based MCP clients
## - **Endpoint Configuration**: Customizable SSE and message endpoint paths
## - **Error Handling**: Robust error handling with proper JSON-RPC error responses
##
## Communication Flow:
## 1. **Client connects** to SSE endpoint (`/sse` by default) to establish event stream
## 2. **Server sends** initial endpoint event with message endpoint URL
## 3. **Client sends** JSON-RPC requests via HTTP POST to message endpoint (`/messages` by default)
## 4. **Server responds** by send JSON-RPC responses via SSE
## 5. **HTTP POST** returns 204 No Content (responses are delivered via SSE only)
##
## Usage:
## ```nim
## let server = newMcpServer("MyServer", "1.0.0")
## # Add tools and resources to server...
##
## # Or with custom configuration
## let authConfig = newAuthConfig(enabled = true, bearerToken = "secret")
## server.runSse(port = 8080, host = "0.0.0.0", authConfig = authConfig)
##
## # Or with custom endpoints
## let transport = newSseTransport(port = 8080, sseEndpoint = "/events", messageEndpoint = "/rpc")
## transport.serve(server)
## ```
##
## The transport automatically handles:
## - SSE connection establishment and lifecycle management
## - Authentication validation for both SSE and message endpoints
## - JSON-RPC message parsing and response
## - Connection cleanup on errors or server shutdown
## - CORS preflight requests for web-based clients
##
## **Future Enhancement**: Support for simultaneous multiple transports would allow
## clients to choose their preferred transport (stdio, HTTP, WebSocket, SSE) from a single server instance.

import mummy, mummy/routers, mummy/common, json, strutils, strformat, options, tables, locks
import server, types, protocol, auth, connection_pool, http_common, cors

type
  MummySseConnection* = ref object
    ## Wrapper for mummy SSEConnection with additional MCP state
    connection*: SSEConnection
    id*: string
    authenticated*: bool
    sessionId*: string  # Session ID for matching HTTP requests to SSE connections
    
  SseTransport* = ref object
    ## SSE transport implementation for MCP servers
    base*: HttpServerBase
    connectionPool: ConnectionPool[MummySseConnection]
    sseEndpoint*: string
    messageEndpoint*: string

# Thread-local storage for current SSE connection (safe for concurrent requests)
var currentSSEConnection {.threadvar.}: MummySseConnection

proc newSseTransport*(port: int = 8080, host: string = "127.0.0.1", 
                      authConfig: AuthConfig = newAuthConfig(),
                      sseEndpoint: string = "/sse", 
                      messageEndpoint: string = "/messages"): SseTransport =
  ## Create a new SSE transport instance
  var transport = SseTransport(
    base: newHttpServerBase(port, host, authConfig, @[]),
    connectionPool: newConnectionPool[MummySseConnection](),
    sseEndpoint: sseEndpoint,
    messageEndpoint: messageEndpoint
  )
  return transport

# Forward declaration for the notification sending function
proc sendNotification(transport: SseTransport, connection: MummySseConnection, notificationType: string, data: JsonNode) {.gcsafe.}

proc sseNotificationWrapper(ctx: McpRequestContext, notificationType: string, data: JsonNode) {.gcsafe.} =
  ## Wrapper function for SSE notification sending that matches function pointer signature
  let transport = cast[SseTransport](ctx.transport.sseTransport)
  if currentSSEConnection != nil:
    transport.sendNotification(currentSSEConnection, notificationType, data)
  else:
    echo "SSE notification requested but no current connection context"

proc validateSseAuth(transport: SseTransport, request: Request): tuple[valid: bool, errorMsg: string] =
  ## Validate SSE authentication using shared auth module
  let (valid, _, errorMsg) = transport.base.validateAuthentication(request)
  if not valid:
    return (false, errorMsg)
  return (true, "")

proc sendEvent(connection: MummySseConnection, event: string, data: string, id: string = "") =
  ## Send an SSE event to a connection (renamed from sendEvent for unified API)
  let sseEvent = SSEEvent(
    event: some(event),
    data: data,
    id: if id != "": some(id) else: none(string),
    retry: none(int)
  )
  
  try:
    connection.connection.send(sseEvent)
  except:
    # Connection closed, ignore
    discard

proc sendSseMessage(connection: MummySseConnection, jsonMessage: JsonNode, id: string = "") =
  ## Send a JSON-RPC message via SSE
  sendEvent(connection, "message", $jsonMessage, id)

proc setupRoutes(transport: SseTransport, server: McpServer) =
  ## Setup SSE and message handling routes
  
  # SSE endpoint - establishes server-to-client stream
  transport.base.router.get(transport.sseEndpoint, proc (request: Request) =
    # Validate authentication
    let (valid, errorMsg) = validateSseAuth(transport, request)
    if not valid:
      let errorResponse = if transport.base.authConfig.customErrorResponses.hasKey(401):
                           transport.base.authConfig.customErrorResponses[401]
                         else:
                           "Unauthorized: " & errorMsg
      request.respond(401, body = errorResponse)
      return
      
    # Create SSE connection using mummy's respondSSE
    try:
      let sseConnection = request.respondSSE()
      
      # Extract session ID from request headers if present
      let sessionId = if "Mcp-Session-Id" in request.headers:
                        request.headers["Mcp-Session-Id"]
                      else:
                        generateConnectionId()
      
      # Create and add connection to pool
      let connection = MummySseConnection(
        connection: sseConnection,
        id: generateConnectionId(),
        authenticated: transport.base.authConfig.enabled,
        sessionId: sessionId
      )
      transport.connectionPool.addConnection(connection.id, connection)
      
      # Send initial endpoint event with message endpoint URL
      # Per MCP specification, endpoint event data should be plain URL string, not JSON
      sendEvent(connection, "endpoint", transport.messageEndpoint)
      
      # Send session ID event so client can use it for HTTP requests
      sendEvent(connection, "session", sessionId)
      
      # Note: mummy handles the connection lifecycle, no need for manual keep-alive
      
    except MummyError as e:
      request.respond(500, body = "SSE connection failed: " & e.msg)
  )
  
  # CORS preflight for SSE endpoint
  transport.base.router.options(transport.sseEndpoint, proc (request: Request) =
    let headers = corsHeadersFor("GET, OPTIONS")
    request.respond(200, headers = headers)
  )
  
  # Message endpoint - handles client-to-server POST requests
  transport.base.router.post(transport.messageEndpoint, proc (request: Request) =
    # CORS headers
    var corsHeaders = corsHeadersFor("POST, GET, OPTIONS")
    corsHeaders["Content-Type"] = "application/json"
    
    try:
      # Parse JSON-RPC request
      if request.body.len == 0:
        request.respond(400, headers = corsHeaders, body = "Empty request body")
        return
        
      let jsonRequest = parseJson(request.body)
      
      # Validate JSON-RPC format
      if not jsonRequest.hasKey("jsonrpc") or jsonRequest["jsonrpc"].getStr() != "2.0":
        let errorResponse = createInvalidRequest(details = "Invalid JSON-RPC version")
        request.respond(200, headers = corsHeaders, body = $errorResponse)
        return
        
      # Parse the JSON-RPC request using the existing protocol parser
      let jsonRpcRequest = parseJsonRpcMessage(request.body)
      
      # Find the SSE connection for this request based on session ID
      let sessionId = if "Mcp-Session-Id" in request.headers:
                        request.headers["Mcp-Session-Id"]
                      else:
                        ""
      
      # Set thread-local connection context if we have a session ID
      currentSSEConnection = nil
      if sessionId != "":
        for connection in transport.connectionPool.connections():
          if connection.sessionId == sessionId:
            currentSSEConnection = connection
            break
      else:
        # If no session ID provided, use the first (and likely only) connection
        # This is a fallback for simple single-client scenarios
        for connection in transport.connectionPool.connections():
          currentSSEConnection = connection
          break  # Use the first connection found
      
      # Use the existing server's request handler with transport access
      let capabilities = {tcUnicast, tcEvents}  # SSE supports unicast and events
      let mcpTransport = McpTransport(kind: tkSSE, capabilities: capabilities, 
        sseTransport: cast[pointer](transport), sseSendNotification: sseNotificationWrapper)
      let response = server.handleRequest(mcpTransport, jsonRpcRequest)
      
      # Send response back via SSE to the specific connection
      if currentSSEConnection != nil:
        sendSseMessage(currentSSEConnection, parseJson($response))
      
      # Return HTTP 204 No Content (no response body per MCP specification)
      request.respond(204, headers = corsHeaders)
      
    except JsonParsingError:
      let errorResponse = createParseError()
      # Send error via SSE and return 204 No Content
      if currentSSEConnection != nil:
        sendSseMessage(currentSSEConnection, %errorResponse)
      request.respond(204, headers = corsHeaders)
    except Exception as e:
      let errorResponse = createInternalError(JsonRpcId(kind: jridString, str: ""), e.msg)
      # Send error via SSE and return 204 No Content
      if currentSSEConnection != nil:
        sendSseMessage(currentSSEConnection, %errorResponse)
      request.respond(204, headers = corsHeaders)
  )
  
  # CORS preflight for message endpoint
  transport.base.router.options(transport.messageEndpoint, proc (request: Request) =
    let headers = corsHeadersFor("POST, GET, OPTIONS")
    request.respond(200, headers = headers)
  )

proc sendNotification(transport: SseTransport, connection: MummySseConnection, notificationType: string, data: JsonNode) {.gcsafe.} =
  ## Send MCP notification to specific SSE client
  let notification = %*{
    "jsonrpc": "2.0",
    "method": "notifications/message",
    "params": %*{
      "type": notificationType,
      "data": data
    }
  }
  
  sendSseMessage(connection, notification)

proc sendNotificationToSession*(transport: SseTransport, sessionId: string, notificationType: string, data: JsonNode) {.gcsafe.} =
  ## Send MCP notification to specific session
  for connection in transport.connectionPool.connections():
    if connection.sessionId == sessionId:
      transport.sendNotification(connection, notificationType, data)
      return

proc serve*(transport: SseTransport, server: McpServer) =
  ## Serve the SSE transport server
  setupRoutes(transport, server)
  
  
  transport.base.httpServer = newServer(transport.base.router)
  
  echo fmt"Starting MCP SSE server at http://{transport.base.host}:{transport.base.port}"
  echo fmt"SSE endpoint: {transport.sseEndpoint}"
  echo fmt"Message endpoint: {transport.messageEndpoint}"
  if transport.base.authConfig.enabled:
    echo "Authentication: Enabled"
  else:
    echo "Authentication: Disabled"
  echo "Press Ctrl+C to stop the server"
  
  transport.base.httpServer.serve(Port(transport.base.port), transport.base.host)

proc stop*(transport: SseTransport) =
  ## Stop the SSE transport server
  transport.base.stopServer()
  
  
  # Close all SSE connections
  for connection in transport.connectionPool.connections():
    try:
      sendEvent(connection, "close", "Server shutting down")
    except:
      discard
  transport.connectionPool = newConnectionPool[MummySseConnection]()
  echo "SSE transport server stopped"

proc getActiveConnectionCount*(transport: SseTransport): int =
  ## Get the number of active SSE connections
  transport.connectionPool.connectionCount()

# Note: Object variant transport system handles polymorphic operations via types.nim



