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
## - **Broadcasting**: Ability to broadcast messages to all connected SSE clients
##
## Communication Flow:
## 1. **Client connects** to SSE endpoint (`/sse` by default) to establish event stream
## 2. **Server sends** initial endpoint event with message endpoint URL
## 3. **Client sends** JSON-RPC requests via HTTP POST to message endpoint (`/messages` by default)
## 4. **Server responds** by broadcasting JSON-RPC responses via SSE to all connected clients
## 5. **HTTP POST** returns 204 No Content (responses are delivered via SSE only)
##
## Usage:
## ```nim
## let server = newMcpServer("MyServer", "1.0.0")
## # Add tools and resources to server...
##
## # Run with default settings
## server.runSse()
##
## # Or with custom configuration
## let authConfig = newAuthConfig(enabled = true, bearerToken = "secret")
## server.runSse(port = 8080, host = "0.0.0.0", authConfig = authConfig)
##
## # Or with custom endpoints
## let transport = newSseTransport(server, sseEndpoint = "/events", messageEndpoint = "/rpc")
## transport.start()
## ```
##
## The transport automatically handles:
## - SSE connection establishment and lifecycle management
## - Authentication validation for both SSE and message endpoints
## - JSON-RPC message parsing and response broadcasting
## - Connection cleanup on errors or server shutdown
## - CORS preflight requests for web-based clients
##
## **Future Enhancement**: Support for simultaneous multiple transports would allow
## clients to choose their preferred transport (stdio, HTTP, WebSocket, SSE) from a single server instance.

import mummy, mummy/routers, mummy/common, json, strutils, strformat, options, tables, locks, random
import server, types, protocol, auth, connection_pool

type
  MummySseConnection* = ref object
    ## Wrapper for mummy SSEConnection with additional MCP state
    connection*: SSEConnection
    id*: string
    authenticated*: bool
    
  SseTransport* = ref object
    ## SSE transport implementation for MCP servers
    router: Router
    httpServer: Server
    port*: int
    host*: string
    authConfig*: AuthConfig
    connectionPool: ConnectionPool[MummySseConnection]
    sseEndpoint*: string
    messageEndpoint*: string

proc newSseTransport*(port: int = 8080, host: string = "127.0.0.1", 
                      authConfig: AuthConfig = newAuthConfig(),
                      sseEndpoint: string = "/sse", 
                      messageEndpoint: string = "/messages"): SseTransport =
  ## Create a new SSE transport instance
  var transport = SseTransport(
    router: Router(),
    port: port,
    host: host,
    authConfig: authConfig,
    connectionPool: newConnectionPool[MummySseConnection](),
    sseEndpoint: sseEndpoint,
    messageEndpoint: messageEndpoint
  )
  return transport

proc generateConnectionId(): string =
  ## Generate a unique connection ID
  return $rand(int.high)

proc validateSseAuth(transport: SseTransport, request: Request): tuple[valid: bool, errorMsg: string] =
  ## Validate SSE authentication using shared auth module
  let (valid, _, errorMsg) = validateRequest(transport.authConfig, request)
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

proc broadcastSseMessage(transport: SseTransport, jsonMessage: JsonNode) =
  ## Broadcast a JSON-RPC message to all SSE connections
  for connection in transport.connectionPool.connections():
    sendSseMessage(connection, jsonMessage)

