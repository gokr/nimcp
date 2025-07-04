## Request context implementation for NimCP
## Provides request context, progress tracking, cancellation, and structured error handling

import json, tables, options, times, strutils, locks, random
import types

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

proc newMcpRequestContext*(requestId: string = ""): McpRequestContext =
  ## Create a new request context with unique ID (for backward compatibility)
  let id = if requestId.len > 0: requestId else: $now().toTime().toUnix() & "_" & $rand(1000)
  
  result = McpRequestContext(
    server: nil,  # Server reference not available in this constructor
    transport: McpTransport(),  # Empty transport for backward compatibility
    requestId: id,
    startTime: now(),
    cancelled: false,
    metadata: initTable[string, JsonNode](),
    progressCallback: nil,
    logCallback: nil
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

proc reportProgress*(ctx: McpRequestContext, message: string, progress: float) =
  ## Report progress for the current request (0.0 to 1.0)
  if ctx.progressCallback != nil:
    ctx.progressCallback(message, progress)

proc logMessage*(ctx: McpRequestContext, level: string, message: string) =
  ## Log a message for the current request
  if ctx.logCallback != nil:
    ctx.logCallback(level, message)
  else:
    # Default logging to stdout
    echo "[" & level.toUpperAscii() & "] " & ctx.requestId & ": " & message

proc sendEvent*(ctx: McpRequestContext, eventType: string, data: JsonNode, target: string = "") =
  ## Send an event through the transport (transport-agnostic)
  sendEvent(ctx.transport, eventType, data, target)

proc broadcastMessage*(ctx: McpRequestContext, jsonMessage: JsonNode) =
  ## Broadcast a message through the transport (transport-agnostic)
  broadcastMessage(ctx.transport, jsonMessage)

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

# Progress tracking utilities
proc createProgressCallback*(onProgress: proc(message: string, progress: float) {.gcsafe.}): proc(message: string, progress: float) {.gcsafe.} =
  ## Create a thread-safe progress callback
  return proc(message: string, progress: float) {.gcsafe.} =
    try:
      onProgress(message, progress)
    except:
      discard  # Ignore callback errors

proc createLogCallback*(onLog: proc(level: string, message: string) {.gcsafe.}): proc(level: string, message: string) {.gcsafe.} =
  ## Create a thread-safe log callback
  return proc(level: string, message: string) {.gcsafe.} =
    try:
      onLog(level, message)
    except:
      discard  # Ignore callback errors

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
