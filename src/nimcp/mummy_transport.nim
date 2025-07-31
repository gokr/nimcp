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

import mummy, mummy/routers, json, strutils, strformat, options, tables, times, random, os
import server, types, protocol, auth, cors, http_common

# Thread-local storage for current HTTP request (safe for concurrent requests)
var currentHTTPRequest {.threadvar.}: Request
var currentSessionId {.threadvar.}: string

type
  StreamingConnection* = ref object
    request*: Request
    sseConnection*: SSEConnection  # Proper SSE connection
    sessionId*: string
    isActive*: bool
    lastActivity*: times.Time
  
  MummyTransport* = ref object
    base*: HttpServerBase
    connections*: Table[string, StreamingConnection]  # Active streaming connections

# Forward declarations
proc sendNotification(transport: MummyTransport, sseConnection: SSEConnection, notificationType: string, data: JsonNode) {.gcsafe.}
proc writeSSEEvent(sseConnection: SSEConnection, eventType: string, data: string, eventId: string = "") {.gcsafe.}
proc writeSSENotification(sseConnection: SSEConnection, notification: JsonNode, eventId: string = "") {.gcsafe.}
proc sendProgressNotification(transport: MummyTransport, sseConnection: SSEConnection, progressToken: JsonNode, progress: JsonNode, total: JsonNode = nil, message: string = "") {.gcsafe.}
proc sendLoggingNotification(transport: MummyTransport, sseConnection: SSEConnection, data: JsonNode, level: string = "info", logger: string = "") {.gcsafe.}

proc httpNotificationWrapper(ctx: McpRequestContext, notificationType: string, data: JsonNode) {.gcsafe.} =
  ## Wrapper function for HTTP notification sending that matches function pointer signature
  echo "\n=== HTTP NOTIFICATION WRAPPER ==="
  echo fmt"Notification type: {notificationType}"
  echo fmt"Data: {data}"
  echo fmt"Current request context exists: {currentHTTPRequest != nil}"
  echo fmt"Session ID: {ctx.sessionId}"
  
  let transport = cast[MummyTransport](ctx.transport.httpTransport)
  
  # Try to send to specific session first if we have one from context
  var targetSessionId = ctx.sessionId
  if targetSessionId.len == 0:
    targetSessionId = currentSessionId
    echo fmt"Using thread-local session ID: {targetSessionId}"
  
  if targetSessionId.len > 0 and targetSessionId in transport.connections:
    let connection = transport.connections[targetSessionId]
    if connection.isActive and connection.sseConnection.active:
      echo fmt"Sending notification to active session: {targetSessionId}"
      # Route to appropriate notification function based on type
      if notificationType == "progress":
        # Extract progress notification fields
        let progress = data["progress"]
        let progressToken = if data.hasKey("progressToken"): data["progressToken"] else: newJNull()
        let total = if data.hasKey("total"): data["total"] else: nil
        let message = if data.hasKey("message"): data["message"].getStr() else: ""
        transport.sendProgressNotification(connection.sseConnection, progressToken, progress, total, message)
      else:
        # Send as general message notification
        transport.sendNotification(connection.sseConnection, notificationType, data)
      return
    else:
      echo fmt"Connection for session {targetSessionId} is inactive or SSE closed"
  
  # For non-session requests, we can't send real-time notifications
  echo "WARNING: HTTP notification requested but no active SSE connection available"
  echo fmt"Available sessions: {transport.connections.len}"
  for sessionId, conn in transport.connections:
    echo fmt"  - {sessionId}: active={conn.isActive}, sse_active={conn.sseConnection.active}"

proc newMummyTransport*(port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig(), allowedOrigins: seq[string] = @[]): MummyTransport =
  var transport = MummyTransport(
    base: newHttpServerBase(port, host, authConfig, allowedOrigins),
    connections: initTable[string, StreamingConnection]()
  )
  return transport

proc writeSSEEvent(sseConnection: SSEConnection, eventType: string, data: string, eventId: string = "") {.gcsafe.} =
  ## Write a Server-Sent Event using Mummy's proper SSE API
  try:
    if sseConnection.active:
      let event = SSEEvent(
        event: if eventType != "": some(eventType) else: none(string),
        data: data,
        id: if eventId != "": some(eventId) else: none(string)
      )
      sseConnection.send(event)
      echo fmt"SSE Event sent: {eventType} - {data.substr(0, min(100, data.len))}"
    else:
      echo "SSE Connection is not active, cannot send event"
  except Exception as e:
    echo fmt"Failed to write SSE event: {e.msg}"

