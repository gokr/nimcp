## Request context implementation for NimCP
## Provides request context, progress tracking, cancellation, and structured error handling

import json, tables, options, times, locks, random
import types

# No imports or forward declarations needed - we'll use function pointers from the transport

type
  ContextManager* = ref object
    ## Manages request contexts across the server
    contexts: Table[string, McpRequestContext]
    contextLock: Lock
    defaultTimeout: int = 30000  # milliseconds
    
  RequestCancellation* = object of CatchableError
    ## Exception raised when a request is cancelled
    
  RequestTimeout* = object of CatchableError
    ## Exception raised when a request times out

var globalContextManager* = ContextManager()
initLock(globalContextManager.contextLock)


proc newMcpRequestContext*(requestId: string = "", sessionId: string = ""): McpRequestContext =
  ## Create a new request context with unique ID and session ID
  let id = if requestId.len > 0: requestId else: $now().toTime().toUnix() & "_" & $rand(1000)
  
  result = McpRequestContext(
    server: nil,  # Server reference not available in this constructor
    transport: McpTransport(),  # Empty transport for backward compatibility
    requestId: id,
    sessionId: sessionId,
    startTime: now(),
    cancelled: false,
    metadata: initTable[string, JsonNode]()
  )


proc registerContext*(ctx: McpRequestContext) =
  ## Register a context with the context manager  
  withLock globalContextManager.contextLock:
    globalContextManager.contexts[ctx.requestId] = ctx

proc unregisterContext*(requestId: string) =
  withLock globalContextManager.contextLock:
    globalContextManager.contexts.del(requestId)

proc getContext*(requestId: string): Option[McpRequestContext] =
  ## Get a context by ID
  withLock globalContextManager.contextLock:
    if requestId in globalContextManager.contexts:
      return some(globalContextManager.contexts[requestId])
    return none(McpRequestContext)

proc cancelRequest*(requestId: string): bool =
  ## Cancel a request by ID
  let ctxOpt = getContext(requestId)
  if ctxOpt.isSome:
    let ctx = ctxOpt.get()
    ctx.cancelled = true
    return true
  return false

proc sendNotification*(ctx: McpRequestContext, notificationType: string, data: JsonNode, sessionId: string = "") =
  ## Send a notification to a client through the transport
  
  case ctx.transport.kind:
  of tkNone:
    discard  # No transport configured
  of tkStdio:
    # For stdio transport, send notification as JSON-RPC notification to stdout
    let notification = %*{
      "jsonrpc": "2.0",
      "method": "notifications/message",
      "params": %*{
        "level": "info",
        "logger": "nimcp-server",
        "data": data
      }
    }
    echo $notification
  of tkHttp:
    # Current session notification
    if ctx.transport.httpTransport != nil and ctx.transport.httpSendNotification != nil:
      ctx.transport.httpSendNotification(ctx, "message", data)
  of tkWebSocket:
    # Current session notification
    if ctx.transport.wsTransport != nil and ctx.transport.wsSendNotification != nil:
      ctx.transport.wsSendNotification(ctx, "message", data)
  of tkSSE:
    # Current session notification
    if ctx.transport.sseTransport != nil and ctx.transport.sseSendNotification != nil:
      ctx.transport.sseSendNotification(ctx, "message", data)

proc sendProgress*(ctx: McpRequestContext, progress: int, total: int, message: string = "", sessionId: string = "") =
  ## Send a progress notification using MCP protocol
  ## Only sends notifications when client explicitly requested them via progressToken
  
  # Only send progress notifications if client provided a progressToken
  if ctx.progressToken == none(JsonNode):
    return  # Client didn't request progress updates
  
  var progressData = %*{
    "progress": progress,
    "total": total,
    "progressToken": ctx.progressToken.get()
  }
  
  if message.len > 0:
    progressData["message"] = %message
  
  case ctx.transport.kind:
  of tkNone:
    discard  # No transport configured
  of tkStdio:
    # For stdio transport, send progress notification as JSON-RPC notification to stdout
    let notification = %*{
      "jsonrpc": "2.0",
      "method": "notifications/progress",
      "params": progressData
    }
    echo $notification
  of tkHttp:
    # Current session progress notification
    if ctx.transport.httpTransport != nil and ctx.transport.httpSendNotification != nil:
      ctx.transport.httpSendNotification(ctx, "progress", progressData)
  of tkWebSocket:
    # Current session progress notification
    if ctx.transport.wsTransport != nil and ctx.transport.wsSendNotification != nil:
      ctx.transport.wsSendNotification(ctx, "progress", progressData)
  of tkSSE:
    # Current session progress notification
    if ctx.transport.sseTransport != nil and ctx.transport.sseSendNotification != nil:
      ctx.transport.sseSendNotification(ctx, "progress", progressData)

proc isCancelled*(ctx: McpRequestContext): bool =
  ## Check if the current request has been cancelled
  return ctx.cancelled

