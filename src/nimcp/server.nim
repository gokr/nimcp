## MCP Server implementation using taskpools for concurrent request processing
##
## This module provides the main MCP server implementation using the modern
## taskpools library for better performance and energy efficiency.

import json, tables, options, locks, cpuinfo, strutils, times, algorithm
import json_serialization
import taskpools
import types, protocol, context, schema

# Fine-grained locks for thread-safe access to server data structures
var toolsLock: Lock
var resourcesLock: Lock
var promptsLock: Lock
initLock(toolsLock)
initLock(resourcesLock)
initLock(promptsLock)

type
  McpServer* = ref object
    ## Enhanced MCP server using taskpools for concurrent processing
    serverInfo*: McpServerInfo
    capabilities*: McpCapabilities
    tools*: Table[string, McpTool]
    toolHandlers*: Table[string, McpToolHandler]
    contextAwareToolHandlers*: Table[string, McpToolHandlerWithContext]
    resources*: Table[string, McpResource]
    resourceHandlers*: Table[string, McpResourceHandler]
    contextAwareResourceHandlers*: Table[string, McpResourceHandlerWithContext]
    prompts*: Table[string, McpPrompt]
    promptHandlers*: Table[string, McpPromptHandler]
    contextAwarePromptHandlers*: Table[string, McpPromptHandlerWithContext]
    middleware*: seq[McpMiddleware]
    initialized*: bool
    taskpool*: Taskpool
    requestTimeout*: int  # milliseconds
    enableContextLogging*: bool

proc newMcpServer*(name: string, version: string, numThreads: int = 0): McpServer =
  ## Create a new enhanced MCP server instance using taskpools for concurrency.
  ##
  ## Args:
  ##   name: Human-readable name for the server
  ##   version: Semantic version string (e.g., "1.0.0")
  ##   numThreads: Number of worker threads (0 = auto-detect)
  ##
  ## Returns:
  ##   A new McpServer instance ready for registration
  result = McpServer()
  result.serverInfo = McpServerInfo(name: name, version: version)
  result.capabilities = McpCapabilities()
  result.initialized = false
  result.requestTimeout = 30000  # 30 seconds default
  result.enableContextLogging = false
  result.middleware = @[]
  
  # Initialize taskpool with specified or auto-detected thread count
  let threads = if numThreads > 0: numThreads else: countProcessors()
  result.taskpool = Taskpool.new(numThreads = threads)
  
  # Initialize the context manager
  initContextManager()

proc shutdown*(server: McpServer) =
  ## Shutdown the server and clean up resources
  if server.taskpool != nil:
    server.taskpool.syncAll()
    server.taskpool.shutdown()
  
  # Clean up any remaining contexts
  cleanupExpiredContexts()

# Registration functions (same as original server but with validation)
proc registerTool*(server: McpServer, tool: McpTool, handler: McpToolHandler) =
  ## Register a tool with its handler function.
  if tool.name.len == 0:
    raise newException(ValueError, "Tool name cannot be empty")
  if handler == nil:
    raise newException(ValueError, "Tool handler cannot be nil")
  
  withLock toolsLock:
    server.tools[tool.name] = tool
    server.toolHandlers[tool.name] = handler
  
  if server.capabilities.tools.isNone:
    server.capabilities.tools = some(McpToolsCapability())

proc registerToolWithContext*(server: McpServer, tool: McpTool, handler: McpToolHandlerWithContext) =
  ## Register a context-aware tool with its handler function.
  if tool.name.len == 0:
    raise newException(ValueError, "Tool name cannot be empty")
  if handler == nil:
    raise newException(ValueError, "Tool handler cannot be nil")
  
  withLock toolsLock:
    server.tools[tool.name] = tool
    server.contextAwareToolHandlers[tool.name] = handler
  
  if server.capabilities.tools.isNone:
    server.capabilities.tools = some(McpToolsCapability())

proc registerResource*(server: McpServer, resource: McpResource, handler: McpResourceHandler) =
  ## Register a resource with its handler function.
  if resource.uri.len == 0:
    raise newException(ValueError, "Resource URI cannot be empty")
  if handler == nil:
    raise newException(ValueError, "Resource handler cannot be nil")
  
  withLock resourcesLock:
    server.resources[resource.uri] = resource
    server.resourceHandlers[resource.uri] = handler
  
  if server.capabilities.resources.isNone:
    server.capabilities.resources = some(McpResourcesCapability())

