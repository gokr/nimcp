## HTTP Streaming Transport with Server-Sent Events (SSE) for NimCP
## Provides real-time streaming capabilities over HTTP

import json, tables, options, strutils, asyncdispatch, asynchttpserver, asyncnet, random, times
import types, protocol, server, context, logging

type
  StreamingConnection* = object
    ## Represents a streaming connection
    id*: string
    response*: AsyncSocket
    isActive*: bool
    lastActivity*: float

  StreamingServer* = ref object
    ## HTTP server with streaming support
    mcpServer*: McpServer
    httpServer*: AsyncHttpServer
    connections*: Table[string, StreamingConnection]
    port*: int
    host*: string
    logger*: Logger

  StreamingMessage* = object
    ## Message for streaming over SSE
    event*: Option[string]
    data*: string
    id*: Option[string]
    retry*: Option[int]

proc newStreamingMessage*(data: string, event: Option[string] = none(string),
                         id: Option[string] = none(string),
                         retry: Option[int] = none(int)): StreamingMessage =
  ## Create a new streaming message
  StreamingMessage(
    event: event,
    data: data,
    id: id,
    retry: retry
  )

proc formatSSE*(msg: StreamingMessage): string =
  ## Format message for Server-Sent Events
  result = ""
  
  if msg.event.isSome:
    result.add("event: " & msg.event.get() & "\n")
  
  if msg.id.isSome:
    result.add("id: " & msg.id.get() & "\n")
  
  if msg.retry.isSome:
    result.add("retry: " & $msg.retry.get() & "\n")
  
  # Handle multi-line data
  for line in msg.data.split('\n'):
    result.add("data: " & line & "\n")
  
  result.add("\n")  # End message with double newline

proc newStreamingServer*(mcpServer: McpServer, port: int = 8080, host: string = "127.0.0.1"): StreamingServer =
  ## Create a new streaming server
  StreamingServer(
    mcpServer: mcpServer,
    httpServer: newAsyncHttpServer(),
    connections: initTable[string, StreamingConnection](),
    port: port,
    host: host,
    logger: newLogger(llInfo)
  )

proc generateConnectionId(): string =
  ## Generate a unique connection ID
  let timestamp = epochTime()
  let randomPart = rand(100000..999999)
  return "conn_" & $timestamp.int & "_" & $randomPart

proc addConnection*(server: StreamingServer, id: string, socket: AsyncSocket) =
  ## Add a new streaming connection
  server.connections[id] = StreamingConnection(
    id: id,
    response: socket,
    isActive: true,
    lastActivity: epochTime()
  )
  server.logger.info("New streaming connection", context = {"connectionId": %id}.toTable)

proc removeConnection*(server: StreamingServer, id: string) =
  ## Remove a streaming connection
  if id in server.connections:
    server.connections[id].isActive = false
    server.connections.del(id)
    server.logger.info("Streaming connection removed", context = {"connectionId": %id}.toTable)

proc broadcastMessage*(server: StreamingServer, msg: StreamingMessage) {.async.} =
  ## Broadcast a message to all active connections
  let formattedMsg = msg.formatSSE()
  var toRemove: seq[string] = @[]
  
  for connectionId, connection in server.connections:
    if connection.isActive:
      try:
        await connection.response.send(formattedMsg)
        server.connections[connectionId].lastActivity = epochTime()
      except:
        # Connection failed, mark for removal
        toRemove.add(connectionId)
        server.logger.warn("Failed to send to connection", 
          context = {"connectionId": %connectionId}.toTable)
  
  # Remove failed connections
  for connectionId in toRemove:
    server.removeConnection(connectionId)

proc sendToConnection*(server: StreamingServer, connectionId: string, msg: StreamingMessage) {.async.} =
  ## Send a message to a specific connection
  if connectionId in server.connections:
    let connection = server.connections[connectionId]
    if connection.isActive:
      try:
        let formattedMsg = msg.formatSSE()
        await connection.response.send(formattedMsg)
        server.connections[connectionId].lastActivity = epochTime()
      except:
        server.removeConnection(connectionId)
        server.logger.warn("Failed to send to connection", 
          context = {"connectionId": %connectionId}.toTable)