proc cancel*(ctx: McpRequestContext) =
  ## Cancel the current request
  ctx.cancelled = true

proc setMetadata*(ctx: McpRequestContext, key: string, value: JsonNode) =
  ## Set metadata for the current request
  ctx.metadata[key] = value

proc getMetadata*(ctx: McpRequestContext, key: string): Option[JsonNode] =
  ## Get metadata for the current request
  if key in ctx.metadata:
    return some(ctx.metadata[key])
  return none(JsonNode)

proc getElapsedTime*(ctx: McpRequestContext): Duration =
  ## Get elapsed time since request started
  return now() - ctx.startTime

proc getSessionId*(ctx: McpRequestContext): string =
  ## Get the session ID for this request context
  return ctx.sessionId

proc checkTimeout*(ctx: McpRequestContext, timeoutMs: int = 0): bool {.gcsafe.} =
  ## Check if request has timed out
  let timeout = if timeoutMs > 0: timeoutMs else: 30000  # Default 30 seconds
  let elapsed = getElapsedTime(ctx)
  return elapsed.inMilliseconds > timeout

proc ensureNotCancelled*(ctx: McpRequestContext) =
  ## Raise exception if request is cancelled
  if ctx.cancelled:
    raise newException(RequestCancellation, "Request " & ctx.requestId & " was cancelled")

proc ensureNotTimedOut*(ctx: McpRequestContext, timeoutMs: int = 0) {.gcsafe.} =
  ## Raise exception if request has timed out
  if checkTimeout(ctx, timeoutMs):
    raise newException(RequestTimeout, "Request " & ctx.requestId & " timed out")

proc withContext*[T](requestId: string, operation: proc(ctx: McpRequestContext): T): T =
  ## Execute an operation with a managed context
  let ctx = newMcpRequestContext(requestId)
  registerContext(ctx)
  
  try:
    return operation(ctx)
  finally:
    unregisterContext(ctx.requestId)

proc withContext*[T](requestId: string, sessionId: string, operation: proc(ctx: McpRequestContext): T): T =
  ## Execute an operation with a managed context including session ID
  let ctx = newMcpRequestContext(requestId, sessionId)
  registerContext(ctx)
  
  try:
    return operation(ctx)
  finally:
    unregisterContext(ctx.requestId)

# Structured error handling
proc newMcpStructuredError*(code: int, level: McpErrorLevel, message: string, 
                          details: string = "", requestId: string = ""): McpStructuredError =
  ## Create a new structured error
  McpStructuredError(
    code: code,
    level: level,
    message: message,
    details: if details.len > 0: some(details) else: none(string),
    timestamp: now(),
    requestId: if requestId.len > 0: some(requestId) else: none(string),
    context: none(Table[string, JsonNode])
  )

proc addErrorContext*(error: var McpStructuredError, key: string, value: JsonNode) =
  ## Add context information to a structured error
  if error.context.isNone:
    error.context = some(initTable[string, JsonNode]())
  error.context.get()[key] = value

proc toJsonRpcError*(error: McpStructuredError): JsonRpcError =
  ## Convert structured error to JSON-RPC error
  var data = newJObject()
  data["level"] = %($error.level)
  data["timestamp"] = %($error.timestamp)
  
  if error.details.isSome:
    data["details"] = %error.details.get()
  if error.requestId.isSome:
    data["requestId"] = %error.requestId.get()
  if error.context.isSome:
    data["context"] = %error.context.get()
  if error.stackTrace.isSome:
    data["stackTrace"] = %error.stackTrace.get()
  
  JsonRpcError(
    code: error.code,
    message: error.message,
    data: some(data)
  )

# Context-aware wrappers for handler functions
template withRequestContext*(requestId: string, body: untyped): untyped =
  ## Execute code block with a request context
  let ctx {.inject.} = newMcpRequestContext(requestId)
  registerContext(ctx)
  
  try:
    body
  finally:
    unregisterContext(ctx.requestId)

template withRequestContext*(requestId: string, sessionId: string, body: untyped): untyped =
  ## Execute code block with a request context including session ID
  let ctx {.inject.} = newMcpRequestContext(requestId, sessionId)
  registerContext(ctx)
  
  try:
    body
  finally:
    unregisterContext(ctx.requestId)



# Timeout management
proc setDefaultTimeout*(timeoutMs: int) =
  ## Set the default timeout for all requests
  globalContextManager.defaultTimeout = timeoutMs

proc getDefaultTimeout*(): int =
  ## Get the default timeout
  return globalContextManager.defaultTimeout


# Context cleanup utilities
proc cleanupExpiredContexts*() =
  ## Clean up contexts that have been around too long
  let cutoff = now() - initDuration(hours = 1)  # Clean up contexts older than 1 hour
  var toRemove: seq[string] = @[]
  
  withLock globalContextManager.contextLock:
    for id, ctx in globalContextManager.contexts:
      if ctx.startTime < cutoff:
        toRemove.add(id)
    
    for id in toRemove:
      globalContextManager.contexts.del(id)
