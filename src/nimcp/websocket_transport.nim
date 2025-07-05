

## WebSocket Transport Implementation for MCP Servers
##
## This module provides a WebSocket-based transport layer for Model Context Protocol (MCP) servers.
## It enables real-time, bidirectional communication between MCP clients and servers over WebSocket
## connections, built on top of the Mummy web framework.
##
## Key Features:
## - **WebSocket Communication**: Full-duplex communication for real-time MCP interactions
## - **JSON-RPC Protocol**: Handles JSON-RPC 2.0 messages over WebSocket connections
## - **Connection Management**: Maintains a pool of active WebSocket connections with unique IDs
## - **Authentication Support**: Integrates with the auth module for Bearer token authentication
## - **CORS Support**: Handles cross-origin requests for web-based MCP clients
## - **Dual Endpoints**: Supports both WebSocket upgrades and HTTP info requests on the same endpoint
## - **Error Handling**: Robust error handling with proper JSON-RPC error responses
## - **Broadcasting**: Ability to broadcast messages to all connected clients
##
## Usage:
## ```nim
## let server = newMcpServer("MyServer", "1.0.0")
## # Add tools and resources to server...
##
## # Run with default settings
## server.runWebSocket()
##
## # Or with custom configuration
## let authConfig = newAuthConfig(enabled = true, bearerToken = "secret")
## server.runWebSocket(port = 8080, host = "0.0.0.0", authConfig = authConfig)
## ```
##
## The transport automatically handles:
## - WebSocket handshake and upgrade from HTTP
## - Connection lifecycle (open, message, close, error events)
## - JSON-RPC message parsing and response formatting
## - Authentication validation during connection establishment
## - Connection cleanup on errors or disconnections
##
## Clients can connect using standard WebSocket libraries and send JSON-RPC 2.0 formatted
## messages to interact with the MCP server's tools and resources.

import mummy, mummy/routers, json, strutils, strformat, options, tables, locks
import server, types, protocol
import auth, connection_pool, cors, http_common
type
  WebSocketConnection* = ref object
    ## Represents an active WebSocket connection
    websocket*: WebSocket
    id*: string
    authenticated*: bool
    
  WebSocketTransport* = ref object
    ## WebSocket transport implementation for MCP servers  
    base*: HttpServerBase
    connectionPool: ConnectionPool[WebSocketConnection]

# Reuse authentication types from mummy_transport
proc newWebSocketTransport*(port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()): WebSocketTransport =
  ## Create a new WebSocket transport instance
  var transport = WebSocketTransport(
    base: newHttpServerBase(port, host, authConfig, @[]),
    connectionPool: newConnectionPool[WebSocketConnection]()
  )
  return transport

# Forward declaration for the event sending function
proc sendEventToWebSocketClients(transport: WebSocketTransport, eventType: string, data: JsonNode, target: string = "") {.gcsafe.}

proc wsEventWrapper(transportPtr: pointer, eventType: string, data: JsonNode, target: string = "") {.gcsafe.} =
  ## Wrapper function for WebSocket event sending that matches function pointer signature
  let transport = cast[WebSocketTransport](transportPtr)
  transport.sendEventToWebSocketClients(eventType, data, target)




proc handleJsonRpcMessage(transport: WebSocketTransport, server: McpServer, websocket: WebSocket, message: string) {.gcsafe.} =
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
      server.handleNotification(jsonRpcRequest)
      return
    
    # Handle requests that expect responses with transport access
    let capabilities = {tcBidirectional, tcUnicast, tcEvents}  # WebSocket supports bidirectional real-time events
    let mcpTransport = McpTransport(kind: tkWebSocket, capabilities: capabilities,
      wsTransport: cast[pointer](transport), wsSendEvent: wsEventWrapper)
    let response = server.handleRequest(mcpTransport, jsonRpcRequest)
    
    # Send response back through WebSocket
    websocket.send($response)
    
  except JsonParsingError as e:
    let errorResponse = createParseError(details = e.msg)
    websocket.send($(%errorResponse))
  except Exception as e:
    let errorResponse = createInternalError(JsonRpcId(kind: jridString, str: ""), e.msg)
    websocket.send($(%errorResponse))

proc websocketEventHandler(transport: WebSocketTransport, server: McpServer, websocket: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} =
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
      transport.handleJsonRpcMessage(server, websocket, message.data)
    
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
  let (valid, errorCode, errorMsg) = transport.base.validateAuthentication(request)
  if not valid:
    var headers: HttpHeaders
    headers["Content-Type"] = "text/plain"
    request.respond(errorCode, headers, errorMsg)
    return
  
  # Upgrade to WebSocket - Mummy handles the upgrade internally
  discard request.upgradeToWebSocket()

proc handleInfoRequest(transport: WebSocketTransport, server: McpServer, request: Request) {.gcsafe.} =
  ## Handle GET requests for server info
  let info = %*{
    "server": {
      "name": server.serverInfo.name,
      "version": server.serverInfo.version
    },
    "transport": "websocket",
    "capabilities": server.capabilities,
    "websocket": {
      "endpoint": fmt"ws://{transport.base.host}:{transport.base.port}/",
      "authentication": transport.base.authConfig.enabled
    }
  }
  
  var headers = defaultCorsHeaders()
  headers["Content-Type"] = "application/json"
  
  request.respond(200, headers, $info)

proc setupRoutes(transport: WebSocketTransport, server: McpServer) =
  ## Set up WebSocket and HTTP routes
  
  # WebSocket/HTTP endpoint
  transport.base.router.get("/", proc(request: Request) {.gcsafe.} = 
    if "Upgrade" in request.headers and request.headers["Upgrade"].toLowerAscii() == "websocket":
      transport.upgradeHandler(request)
    else:
      transport.handleInfoRequest(server, request)
  )
  
  # OPTIONS for CORS
  transport.base.router.options("/", proc(request: Request) {.gcsafe.} =
    let headers = corsHeadersFor("GET, OPTIONS", "Content-Type, Accept, Origin, Authorization, Upgrade, Connection")
    request.respond(204, headers, "")
  )

proc sendEventToWebSocketClients(transport: WebSocketTransport, eventType: string, data: JsonNode, target: string = "") {.gcsafe.} =
  ## Send MCP notification to all WebSocket clients
  let notification = %*{
    "jsonrpc": "2.0",
    "method": "notifications/message",
    "params": %*{
      "type": eventType,
      "data": data
    }
  }
  
  # Send to all WebSocket connections
  for connection in transport.connectionPool.connections():
    try:
      connection.websocket.send($notification)
    except:
      discard  # Connection might be closed


proc serve*(transport: WebSocketTransport, server: McpServer) =
  ## Serve the WebSocket server
  transport.setupRoutes(server)
  
  
  # Create server with WebSocket handler
  let wsHandler = proc(websocket: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} =
    transport.websocketEventHandler(server, websocket, event, message)
  
  transport.base.startServer(wsHandler)

proc shutdown*(transport: WebSocketTransport) =
  ## Shutdown the WebSocket server and close all connections
  if transport.base.httpServer != nil:
    transport.base.httpServer.close()
  
  
  # Close all active WebSocket connections
  for connection in transport.connectionPool.connections():
    try:
      connection.websocket.close()
    except:
      discard  # Ignore errors during shutdown
  transport.connectionPool = newConnectionPool[WebSocketConnection]()


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