proc writeSSENotification(sseConnection: SSEConnection, notification: JsonNode, eventId: string = "") {.gcsafe.} =
  ## Write an MCP notification as SSE event
  let notificationStr = $notification
  writeSSEEvent(sseConnection, "message", notificationStr, eventId)
proc validateOrigin(transport: MummyTransport, request: Request): bool =
  ## Validate Origin header to prevent DNS rebinding attacks
  return transport.base.validateOrigin(request)

proc parseAcceptHeader(acceptHeader: string): seq[tuple[mediaType: string, quality: float]] =
  ## Parse Accept header with quality values
  result = @[]
  let parts = acceptHeader.split(",")
  
  for part in parts:
    let trimmed = part.strip()
    let components = trimmed.split(";")
    if components.len > 0:
      let mediaType = components[0].strip()
      var quality = 1.0
      
      # Parse quality value if present
      if components.len > 1:
        for component in components[1..^1]:
          let qPair = component.strip().split("=")
          if qPair.len == 2 and qPair[0].strip() == "q":
            try:
              quality = parseFloat(qPair[1].strip())
            except:
              quality = 1.0
      
      result.add((mediaType, quality))

proc clientSupportsStreaming(request: Request): bool =
  ## Check if client supports SSE streaming (regardless of preference)
  if "Accept" notin request.headers:
    return false
  
  let acceptHeader = request.headers["Accept"]
  let acceptedTypes = parseAcceptHeader(acceptHeader)
  
  # Check if text/event-stream is accepted at all
  for (mediaType, quality) in acceptedTypes:
    if mediaType == "text/event-stream" and quality > 0.0:
      return true
    elif mediaType == "*/*" and quality > 0.0:
      return true
  
  return false

proc supportsStreaming(request: Request): bool =
  ## Check if client prefers SSE streaming over JSON via Accept header parsing
  ## Returns true only if text/event-stream has higher quality than application/json
  ## or if text/event-stream is present and application/json is not
  echo "=== STREAMING SUPPORT CHECK ==="
  if "Accept" notin request.headers:
    echo "No Accept header found - defaulting to JSON mode"
    return false
  
  let acceptHeader = request.headers["Accept"]
  echo fmt"Accept header: {acceptHeader}"
  
  # Parse the Accept header properly
  let acceptedTypes = parseAcceptHeader(acceptHeader)
  echo "Parsed Accept types:"
  for (mediaType, quality) in acceptedTypes:
    echo fmt"  {mediaType} (q={quality})"
  
  # Find quality values for both JSON and SSE
  var jsonQuality = 0.0
  var sseQuality = 0.0
  var hasWildcard = false
  
  for (mediaType, quality) in acceptedTypes:
    case mediaType:
    of "application/json":
      jsonQuality = quality
    of "text/event-stream":
      sseQuality = quality
    of "*/*":
      hasWildcard = true
      # Wildcards support both, but we prefer JSON by default
  
  echo fmt"Quality scores: JSON={jsonQuality}, SSE={sseQuality}, Wildcard={hasWildcard}"
  
  # Decision logic:
  # 1. If SSE quality > JSON quality, use streaming
  # 2. If only SSE is present (no JSON), use streaming  
  # 3. If both are equal or JSON is higher, use JSON
  # 4. If wildcard only, use JSON (more compatible)
  
  if sseQuality > 0.0 and jsonQuality == 0.0:
    echo "Streaming mode: SSE requested, no JSON preference"
    return true
  elif sseQuality > jsonQuality:
    echo fmt"Streaming mode: SSE quality ({sseQuality}) > JSON quality ({jsonQuality})"
    return true
  else:
    echo fmt"JSON mode: JSON preferred (JSON q={jsonQuality}, SSE q={sseQuality})"
    return false

proc getSessionId(request: Request): string =
  ## Extract session ID from Mcp-Session-Id header if present
  echo "=== SESSION ID EXTRACTION ==="
  if "Mcp-Session-Id" in request.headers:
    let sessionId = request.headers["Mcp-Session-Id"]
    echo fmt"Found session ID: {sessionId}"
    return sessionId
  echo "No session ID header found"
  return ""

proc validateAuthentication(transport: MummyTransport, request: Request): tuple[valid: bool, errorCode: int, errorMsg: string] =
  ## Validate authentication using shared auth module
  return transport.base.validateAuthentication(request)

