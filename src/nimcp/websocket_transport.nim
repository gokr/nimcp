## WebSocket transport for MCP servers using Mummy
## Provides real-time bidirectional communication with JSON-RPC 2.0 over WebSocket

import mummy, mummy/routers, json, strutils, strformat, options, tables, locks
import server, types, protocol

# Import AuthConfig from mummy_transport
from mummy_transport import AuthConfig, newAuthConfig

type
  WebSocketConnection* = ref object
    ## Represents an active WebSocket connection
    websocket*: WebSocket
    id*: string
    authenticated*: bool
    
  WebSocketTransport* = ref object
    ## WebSocket transport implementation for MCP servers
    server: McpServer
    router: Router
    httpServer: Server
    port*: int
    host*: string
    authConfig*: AuthConfig
    connections: Table[string, WebSocketConnection]
    connectionsLock: Lock

# Reuse authentication types from mummy_transport
proc newWebSocketTransport*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()): WebSocketTransport =
  ## Create a new WebSocket transport instance
  var transport = WebSocketTransport(
    server: server,
    router: Router(),
    port: port,
    host: host,
    authConfig: authConfig,
    connections: initTable[string, WebSocketConnection]()
  )
  initLock(transport.connectionsLock)
  return transport

import random

proc generateConnectionId(): string =
  ## Generate a unique connection ID
  return $rand(int.high)

proc validateWebSocketAuth(transport: WebSocketTransport, request: Request): tuple[valid: bool, errorMsg: string] =
  ## Validate WebSocket authentication during handshake
  if not transport.authConfig.enabled:
    return (true, "")
  
  # Check for Authorization header in WebSocket handshake
  if "Authorization" notin request.headers:
    return (false, "Authorization required: Bearer token missing")
  
  let authHeader = request.headers["Authorization"]
  if not authHeader.startsWith("Bearer "):
    return (false, "Authorization required: Bearer token format invalid")
  
  let token = authHeader[7..^1].strip()
  if token.len == 0:
    return (false, "Authorization required: empty token")
  
  # Validate token using configured validator
  if transport.authConfig.validator == nil:
    return (false, "Internal error: no token validator configured")
  
  try:
    if not transport.authConfig.validator(token):
      return (false, "Authorization required: token invalid")
  except:
    return (false, "Internal error: token validation failed")
  
  return (true, "")

proc addConnection(transport: WebSocketTransport, connection: WebSocketConnection) =
  ## Thread-safe connection addition
  withLock transport.connectionsLock:
    transport.connections[connection.id] = connection

proc removeConnection(transport: WebSocketTransport, connectionId: string) =
  ## Thread-safe connection removal
  withLock transport.connectionsLock:
    transport.connections.del(connectionId)

proc getConnection(transport: WebSocketTransport, connectionId: string): WebSocketConnection =
  ## Thread-safe connection retrieval
  withLock transport.connectionsLock:
    return transport.connections.getOrDefault(connectionId, nil)

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
    let connectionId = generateConnectionId()
    let connection = WebSocketConnection(
      websocket: websocket,
      id: connectionId,
      authenticated: true  # Authentication handled during handshake
    )
    transport.addConnection(connection)
    echo fmt"WebSocket connection opened: {connectionId}"
    
  of MessageEvent:
    # Handle JSON-RPC message
    if message.kind == TextMessage:
      transport.handleJsonRpcMessage(websocket, message.data)
    
  of CloseEvent:
    # Find and remove connection
    withLock transport.connectionsLock:
      for id, conn in transport.connections.pairs:
        if conn.websocket == websocket:
          echo fmt"WebSocket connection closed: {id}"
          transport.connections.del(id)
          break
    
  of ErrorEvent:
    # Find and remove connection on error
    withLock transport.connectionsLock:
      for id, conn in transport.connections.pairs:
        if conn.websocket == websocket:
          echo fmt"WebSocket error on connection {id}"
          transport.connections.del(id)
          break

proc upgradeHandler(transport: WebSocketTransport, request: Request) {.gcsafe.} =
  ## Handle WebSocket upgrade requests
  
  # Validate authentication during handshake
  let authResult = validateWebSocketAuth(transport, request)
  if not authResult.valid:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain"
    request.respond(401, headers, authResult.errorMsg)
    return
  
  # Upgrade to WebSocket - Mummy handles the upgrade internally
  let websocket = request.upgradeToWebSocket()
  
  # WebSocket events will be handled by the websocketEventHandler

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
  
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  headers["Access-Control-Allow-Origin"] = "*"
  
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
    var headers: HttpHeaders
    headers["Access-Control-Allow-Origin"] = "*"
    headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
    headers["Access-Control-Allow-Headers"] = "Content-Type, Accept, Origin, Authorization, Upgrade, Connection"
    request.respond(204, headers, "")
  )

proc serve*(transport: WebSocketTransport) =
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
  withLock transport.connectionsLock:
    for connection in transport.connections.values:
      try:
        connection.websocket.close()
      except:
        discard  # Ignore errors during shutdown
    transport.connections.clear()

proc runWebSocket*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()) =
  ## Convenience function to run an MCP server over WebSocket
  let transport = newWebSocketTransport(server, port, host, authConfig)
  try:
    transport.serve()
  finally:
    transport.shutdown()

proc broadcastToAll*(transport: WebSocketTransport, message: string) =
  ## Broadcast a message to all connected WebSocket clients
  withLock transport.connectionsLock:
    for connection in transport.connections.values:
      try:
        connection.websocket.send(message)
      except:
        # Remove failed connections
        discard

proc getActiveConnectionCount*(transport: WebSocketTransport): int =
  ## Get the number of active WebSocket connections
  withLock transport.connectionsLock:
    return transport.connections.len