proc registerResourceWithContext*(server: McpServer, resource: McpResource, handler: McpResourceHandlerWithContext) =
  ## Register a context-aware resource with its handler function.
  if resource.uri.len == 0:
    raise newException(ValueError, "Resource URI cannot be empty")
  if handler == nil:
    raise newException(ValueError, "Resource handler cannot be nil")
  
  withLock resourcesLock:
    server.resources[resource.uri] = resource
    server.contextAwareResourceHandlers[resource.uri] = handler
  
  if server.capabilities.resources.isNone:
    server.capabilities.resources = some(McpResourcesCapability())

proc registerPrompt*(server: McpServer, prompt: McpPrompt, handler: McpPromptHandler) =
  ## Register a prompt with its handler function.
  if prompt.name.len == 0:
    raise newException(ValueError, "Prompt name cannot be empty")
  if handler == nil:
    raise newException(ValueError, "Prompt handler cannot be nil")
  
  withLock promptsLock:
    server.prompts[prompt.name] = prompt
    server.promptHandlers[prompt.name] = handler
  
  if server.capabilities.prompts.isNone:
    server.capabilities.prompts = some(McpPromptsCapability())

proc registerPromptWithContext*(server: McpServer, prompt: McpPrompt, handler: McpPromptHandlerWithContext) =
  ## Register a context-aware prompt with its handler function.
  if prompt.name.len == 0:
    raise newException(ValueError, "Prompt name cannot be empty")
  if handler == nil:
    raise newException(ValueError, "Prompt handler cannot be nil")
  
  withLock promptsLock:
    server.prompts[prompt.name] = prompt
    server.contextAwarePromptHandlers[prompt.name] = handler
  
  if server.capabilities.prompts.isNone:
    server.capabilities.prompts = some(McpPromptsCapability())

# Middleware management
proc registerMiddleware*(server: McpServer, middleware: McpMiddleware) =
  ## Register middleware for request/response processing
  server.middleware.add(middleware)
  # Sort by priority (lower numbers first)
  server.middleware.sort(proc(a, b: McpMiddleware): int = cmp(a.priority, b.priority))

# Server configuration methods
proc setRequestTimeout*(server: McpServer, timeoutMs: int) =
  ## Set request timeout in milliseconds
  server.requestTimeout = timeoutMs

proc enableContextLogging*(server: McpServer, enable: bool = true) =
  ## Enable or disable context logging
  server.enableContextLogging = enable

proc getRequestTimeout*(server: McpServer): int =
  ## Get current request timeout
  return server.requestTimeout

proc isContextLoggingEnabled*(server: McpServer): bool =
  ## Check if context logging is enabled
  return server.enableContextLogging

# Utility methods for server management
proc getRegisteredToolNames*(server: McpServer): seq[string] =
  ## Get list of all registered tool names
  result = @[]
  withLock toolsLock:
    for name in server.tools.keys:
      result.add(name)

proc getRegisteredResourceUris*(server: McpServer): seq[string] =
  ## Get list of all registered resource URIs
  result = @[]
  withLock resourcesLock:
    for uri in server.resources.keys:
      result.add(uri)

proc getRegisteredPromptNames*(server: McpServer): seq[string] =
  ## Get list of all registered prompt names
  result = @[]
  withLock promptsLock:
    for name in server.prompts.keys:
      result.add(name)

proc getServerStats*(server: McpServer): Table[string, JsonNode] =
  ## Get server statistics
  result = initTable[string, JsonNode]()
  result["serverName"] = %server.serverInfo.name
  result["serverVersion"] = %server.serverInfo.version
  result["initialized"] = %server.initialized
  result["requestTimeout"] = %server.requestTimeout
  result["contextLogging"] = %server.enableContextLogging
  result["middlewareCount"] = %server.middleware.len
  result["toolCount"] = %server.getRegisteredToolNames().len
  result["resourceCount"] = %server.getRegisteredResourceUris().len
  result["promptCount"] = %server.getRegisteredPromptNames().len