proc handleJsonRequest(transport: MummyTransport, server: McpServer, request: Request, jsonRpcRequest: JsonRpcRequest, sessionId: string) {.gcsafe.} =
  ## Handle regular JSON response mode
  echo "\n=== JSON REQUEST HANDLER ==="
  echo fmt"Request ID: {jsonRpcRequest.id}"
  echo fmt"Method: {jsonRpcRequest.`method`}"
  
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  headers["Content-Type"] = "application/json"
  
  if sessionId != "":
    echo fmt"Using session ID: {sessionId}"
    headers["Mcp-Session-Id"] = sessionId
  else:
    echo "No session ID in JSON mode"
  
  # Set thread-local request context for notifications
  currentHTTPRequest = request
  echo "Set current HTTP request context for notifications"
  
  # Use the existing server's request handler with transport access
  echo "=== TRANSPORT CONFIGURATION ==="
  let capabilities = {tcEvents, tcUnicast}
  echo fmt"Transport capabilities: {capabilities}"
  let mcpTransport = McpTransport(kind: tkHttp, capabilities: capabilities, 
    httpTransport: cast[pointer](transport), httpSendNotification: httpNotificationWrapper)
  echo fmt"Created transport with kind: {mcpTransport.kind}"
  
  echo "=== REQUEST PROCESSING ==="
  echo "Calling server.handleRequest..."
  let response = server.handleRequest(mcpTransport, jsonRpcRequest)
  echo fmt"Response received - ID: {response.id}, Error present: {response.error.isSome}"
  
  # Only send a response if it's not empty (i.e., not a notification)
  if response.id.kind != jridString or response.id.str != "":
    echo fmt"Sending 200 response with body length: {($response).len}"
    request.respond(200, headers, $response)
  else:
    echo "Sending 204 No Content (notification response)"
    # For notifications, just return 204 No Content
    request.respond(204, headers, "")


proc handleStreamingRequest(transport: MummyTransport, server: McpServer, request: Request, jsonRpcRequest: JsonRpcRequest, sessionId: string) {.gcsafe.} =
  ## Handle single POST request with SSE streaming (MCP specification)
  echo "\n=== STREAMING REQUEST HANDLER ==="
  echo fmt"Request ID: {jsonRpcRequest.id}"
  echo fmt"Method: {jsonRpcRequest.`method`}"
  
  # Create SSE connection for this POST request
  echo "Creating SSE connection using Mummy's respondSSE()"
  let sseConnection = request.respondSSE()
  
  # Generate session ID for tracking (optional for single-request streams)  
  let actualSessionId = if sessionId != "": sessionId else: "sse-" & $sseConnection.clientId
  
  # Track this connection temporarily (for notifications during processing)
  let connection = StreamingConnection(
    request: request,
    sseConnection: sseConnection,
    sessionId: actualSessionId,
    isActive: true,
    lastActivity: getTime()
  )
  transport.connections[actualSessionId] = connection
  echo fmt"Created SSE connection for POST request: {actualSessionId}"
  echo fmt"SSE connection active: {sseConnection.active}"
  
  # Set thread-local request context for notifications
  currentHTTPRequest = request
  currentSessionId = actualSessionId
  echo fmt"Set request context for notifications: {actualSessionId}"
  
  try:
    # Handle the request with transport access
    echo "=== STREAMING TRANSPORT CONFIGURATION ==="
    let capabilities = {tcEvents, tcUnicast}
    echo fmt"Transport capabilities: {capabilities}"
    let mcpTransport = McpTransport(kind: tkHttp, capabilities: capabilities, 
      httpTransport: cast[pointer](transport), httpSendNotification: httpNotificationWrapper)
    echo fmt"Created streaming transport with kind: {mcpTransport.kind}"
    
    echo "=== STREAMING REQUEST PROCESSING ==="
    echo "Calling server.handleRequest for streaming..."
    let response = server.handleRequest(mcpTransport, jsonRpcRequest)
    echo fmt"Streaming response received - ID: {response.id}, Error present: {response.error.isSome}"
    
    # Send the final response as an SSE event, then close the stream per MCP spec
    if response.id.kind != jridString or response.id.str != "":
      echo fmt"Sending final response as SSE event for request ID: {response.id}"
      let responseStr = $response
      let finalEventId = case response.id.kind:
        of jridInt: $response.id.num
        of jridString: response.id.str
      writeSSEEvent(sseConnection, "message", responseStr, finalEventId)
      echo fmt"Sent final SSE response with body length: {responseStr.len}"
    else:
      echo "Sending completion event for notification-only response"
      let completeEventId = fmt"complete-{getTime().toUnix()}"
      writeSSEEvent(sseConnection, "complete", "{\"status\": \"complete\"}", completeEventId)
    
    # Per MCP spec: "After all JSON-RPC responses have been sent, the server SHOULD close the SSE stream"
    echo "All responses sent - closing SSE stream per MCP specification"
    
  except Exception as e:
    echo fmt"Streaming request error: {e.msg}"
    # Send error as SSE event, then close stream  
    if sseConnection.active:
      let errorEvent = %*{
        "jsonrpc": "2.0",
        "id": $jsonRpcRequest.id,
        "error": {
          "code": -32603,
          "message": "Internal error",
          "data": e.msg
        }
      }
      writeSSEEvent(sseConnection, "error", $errorEvent)
      echo "Error sent via SSE - stream will close"
    
    # Clean up and let stream close naturally
  
  finally:
    # Clean up connection tracking  
    if actualSessionId in transport.connections:
      transport.connections.del(actualSessionId)
      echo fmt"Removed connection: {actualSessionId}"
  
  echo "SSE stream closed - POST request completed"