proc handleStreamingRequest(server: StreamingServer, req: Request) {.async.} =
  ## Handle incoming streaming requests
  case req.url.path:
  of "/events":
    # Server-Sent Events endpoint
    let connectionId = generateConnectionId()
    
    # Set SSE headers
    let headers = "HTTP/1.1 200 OK\r\n" &
                 "Content-Type: text/event-stream\r\n" &
                 "Cache-Control: no-cache\r\n" &
                 "Connection: keep-alive\r\n" &
                 "Access-Control-Allow-Origin: *\r\n" &
                 "\r\n"
    
    await req.client.send(headers)
    
    # Add connection to server
    server.addConnection(connectionId, req.client)
    
    # Send initial connection message
    let welcomeMsg = newStreamingMessage(
      data = $(%{"type": %"connection", "connectionId": %connectionId}),
      event = some("connected"),
      id = some(connectionId)
    )
    await server.sendToConnection(connectionId, welcomeMsg)
    
    # Keep connection alive
    try:
      while server.connections.hasKey(connectionId) and server.connections[connectionId].isActive:
        await sleepAsync(1000)  # Check every second
        
        # Send periodic heartbeat
        let heartbeat = newStreamingMessage(
          data = $(%{"type": %"heartbeat", "timestamp": %epochTime()}),
          event = some("heartbeat")
        )
        await server.sendToConnection(connectionId, heartbeat)
    except:
      server.removeConnection(connectionId)
  
  of "/api/stream":
    # MCP streaming endpoint
    if req.reqMethod == HttpPost:
      try:
        let body = req.body
        let jsonRequest = parseJson(body)
        
        # Process MCP request using the main server
        let mcpRequest = jsonRequest.to(JsonRpcRequest)
        let mcpResponse = server.mcpServer.handleRequest(mcpRequest)
        
        # Send response as SSE
        let responseMsg = newStreamingMessage(
          data = $mcpResponse,
          event = some("mcp-response"),
          id = mcpRequest.id.map(proc(id: JsonRpcId): string = $id)
        )
        
        await server.broadcastMessage(responseMsg)
        
        # Also send regular HTTP response
        await req.respond(Http200, $mcpResponse, 
          newHttpHeaders([("Content-Type", "application/json")]))
      except Exception as e:
        let errorResponse = %{"error": %{"code": %(-32603), "message": %e.msg}}
        await req.respond(Http500, $errorResponse,
          newHttpHeaders([("Content-Type", "application/json")]))
    else:
      await req.respond(Http405, "Method Not Allowed")
  
  else:
    # Regular MCP HTTP endpoint (non-streaming)
    if req.reqMethod == HttpPost:
      try:
        let body = req.body
        let jsonRequest = parseJson(body)
        
        let mcpRequest = jsonRequest.to(JsonRpcRequest)
        let mcpResponse = server.mcpServer.handleRequest(mcpRequest)
        
        await req.respond(Http200, $mcpResponse,
          newHttpHeaders([("Content-Type", "application/json")]))
      except Exception as e:
        let errorResponse = %{"error": %{"code": %(-32603), "message": %e.msg}}
        await req.respond(Http500, $errorResponse,
          newHttpHeaders([("Content-Type", "application/json")]))
    else:
      await req.respond(Http405, "Method Not Allowed")

proc cleanupConnections*(server: StreamingServer) =
  ## Clean up inactive connections
  let currentTime = epochTime()
  var toRemove: seq[string] = @[]
  
  for connectionId, connection in server.connections:
    if currentTime - connection.lastActivity > 300:  # 5 minutes timeout
      toRemove.add(connectionId)
  
  for connectionId in toRemove:
    server.removeConnection(connectionId)