# Core message handlers (same logic as original server)
proc handleInitialize(server: McpServer, params: JsonNode): JsonNode {.gcsafe.} =
  server.initialized = true
  return createInitializeResponse(server.serverInfo, server.capabilities)

proc handleToolsList(server: McpServer): JsonNode {.gcsafe.} =
  var tools: seq[McpTool] = @[]
  withLock toolsLock:
    for tool in server.tools.values:
      tools.add(tool)
  return createToolsListResponse(tools)

proc handleToolsCall(server: McpServer, params: JsonNode, ctx: McpRequestContext = nil): JsonNode {.gcsafe.} =
  if not params.hasKey("name"):
    raise newException(ValueError, "Missing required parameter: name")
  
  let toolName = params["name"].getStr()
  if toolName.len == 0:
    raise newException(ValueError, "Tool name cannot be empty")
  
  let args = if params.hasKey("arguments"): params["arguments"] else: newJObject()
  
  # Check for context-aware handler first
  var contextHandler: McpToolHandlerWithContext
  var regularHandler: McpToolHandler
  var hasContextHandler = false
  var hasRegularHandler = false
  
  withLock toolsLock:
    if toolName in server.contextAwareToolHandlers:
      contextHandler = server.contextAwareToolHandlers[toolName]
      hasContextHandler = true
    elif toolName in server.toolHandlers:
      regularHandler = server.toolHandlers[toolName]
      hasRegularHandler = true
    else:
      raise newException(ValueError, "Tool not found: " & toolName)
  
  try:
    let requestCtx = if ctx != nil: ctx else: newMcpRequestContext()
    
    if server.enableContextLogging:
      requestCtx.logMessage("info", "Executing tool: " & toolName)
    
    let res = if hasContextHandler:
      contextHandler(requestCtx, args)
    else:
      regularHandler(args)
    
    return parseJson(toJson(res))
  except RequestCancellation:
    raise newException(ValueError, "Tool execution cancelled for '" & toolName & "'")
  except RequestTimeout:
    raise newException(ValueError, "Tool execution timed out for '" & toolName & "'")
  except Exception as e:
    raise newException(ValueError, "Tool execution failed for '" & toolName & "': " & e.msg)

proc handleResourcesList(server: McpServer): JsonNode {.gcsafe.} =
  var resources: seq[McpResource] = @[]
  withLock resourcesLock:
    for resource in server.resources.values:
      resources.add(resource)
  return createResourcesListResponse(resources)

proc handleResourcesRead(server: McpServer, params: JsonNode, ctx: McpRequestContext = nil): JsonNode {.gcsafe.} =
  if not params.hasKey("uri"):
    raise newException(ValueError, "Missing required parameter: uri")
  
  let uri = params["uri"].getStr()
  if uri.len == 0:
    raise newException(ValueError, "Resource URI cannot be empty")
  
  var contextHandler: McpResourceHandlerWithContext
  var regularHandler: McpResourceHandler
  var hasContextHandler = false
  var hasRegularHandler = false
  
  withLock resourcesLock:
    if uri in server.contextAwareResourceHandlers:
      contextHandler = server.contextAwareResourceHandlers[uri]
      hasContextHandler = true
    elif uri in server.resourceHandlers:
      regularHandler = server.resourceHandlers[uri]
      hasRegularHandler = true
    else:
      raise newException(ValueError, "Resource not found: " & uri)
  
  try:
    let requestCtx = if ctx != nil: ctx else: newMcpRequestContext()
    
    if server.enableContextLogging:
      requestCtx.logMessage("info", "Accessing resource: " & uri)
    
    let res = if hasContextHandler:
      contextHandler(requestCtx, uri)
    else:
      regularHandler(uri)
    
    return parseJson(toJson(res))
  except RequestCancellation:
    raise newException(ValueError, "Resource access cancelled for '" & uri & "'")
  except RequestTimeout:
    raise newException(ValueError, "Resource access timed out for '" & uri & "'")
  except Exception as e:
    raise newException(ValueError, "Resource access failed for '" & uri & "': " & e.msg)

proc handlePromptsList(server: McpServer): JsonNode {.gcsafe.} =
  var prompts: seq[McpPrompt] = @[]
  withLock promptsLock:
    for prompt in server.prompts.values:
      prompts.add(prompt)
  return createPromptsListResponse(prompts)

