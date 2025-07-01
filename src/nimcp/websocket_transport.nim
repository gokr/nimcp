## WebSocket transport for MCP servers using Mummy
## Provides real-time bidirectional communication with JSON-RPC 2.0 over WebSocket

import mummy, mummy/routers, json, strutils, strformat, options, tables, locks
import server, types, protocol
import auth, connection_pool, cors
type
  WebSocketConnection* = ref object
    ## Represents an active WebSocket connection
    websocket*: WebSocket
    id*: string
    authenticated*: bool
    
  WebSocketTransport* = ref object of TransportInterface
    ## WebSocket transport implementation for MCP servers
    server: McpServer
    router: Router
    httpServer: Server
    port*: int
    host*: string
    authConfig*: AuthConfig
    connectionPool: ConnectionPool[WebSocketConnection]

# Reuse authentication types from mummy_transport
proc newWebSocketTransport*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()): WebSocketTransport =
  ## Create a new WebSocket transport instance
  var transport = WebSocketTransport(
    server: server,
    router: Router(),
    port: port,
    host: host,
    authConfig: authConfig,
    connectionPool: newConnectionPool[WebSocketConnection]()
  )
  # Initialize transport interface capabilities
  TransportInterface(transport).capabilities = {tcBroadcast, tcEvents, tcUnicast, tcBidirectional}
  return transport

import random

proc generateConnectionId(): string =
  ## Generate a unique connection ID
  return $rand(int.high)


proc handleJsonRpcMessage(transport: WebSocketTransport, websocket: WebSocket, message: string) {.gcsafe.} =
  ## Handle incoming WebSocket JSON-RPC message
  try:
    if message.len == 0:
      let errorResponse = createInvalidRequest(details = "Empty message")
      websocket.send($(%errorResponse))
      return
    
    # Parse the JSON-RPC request using existing protocol parser
    let jsonRpcRequest = parseJsonRpcMessage(message)
    
    # Handle notifications (no response expected)
    if jsonRpcRequest.id.isNone:
      transport.server.handleNotification(jsonRpcRequest)
      return
    
    # Handle requests that expect responses
    let response = transport.server.handleRequest(jsonRpcRequest)
    
    # Send response back through WebSocket
    var responseJson = newJObject()
    responseJson["jsonrpc"] = %response.jsonrpc
    responseJson["id"] = %response.id
    
    if response.result.isSome():
      responseJson["result"] = response.result.get()
    if response.error.isSome():
      responseJson["error"] = %response.error.get()
    
    websocket.send($responseJson)
    
  except JsonParsingError as e:
    let errorResponse = createParseError(details = e.msg)
    websocket.send($(%errorResponse))
  except Exception as e:
    let errorResponse = createInternalError(JsonRpcId(kind: jridString, str: ""), e.msg)
    websocket.send($(%errorResponse))

proc websocketEventHandler(transport: WebSocketTransport, websocket: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} =
  ## Handle WebSocket events according to Mummy's API
  case event:
  of OpenEvent:
    let connection = WebSocketConnection(
      websocket: websocket,
      id: generateConnectionId(),
      authenticated: true  # Authentication handled during handshake
    )
    transport.connectionPool.addConnection(connection.id, connection)
    echo fmt"WebSocket connection opened: {connection.id}"
    
  of MessageEvent:
    # Handle JSON-RPC message
    if message.kind == TextMessage:
      transport.handleJsonRpcMessage(websocket, message.data)
    
  of CloseEvent:
    # Find and remove connection
    for connection in transport.connectionPool.connections():
      if connection.websocket == websocket:
        echo fmt"WebSocket connection closed: {connection.id}"
        transport.connectionPool.removeConnection(connection.id)
        break
    
  of ErrorEvent:
    # Find and remove connection on error
    for connection in transport.connectionPool.connections():
      if connection.websocket == websocket:
        echo fmt"WebSocket error on connection {connection.id}"
        transport.connectionPool.removeConnection(connection.id)
        break

proc upgradeHandler(transport: WebSocketTransport, request: Request) {.gcsafe.} =
  ## Handle WebSocket upgrade requests
  
  # Validate authentication using shared auth module
  let (valid, errorCode, errorMsg) = validateRequest(transport.authConfig, request)
  if not valid:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain"
    request.respond(errorCode, headers, errorMsg)
    return
  
  # Upgrade to WebSocket - Mummy handles the upgrade internally
  discard request.upgradeToWebSocket()