proc setupRoutes(transport: SseTransport, server: McpServer) =
  ## Setup SSE and message handling routes
  
  # SSE endpoint - establishes server-to-client stream
  transport.router.get(transport.sseEndpoint, proc (request: Request) =
    # Validate authentication
    let (valid, errorMsg) = validateSseAuth(transport, request)
    if not valid:
      let errorResponse = if transport.authConfig.customErrorResponses.hasKey(401):
                           transport.authConfig.customErrorResponses[401]
                         else:
                           "Unauthorized: " & errorMsg
      request.respond(401, body = errorResponse)
      return
      
    # Create SSE connection using mummy's respondSSE
    try:
      let sseConnection = request.respondSSE()
      
      # Create and add connection to pool
      let connection = MummySseConnection(
        connection: sseConnection,
        id: generateConnectionId(),
        authenticated: transport.authConfig.enabled
      )
      transport.connectionPool.addConnection(connection.id, connection)
      
      # Send initial endpoint event with message endpoint URL
      # Per MCP specification, endpoint event data should be plain URL string, not JSON
      sendEvent(connection, "endpoint", transport.messageEndpoint)
      
      # Note: mummy handles the connection lifecycle, no need for manual keep-alive
      
    except MummyError as e:
      request.respond(500, body = "SSE connection failed: " & e.msg)
  )
  
  # CORS preflight for SSE endpoint
  transport.router.options(transport.sseEndpoint, proc (request: Request) =
    var headers: HttpHeaders
    headers["Access-Control-Allow-Origin"] = "*"
    headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
    headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    request.respond(200, headers = headers)
  )
  
  # Message endpoint - handles client-to-server POST requests
  transport.router.post(transport.messageEndpoint, proc (request: Request) =
    # CORS headers
    var corsHeaders: HttpHeaders
    corsHeaders["Access-Control-Allow-Origin"] = "*"
    corsHeaders["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
    corsHeaders["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
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
      
      # Use the existing server's request handler
      let response = server.handleRequest(jsonRpcRequest)
      
      # Send response back via SSE to all connections
      # Per MCP specification, tool responses should only be sent via SSE events
      
      # Create JSON response (same format as mummy transport)
      var responseJson = newJObject()
      responseJson["jsonrpc"] = %response.jsonrpc
      responseJson["id"] = %response.id
      if response.result.isSome():
        responseJson["result"] = response.result.get()
      if response.error.isSome():
        responseJson["error"] = %response.error.get()
      
      # Broadcast response via SSE to all connected clients
      broadcastSseMessage(transport, responseJson)
      
      # Return HTTP 204 No Content (no response body per MCP specification)
      request.respond(204, headers = corsHeaders)
      
    except JsonParsingError:
      let errorResponse = createParseError()
      # Broadcast error via SSE and return 204 No Content
      broadcastSseMessage(transport, %errorResponse)
      request.respond(204, headers = corsHeaders)
    except Exception as e:
      let errorResponse = createInternalError(JsonRpcId(kind: jridString, str: ""), e.msg)
      # Broadcast error via SSE and return 204 No Content
      broadcastSseMessage(transport, %errorResponse)
      request.respond(204, headers = corsHeaders)
  )
  
  # CORS preflight for message endpoint
  transport.router.options(transport.messageEndpoint, proc (request: Request) =
    var headers: HttpHeaders
    headers["Access-Control-Allow-Origin"] = "*"
    headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
    headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    request.respond(200, headers = headers)
  )

proc serve*(transport: SseTransport, server: McpServer) =
  ## Serve the SSE transport server
  setupRoutes(transport, server)
  
  transport.httpServer = newServer(transport.router)
  
  echo fmt"Starting MCP SSE server at http://{transport.host}:{transport.port}"
  echo fmt"SSE endpoint: {transport.sseEndpoint}"
  echo fmt"Message endpoint: {transport.messageEndpoint}"
  if transport.authConfig.enabled:
    echo "Authentication: Enabled"
  else:
    echo "Authentication: Disabled"
  echo "Press Ctrl+C to stop the server"
  
  transport.httpServer.serve(Port(transport.port), transport.host)

proc stop*(transport: SseTransport) =
  ## Stop the SSE transport server
  if transport.httpServer != nil:
    # Close all SSE connections
    for connection in transport.connectionPool.connections():
      try:
        sendEvent(connection, "close", "Server shutting down")
      except:
        discard
    transport.connectionPool = newConnectionPool[MummySseConnection]()
    
    transport.httpServer.close()
    echo "SSE transport server stopped"

proc getActiveConnectionCount*(transport: SseTransport): int =
  ## Get the number of active SSE connections
  transport.connectionPool.connectionCount()

# Note: Object variant transport system handles polymorphic operations via types.nim



