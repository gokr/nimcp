## Server-Sent Events (SSE) transport for MCP servers using Mummy
## Implements the MCP SSE transport specification with bidirectional communication:
## - Server-to-client: SSE event stream
## - Client-to-server: HTTP POST requests
## Note: SSE transport is deprecated in MCP 2024-11-05 but maintained for backwards compatibility

import mummy, mummy/routers, mummy/common, json, strutils, strformat, options, tables, locks, random
import server, types, protocol
import auth, connection_pool
type
  MummySseConnection* = ref object
    ## Wrapper for mummy SSEConnection with additional MCP state
    connection*: SSEConnection
    id*: string
    authenticated*: bool
    
  SseTransport* = ref object of TransportInterface
    ## SSE transport implementation for MCP servers
    server: McpServer
    router: Router
    httpServer: Server
    port*: int
    host*: string
    authConfig*: AuthConfig
    connectionPool: ConnectionPool[MummySseConnection]
    sseEndpoint*: string
    messageEndpoint*: string

proc newSseTransport*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", 
                      authConfig: AuthConfig = newAuthConfig(),
                      sseEndpoint: string = "/sse", 
                      messageEndpoint: string = "/messages"): SseTransport =
  ## Create a new SSE transport instance
  var transport = SseTransport(
    server: server,
    router: Router(),
    port: port,
    host: host,
    authConfig: authConfig,
    connectionPool: newConnectionPool[MummySseConnection](),
    sseEndpoint: sseEndpoint,
    messageEndpoint: messageEndpoint
  )
  # Initialize transport interface capabilities
  transport.capabilities = {tcBroadcast, tcEvents, tcUnicast}
  return transport

proc generateConnectionId(): string =
  ## Generate a unique connection ID
  return $rand(int.high)

proc validateSseAuth(transport: SseTransport, request: Request): tuple[valid: bool, errorMsg: string] =
  ## Validate SSE authentication using shared auth module
  let (valid, errorCode, errorMsg) = validateRequest(transport.authConfig, request)
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

# Note: broadcastMessage is now implemented as a polymorphic method below

proc setupRoutes(transport: SseTransport) =
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
      let endpointEvent = %*{
        "type": "endpoint",
        "endpoint": transport.messageEndpoint
      }
      sendEvent(connection, "endpoint", $endpointEvent)
      
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
      let response = transport.server.handleRequest(jsonRpcRequest)
      
      # Send response back via SSE to all connections
      # In a real implementation, you'd want to route responses to specific connections
      # based on request ID or session management
      
      # Create JSON response (same format as mummy transport)
      var responseJson = newJObject()
      responseJson["jsonrpc"] = %response.jsonrpc
      responseJson["id"] = %response.id
      if response.result.isSome():
        responseJson["result"] = response.result.get()
      if response.error.isSome():
        responseJson["error"] = %response.error.get()
      
      broadcastMessage(transport, responseJson)
      
      # Also send HTTP response for immediate feedback
      request.respond(200, headers = corsHeaders, body = $responseJson)
      
    except JsonParsingError:
      let errorResponse = createParseError()
      request.respond(200, headers = corsHeaders, body = $errorResponse)
    except Exception as e:
      let errorResponse = createInternalError(JsonRpcId(kind: jridString, str: ""), e.msg)
      request.respond(200, headers = corsHeaders, body = $errorResponse)
  )
  
  # CORS preflight for message endpoint
  transport.router.options(transport.messageEndpoint, proc (request: Request) =
    var headers: HttpHeaders
    headers["Access-Control-Allow-Origin"] = "*"
    headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
    headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    request.respond(200, headers = headers)
  )

proc start*(transport: SseTransport) =
  ## Start the SSE transport server
  setupRoutes(transport)
  
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

# Unified transport API for compatibility with WebSocket transport
# Note: sendEvent is now implemented as a polymorphic method below

# Polymorphic method implementations for TransportInterface
method broadcastMessage*(transport: SseTransport, jsonMessage: JsonNode) =
  ## Polymorphic implementation - broadcast to all SSE clients
  for connection in transport.connectionPool.connections():
    sendSseMessage(connection, jsonMessage)

method sendEvent*(transport: SseTransport, eventType: string, data: JsonNode, target: string = "") =
  ## Polymorphic implementation - send custom event to SSE clients
  let dataStr = $data
  if target != "":
    # Send to specific connection if target specified
    for connection in transport.connectionPool.connections():
      if connection.id == target:
        sendEvent(connection, eventType, dataStr)
        break
  else:
    # Broadcast to all connections
    for connection in transport.connectionPool.connections():
      sendEvent(connection, eventType, dataStr)

method getTransportKind*(transport: SseTransport): TransportKind =
  ## Polymorphic implementation - return SSE transport kind
  return tkSSE

# Clean API overloads that hide the casting
proc setTransport*(server: McpServer, transport: SseTransport) =
  ## Set SSE transport with clean API (casting handled internally)
  server.setSseTransport(cast[pointer](transport))

proc getTransport*(server: McpServer, transportType: typedesc[SseTransport]): SseTransport =
  ## Get SSE transport with clean API (casting handled internally)
  let transportPtr = server.getSseTransportPtr()
  if transportPtr != nil:
    return cast[SseTransport](transportPtr)
  else:
    return nil

proc runSse*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()) =
  ## Convenience function to run an MCP server over SSE transport
  let transport = newSseTransport(server, port, host, authConfig)
  transport.start()