proc handlePromptsGet(server: McpServer, params: JsonNode, ctx: McpRequestContext = nil): JsonNode {.gcsafe.} =
  if not params.hasKey("name"):
    raise newException(ValueError, "Missing required parameter: name")
  
  let promptName = params["name"].getStr()
  if promptName.len == 0:
    raise newException(ValueError, "Prompt name cannot be empty")
  
  var args = initTable[string, JsonNode]()
  if params.hasKey("arguments"):
    for key, value in params["arguments"]:
      args[key] = value
  
  var contextHandler: McpPromptHandlerWithContext
  var regularHandler: McpPromptHandler
  var hasContextHandler = false
  var hasRegularHandler = false
  
  withLock promptsLock:
    if promptName in server.contextAwarePromptHandlers:
      contextHandler = server.contextAwarePromptHandlers[promptName]
      hasContextHandler = true
    elif promptName in server.promptHandlers:
      regularHandler = server.promptHandlers[promptName]
      hasRegularHandler = true
    else:
      raise newException(ValueError, "Prompt not found: " & promptName)
  
  try:
    let requestCtx = if ctx != nil: ctx else: newMcpRequestContext()
    
    if server.enableContextLogging:
      requestCtx.logMessage("info", "Executing prompt: " & promptName)
    
    let res = if hasContextHandler:
      contextHandler(requestCtx, promptName, args)
    else:
      regularHandler(promptName, args)
    
    return parseJson(toJson(res))
  except RequestCancellation:
    raise newException(ValueError, "Prompt execution cancelled for '" & promptName & "'")
  except RequestTimeout:
    raise newException(ValueError, "Prompt execution timed out for '" & promptName & "'")
  except Exception as e:
    raise newException(ValueError, "Prompt execution failed for '" & promptName & "': " & e.msg)

proc handleNotification*(server: McpServer, request: JsonRpcRequest) {.gcsafe.} =
  try:
    case request.`method`:
      of "initialized":
        discard
      else:
        discard
  except Exception:
    discard

# Middleware processing
proc processMiddleware(server: McpServer, ctx: McpRequestContext, request: JsonRpcRequest): JsonRpcRequest =
  ## Process before-request middleware
  var processedRequest = request
  for middleware in server.middleware:
    if middleware.beforeRequest != nil:
      try:
        processedRequest = middleware.beforeRequest(ctx, processedRequest)
      except Exception as e:
        ctx.logMessage("warning", "Middleware '" & middleware.name & "' failed: " & e.msg)
  return processedRequest

proc processMiddlewareResponse(server: McpServer, ctx: McpRequestContext, response: JsonRpcResponse): JsonRpcResponse =
  ## Process after-response middleware
  var processedResponse = response
  # Process in reverse order for response
  for i in countdown(server.middleware.len - 1, 0):
    let middleware = server.middleware[i]
    if middleware.afterResponse != nil:
      try:
        processedResponse = middleware.afterResponse(ctx, processedResponse)
      except Exception as e:
        ctx.logMessage("warning", "Middleware '" & middleware.name & "' failed: " & e.msg)
  return processedResponse