proc handleMcpRequest(transport: MummyTransport, server: McpServer, request: Request) {.gcsafe.} =
  echo "\n=== INCOMING MCP REQUEST ==="
  echo fmt"Method: {request.httpMethod}"
  echo fmt"Path: {request.path}"
  echo "Headers:"
  for key, value in request.headers.pairs:
    echo fmt"  {key}: {value}"
  echo fmt"Body length: {request.body.len}"
  if request.body.len > 0 and request.body.len < 200:
    echo fmt"Body preview: {request.body}"
  
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  
  # DNS rebinding protection (skip for OPTIONS requests)
  if request.httpMethod != "OPTIONS" and not transport.validateOrigin(request):
    echo "Origin validation failed"
    headers["Content-Type"] = "text/plain"
    request.respond(403, headers, "Forbidden: Invalid origin")
    return
  
  # Authentication validation (skip for OPTIONS requests)
  if request.httpMethod != "OPTIONS":
    let authResult = validateAuthentication(transport, request)
    if not authResult.valid:
      echo fmt"Authentication failed: {authResult.errorMsg}"
      headers["Content-Type"] = "text/plain"
      let errorMsg = if authResult.errorCode in transport.base.authConfig.customErrorResponses:
                      transport.base.authConfig.customErrorResponses[authResult.errorCode]
                    else:
                      authResult.errorMsg
      request.respond(authResult.errorCode, headers, errorMsg)
      return
    echo "Authentication successful"
  
  # Determine response mode based on Accept header
  let streamingSupported = supportsStreaming(request)
  let clientCanStream = clientSupportsStreaming(request)
  let sessionId = getSessionId(request)
  
  case request.httpMethod:
    of "OPTIONS":
      request.respond(204, headers, "")
      
    of "GET":
      # Check if this is an SSE resume request
      if "Last-Event-ID" in request.headers:
        let lastEventId = request.headers["Last-Event-ID"]
        echo fmt"SSE resume request with Last-Event-ID: {lastEventId}"
        
        # Per MCP spec: streams are closed after responses are sent
        # Resume requests for completed streams should return 404
        echo "Stream no longer available (POST request completed)"
        headers["Content-Type"] = "text/plain"
        request.respond(404, headers, "Stream no longer available")
        return
      else:
        # Return server info for GET requests
        headers["Content-Type"] = "application/json"
        let info = %*{
          "server": {
            "name": server.serverInfo.name,
            "version": server.serverInfo.version
          },
          "transport": "streamable-http",
          "capabilities": server.capabilities,
          "streaming": clientCanStream
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
        
        # Handle based on streaming support and request type
        echo "=== RESPONSE MODE SELECTION ==="
        echo fmt"Streaming supported: {streamingSupported}"
        echo fmt"Client can stream: {clientCanStream}"
        echo fmt"Method: {jsonRpcRequest.`method`}"
        echo fmt"Session ID: {sessionId}"
        echo fmt"Active connections: {transport.connections.len}"
        if sessionId != "" and sessionId in transport.connections:
          echo fmt"Found existing connection for session: {sessionId}"
        
        # Force streaming mode for context-aware tool calls if client supports it
        # Context-aware tools are designed to send notifications during processing
        var forceStreaming = false
        if clientCanStream and jsonRpcRequest.`method` == "tools/call":
          if jsonRpcRequest.params.isSome and jsonRpcRequest.params.get().hasKey("name"):
            let toolName = jsonRpcRequest.params.get()["name"].getStr()
            # Check if this is a context-aware tool (these can send notifications)
            if toolName in server.contextAwareToolHandlers:
              forceStreaming = true
              echo fmt"Forcing streaming mode for context-aware tool: {toolName}"
            else:
              echo fmt"Regular tool call, not forcing streaming: {toolName}"
        
        if forceStreaming or streamingSupported:
          echo "Using streaming mode (per-POST SSE stream)"
          handleStreamingRequest(transport, server, request, jsonRpcRequest, sessionId)
        else:
          echo "Using regular JSON response mode"
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

proc sendNotification(transport: MummyTransport, sseConnection: SSEConnection, notificationType: string, data: JsonNode) {.gcsafe.} =
  ## Send MCP notification to HTTP client via SSE
  echo "\n=== SEND NOTIFICATION ==="
  echo fmt"Notification type: {notificationType}"
  echo fmt"Data: {data}"
  echo fmt"SSE connection active: {sseConnection.active}"
  echo fmt"Transport connections count: {transport.connections.len}"
  
  # Log all current connections
  if transport.connections.len > 0:
    echo "Active connections:"
    for sessionId, conn in transport.connections:
      echo fmt"  Session: {sessionId} (active: {conn.isActive}, SSE active: {conn.sseConnection.active})"
  else:
    echo "No active connections for notifications"
  
  # Create MCP notification in proper format per specification
  let notification = %*{
    "jsonrpc": "2.0",
    "method": "notifications/message",
    "params": %*{
      "level": "info",
      "logger": "nimcp-demo",
      "data": data
    }
  }
  
  # Send notification via SSE with event ID
  let eventId = fmt"notify-{getTime().toUnix()}-{rand(1000)}"
  echo "Sending notification via SSE event"
  writeSSENotification(sseConnection, notification, eventId)
  echo fmt"SSE notification sent: {notificationType} - {data}"

proc sendProgressNotification(transport: MummyTransport, sseConnection: SSEConnection, progressToken: JsonNode, progress: JsonNode, total: JsonNode = nil, message: string = "") {.gcsafe.} =
  ## Send progress notification according to MCP specification
  ## Required fields: progress, progressToken
  ## Optional fields: total, message
  echo "\n=== SEND PROGRESS NOTIFICATION ==="
  echo fmt"Progress: {progress}, Token: {progressToken}"
  if total != nil: echo fmt"Total: {total}"
  if message.len > 0: echo fmt"Message: {message}"
  
  let params = %*{
    "progress": progress,
    "progressToken": progressToken
  }
  
  if total != nil:
    params["total"] = total
  if message.len > 0:
    params["message"] = %message
  
  let notification = %*{
    "jsonrpc": "2.0",
    "method": "notifications/progress",
    "params": params
  }
  
  let eventId = fmt"progress-{getTime().toUnix()}-{rand(1000)}"
  writeSSENotification(sseConnection, notification, eventId)
  echo "Progress notification sent via SSE"

proc sendLoggingNotification(transport: MummyTransport, sseConnection: SSEConnection, data: JsonNode, level: string = "info", logger: string = "") {.gcsafe.} =
  ## Send logging notification according to MCP specification
  ## Required fields: data, level
  ## Optional field: logger
  echo "\n=== SEND LOGGING NOTIFICATION ==="
  echo fmt"Data: {data}, Level: {level}"
  if logger.len > 0: echo fmt"Logger: {logger}"
  
  let params = %*{
    "data": data,
    "level": level
  }
  
  if logger.len > 0:
    params["logger"] = %logger
  
  let notification = %*{
    "jsonrpc": "2.0",
    "method": "notifications/message",
    "params": params
  }
  
  let eventId = fmt"log-{getTime().toUnix()}-{rand(1000)}"
  writeSSENotification(sseConnection, notification, eventId)
  echo "Logging notification sent via SSE"

proc sendNotificationToSession*(transport: MummyTransport, sessionId: string, notificationType: string, data: JsonNode) {.gcsafe.} =
  ## Send MCP notification to specific session via SSE
  echo "\n=== SEND NOTIFICATION TO SESSION ==="
  echo fmt"Target session ID: {sessionId}"
  echo fmt"Notification type: {notificationType}"
  echo fmt"Data: {data}"
  echo fmt"Transport connections count: {transport.connections.len}"
  
  # Check if we have an active connection for this session
  if sessionId in transport.connections:
    let connection = transport.connections[sessionId]
    if connection.isActive and connection.sseConnection.active:
      echo fmt"Found active streaming connection for session {sessionId}"
      echo fmt"Connection method: {connection.request.httpMethod}"
      echo fmt"Connection path: {connection.request.path}"
      echo fmt"SSE connection active: {connection.sseConnection.active}"
      echo "Sending notification via SSE to active connection"
      
      # Create MCP notification in proper format per specification
      let notification = %*{
        "jsonrpc": "2.0",
        "method": "notifications/message",
        "params": %*{
          "level": "info",
          "logger": "nimcp-demo",
          "data": data
        }
      }
      
      # Send as SSE event with event ID
      let eventId = fmt"session-notify-{getTime().toUnix()}-{rand(1000)}"
      writeSSENotification(connection.sseConnection, notification, eventId)
      connection.lastActivity = getTime()
      echo "Notification sent via SSE stream"
    else:
      echo fmt"Connection for session {sessionId} is inactive or SSE connection closed"
  else:
    echo fmt"No active connection found for session {sessionId}"
    if transport.connections.len > 0:
      echo "Available sessions:"
      for availableSessionId in transport.connections.keys:
        let conn = transport.connections[availableSessionId]
        echo fmt"  - {availableSessionId} (active: {conn.isActive})"
    else:
      echo "No active sessions at all"

proc cleanupInactiveConnections*(transport: MummyTransport) =
  ## Clean up connections that are no longer active or have timed out
  let cutoff = getTime() - initDuration(minutes = 30)  # 30 minute timeout
  var toRemove: seq[string] = @[]
  
  echo "=== CONNECTION CLEANUP ==="
  for sessionId, connection in transport.connections:
    if not connection.isActive or not connection.sseConnection.active or connection.lastActivity < cutoff:
      echo fmt"Marking connection {sessionId} for removal - active: {connection.isActive}, SSE active: {connection.sseConnection.active}, last activity: {connection.lastActivity}"
      toRemove.add(sessionId)
  
  for sessionId in toRemove:
    transport.connections.del(sessionId)
    echo fmt"Removed inactive connection: {sessionId}"
  
  echo fmt"Cleanup complete - {transport.connections.len} connections remaining"

proc markConnectionInactive*(transport: MummyTransport, sessionId: string) =
  ## Mark a connection as inactive
  if sessionId in transport.connections:
    transport.connections[sessionId].isActive = false
    echo fmt"Marked connection {sessionId} as inactive"

proc setupRoutes(transport: MummyTransport, server: McpServer) =
  # Handle all MCP requests on the root path
  transport.base.router.get("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(server, request))
  transport.base.router.post("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(server, request))
  transport.base.router.options("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(server, request))

proc serve*(transport: MummyTransport, server: McpServer) =
  ## Serve the HTTP server and serve MCP requests
  echo "\n=== SERVER STARTUP ==="
  echo fmt"Server name: {server.serverInfo.name}"
  echo fmt"Server version: {server.serverInfo.version}"
  echo fmt"Server capabilities: {server.capabilities}"
  echo fmt"Transport host: {transport.base.host}"
  echo fmt"Transport port: {transport.base.port}"
  echo fmt"Auth enabled: {transport.base.authConfig.enabled}"
  if transport.base.authConfig.enabled:
    echo "Bearer token configured: [REDACTED]"
  echo fmt"CORS allowed origins: {transport.base.allowedOrigins}"
  
  transport.setupRoutes(server)
  transport.base.httpServer = newServer(transport.base.router)
  
  # Start connection cleanup task
  echo "Starting connection cleanup task"
  # Note: In a production implementation, you'd want to run this in a separate thread
  # For now, we'll just add the cleanup capability
  
  echo fmt"Starting MCP HTTP server at http://{transport.base.host}:{transport.base.port}"
  echo "Server supports both JSON and SSE streaming modes"
  echo "Press Ctrl+C to stop the server"
  echo "=== SERVER READY ==="
  
  transport.base.httpServer.serve(Port(transport.base.port), transport.base.host)