proc startStreamingServer*(server: StreamingServer) {.async.} =
  ## Start the streaming HTTP server
  server.logger.info("Starting streaming server", 
    context = {"host": %server.host, "port": %server.port}.toTable)
  
  # Set up request handler
  proc requestHandler(req: Request) {.async.} =
    await server.handleStreamingRequest(req)
  
  await server.httpServer.serve(Port(server.port), requestHandler, server.host)

proc stopStreamingServer*(server: StreamingServer) =
  ## Stop the streaming server
  server.logger.info("Stopping streaming server")
  server.httpServer.close()
  
  # Close all connections
  for connectionId in server.connections.keys:
    server.removeConnection(connectionId)

# Convenience functions for sending different types of messages

proc sendToolResult*(server: StreamingServer, toolName: string, toolResult: McpToolResult, 
                    connectionId: Option[string] = none(string)) {.async.} =
  ## Send a tool execution result via streaming
  let msg = newStreamingMessage(
    data = $(%toolResult),
    event = some("tool-result"),
    id = some("tool-" & toolName)
  )
  
  if connectionId.isSome:
    await server.sendToConnection(connectionId.get(), msg)
  else:
    await server.broadcastMessage(msg)

proc sendResourceUpdate*(server: StreamingServer, uri: string, content: McpResourceContents,
                        connectionId: Option[string] = none(string)) {.async.} =
  ## Send a resource update via streaming
  let msg = newStreamingMessage(
    data = $(%content),
    event = some("resource-update"),
    id = some("resource-" & uri)
  )
  
  if connectionId.isSome:
    await server.sendToConnection(connectionId.get(), msg)
  else:
    await server.broadcastMessage(msg)

proc sendProgressUpdate*(server: StreamingServer, requestId: string, message: string, 
                        progress: float, connectionId: Option[string] = none(string)) {.async.} =
  ## Send a progress update via streaming
  let progressData = %{
    "requestId": %requestId,
    "message": %message,
    "progress": %progress,
    "timestamp": %epochTime()
  }
  
  let msg = newStreamingMessage(
    data = $progressData,
    event = some("progress"),
    id = some("progress-" & requestId)
  )
  
  if connectionId.isSome:
    await server.sendToConnection(connectionId.get(), msg)
  else:
    await server.broadcastMessage(msg)

proc sendLogMessage*(server: StreamingServer, logMsg: LogMessage,
                    connectionId: Option[string] = none(string)) {.async.} =
  ## Send a log message via streaming
  let logData = %{
    "level": %($logMsg.level),
    "message": %logMsg.message,
    "timestamp": %logMsg.timestamp.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "component": %logMsg.component.get(""),
    "requestId": %logMsg.requestId.get(""),
    "context": %logMsg.context
  }
  
  let msg = newStreamingMessage(
    data = $logData,
    event = some("log"),
    id = some("log-" & $epochTime().int)
  )
  
  if connectionId.isSome:
    await server.sendToConnection(connectionId.get(), msg)
  else:
    await server.broadcastMessage(msg)

# Integration with MCP server for automatic streaming

proc enableStreaming*(mcpServer: McpServer, port: int = 8080, host: string = "127.0.0.1"): StreamingServer =
  ## Enable streaming for an MCP server
  let streamingServer = newStreamingServer(mcpServer, port, host)
  
  # Add streaming log handler to the MCP server
  mcpServer.addLogHandler(proc(msg: LogMessage) =
    asyncCheck streamingServer.sendLogMessage(msg)
  )
  
  return streamingServer

# Example usage functions

proc runStreamingServer*(server: StreamingServer) {.async.} =
  ## Run the streaming server with automatic cleanup
  # Start cleanup task
  proc cleanupTask() {.async.} =
    while true:
      await sleepAsync(60000)  # Clean up every minute
      server.cleanupConnections()
  
  asyncCheck cleanupTask()
  
  # Start the server
  await server.startStreamingServer()