proc handleInfoRequest(transport: WebSocketTransport, request: Request) {.gcsafe.} =
  ## Handle GET requests for server info
  let info = %*{
    "server": {
      "name": transport.server.serverInfo.name,
      "version": transport.server.serverInfo.version
    },
    "transport": "websocket",
    "capabilities": transport.server.capabilities,
    "websocket": {
      "endpoint": fmt"ws://{transport.host}:{transport.port}/",
      "authentication": transport.authConfig.enabled
    }
  }
  
  var headers = defaultCorsHeaders()
  headers["Content-Type"] = "application/json"
  
  request.respond(200, headers, $info)

proc setupRoutes(transport: WebSocketTransport) =
  ## Set up WebSocket and HTTP routes
  
  # WebSocket/HTTP endpoint
  transport.router.get("/", proc(request: Request) {.gcsafe.} = 
    if "Upgrade" in request.headers and request.headers["Upgrade"].toLowerAscii() == "websocket":
      transport.upgradeHandler(request)
    else:
      transport.handleInfoRequest(request)
  )
  
  # OPTIONS for CORS
  transport.router.options("/", proc(request: Request) {.gcsafe.} =
    let headers = corsHeadersFor("GET, OPTIONS", "Content-Type, Accept, Origin, Authorization, Upgrade, Connection")
    request.respond(204, headers, "")
  )

proc start*(transport: WebSocketTransport) =
  ## Start the WebSocket server
  transport.setupRoutes()
  
  # Create server with WebSocket handler
  let wsHandler = proc(websocket: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} =
    transport.websocketEventHandler(websocket, event, message)
  
  transport.httpServer = newServer(transport.router, wsHandler)
  
  echo fmt"Starting MCP WebSocket server at ws://{transport.host}:{transport.port}/"
  if transport.authConfig.enabled:
    echo "Authentication: Bearer token required"
  echo "Press Ctrl+C to stop the server"
  
  transport.httpServer.serve(Port(transport.port), transport.host)

proc shutdown*(transport: WebSocketTransport) =
  ## Shutdown the WebSocket server and close all connections
  if transport.httpServer != nil:
    transport.httpServer.close()
  
  # Close all active WebSocket connections
  for connection in transport.connectionPool.connections():
    try:
      connection.websocket.close()
    except:
      discard  # Ignore errors during shutdown
  transport.connectionPool = newConnectionPool[WebSocketConnection]()

proc runWebSocket*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()) =
  ## Convenience function to run an MCP server over WebSocket
  let transport = newWebSocketTransport(server, port, host, authConfig)
  try:
    transport.start()
  finally:
    transport.shutdown()

proc broadcastToAll*(transport: WebSocketTransport, message: string) =
  ## Broadcast a message to all connected WebSocket clients
  for connection in transport.connectionPool.connections():
    try:
      connection.websocket.send(message)
    except:
      # Connection failed, remove it
      transport.connectionPool.removeConnection(connection.id)

proc getActiveConnectionCount*(transport: WebSocketTransport): int =
  ## Get the number of active WebSocket connections
  transport.connectionPool.connectionCount()

# Note: Unified transport API methods are now implemented as polymorphic methods below

# Clean API overloads that hide the casting
proc setTransport*(server: McpServer, transport: WebSocketTransport) =
  ## Set WebSocket transport with clean API (casting handled internally)
  server.setWebSocketTransport(cast[pointer](transport))

proc getTransport*(server: McpServer, transportType: typedesc[WebSocketTransport]): WebSocketTransport =
  ## Get WebSocket transport with clean API (casting handled internally)  
  let transportPtr = server.getWebSocketTransportPtr()
  if transportPtr != nil:
    return cast[WebSocketTransport](transportPtr)
  else:
    return nil

# Polymorphic method implementations for TransportInterface
method broadcastMessage*(transport: WebSocketTransport, jsonMessage: JsonNode) =
  ## Polymorphic implementation - broadcast to all WebSocket clients
  let messageStr = $jsonMessage
  transport.broadcastToAll(messageStr)

method sendEvent*(transport: WebSocketTransport, eventType: string, data: JsonNode, target: string = "") =
  ## Polymorphic implementation - send custom event to WebSocket clients
  ## Note: WebSocket doesn't have native event types like SSE, so we wrap in a JSON envelope
  let eventMessage = %*{
    "event": eventType,
    "data": data
  }
  # Use the broadcast implementation directly to avoid recursion
  let messageStr = $eventMessage
  if target != "":
    # Send to specific connection (if implemented)
    transport.broadcastToAll(messageStr)
  else:
    # Broadcast to all
    transport.broadcastToAll(messageStr)

method getTransportKind*(transport: WebSocketTransport): TransportKind =
  ## Polymorphic implementation - return WebSocket transport kind
  return tkWebSocket