proc handleRequest*(server: McpServer, request: JsonRpcRequest): JsonRpcResponse {.gcsafe.} =
  if request.id.isNone:
    server.handleNotification(request)
    return JsonRpcResponse()
  
  let id = request.id.get
  let requestId = if id.kind == jridString: id.str else: $id.num
  let ctx = newMcpRequestContext(requestId)
  
  try:
    # Context is available but not automatically registered to avoid GC issues
    
    # Process middleware
    let processedRequest = server.processMiddleware(ctx, request)
    
    if processedRequest.`method` != "initialize" and not server.initialized:
      let error = newMcpStructuredError(McpServerNotInitialized, melError, 
        "Server must be initialized before calling " & processedRequest.`method`, requestId = ctx.requestId)
      return JsonRpcResponse(jsonrpc: "2.0", id: id, error: some(error.toJsonRpcError()))
    
    # Check for cancellation
    ctx.ensureNotCancelled()
    
    let res = case processedRequest.`method`:
      of "initialize":
        server.handleInitialize(processedRequest.params.get(newJObject()))
      of "tools/list":
        server.handleToolsList()
      of "tools/call":
        server.handleToolsCall(processedRequest.params.get(newJObject()), ctx)
      of "resources/list":
        server.handleResourcesList()
      of "resources/read":
        server.handleResourcesRead(processedRequest.params.get(newJObject()), ctx)
      of "prompts/list":
        server.handlePromptsList()
      of "prompts/get":
        server.handlePromptsGet(processedRequest.params.get(newJObject()), ctx)
      else:
        let error = newMcpStructuredError(MethodNotFound, melError, 
          "Method not found: " & processedRequest.`method`, requestId = ctx.requestId)
        return JsonRpcResponse(jsonrpc: "2.0", id: id, error: some(error.toJsonRpcError()))
    
    let response = createJsonRpcResponse(id, res)
    return server.processMiddlewareResponse(ctx, response)
    
  except ValueError as e:
    let error = newMcpStructuredError(InvalidParams, melError, e.msg, requestId = ctx.requestId)
    return JsonRpcResponse(jsonrpc: "2.0", id: id, error: some(error.toJsonRpcError()))
  except JsonParsingError as e:
    let error = newMcpStructuredError(ParseError, melError, "JSON parsing error: " & e.msg, requestId = ctx.requestId)
    return JsonRpcResponse(jsonrpc: "2.0", id: id, error: some(error.toJsonRpcError()))
  except RequestCancellation:
    let error = newMcpStructuredError(McpRequestCancelled, melWarning, "Request was cancelled", requestId = ctx.requestId)
    return JsonRpcResponse(jsonrpc: "2.0", id: id, error: some(error.toJsonRpcError()))
  except RequestTimeout:
    let error = newMcpStructuredError(McpRequestCancelled, melWarning, "Request timed out", requestId = ctx.requestId)
    return JsonRpcResponse(jsonrpc: "2.0", id: id, error: some(error.toJsonRpcError()))
  except Exception as e:
    let error = newMcpStructuredError(InternalError, melCritical, "Internal error: " & e.msg, requestId = ctx.requestId)
    return JsonRpcResponse(jsonrpc: "2.0", id: id, error: some(error.toJsonRpcError()))

# Thread-safe output handling
var stdoutLock: Lock
initLock(stdoutLock)

proc safeEcho(msg: string) =
  withLock stdoutLock:
    echo msg
    stdout.flushFile()

# Global server pointer for taskpools (similar to threadpool approach)
var globalServerPtr: ptr McpServer

# Request processing task for taskpools - uses global pointer to avoid isolation issues
proc processRequestTask(requestLine: string) {.gcsafe.} =
  var requestId: JsonRpcId = JsonRpcId(kind: jridString, str: "")

  try:
    let request = parseJsonRpcMessage(requestLine)

    if request.id.isSome:
      requestId = request.id.get

    if request.id.isNone:
      globalServerPtr[].handleNotification(request)
    else:
      let response = globalServerPtr[].handleRequest(request)

      # Create JSON response manually for thread safety
      var responseJson = newJObject()
      responseJson["jsonrpc"] = %response.jsonrpc
      responseJson["id"] = %response.id
      if response.result.isSome:
        responseJson["result"] = response.result.get
      if response.error.isSome:
        let errorObj = newJObject()
        errorObj["code"] = %response.error.get.code
        errorObj["message"] = %response.error.get.message
        if response.error.get.data.isSome:
          errorObj["data"] = response.error.get.data.get
        responseJson["error"] = errorObj
      safeEcho($responseJson)
  except Exception as e:
    let errorResponse = createJsonRpcError(requestId, ParseError, "Parse error: " & e.msg)
    safeEcho($(%errorResponse))

# Modern stdio transport using taskpools
proc runStdio*(server: McpServer) =
  ## Run the MCP server with stdio transport using modern taskpools
  globalServerPtr = addr server

  while true:
    try:
      let line = stdin.readLine()
      if line.len == 0:
        break

      # Spawn task using taskpools - returns void so no need to track
      server.taskpool.spawn processRequestTask(line)

    except EOFError:
      # Sync all pending tasks before shutdown
      server.taskpool.syncAll()
      break
    except Exception:
      # Sync all pending tasks before shutdown
      server.taskpool.syncAll()
      break

  # Wait for all remaining tasks and shutdown
  server.shutdown()
