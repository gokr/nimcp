## MCP Server implementation using taskpools for concurrent request processing
##
## This module provides the main MCP server implementation using the modern
## taskpools library for better performance and energy efficiency.

import json, tables, options, locks, cpuinfo, strutils, algorithm, times, random
import taskpools
import types, protocol, context, resource_templates, logging

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
    resourceTemplates*: ResourceTemplateRegistry
    middleware*: seq[McpMiddleware]
    initialized*: bool
    taskpool*: Taskpool
    requestTimeout*: int  # milliseconds
    enableContextLogging*: bool
    logger*: Logger
    transport*: Option[McpTransport]  # Type-safe transport storage
    customData*: Table[string, pointer]  # Custom data storage for other use cases

  # Server composition types (moved from types.nim to avoid circular dependency)
  MountPoint* = object
    ## Represents a mount point for a server
    path*: string
    server*: McpServer  # Proper ref type instead of unsafe pointer
    prefix*: Option[string]  # Optional prefix for tool/resource names

  ComposedServer* = ref object
    ## A server that can mount multiple other servers
    mainServer*: McpServer  # Proper ref type instead of unsafe pointer
    mountPoints*: seq[MountPoint]
    pathMappings*: Table[string, MountPoint]

  ServerNamespace* = object
    ## Namespace configuration for mounted servers
    toolPrefix*: Option[string]
    resourcePrefix*: Option[string]
    promptPrefix*: Option[string]

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
  result.resourceTemplates = newResourceTemplateRegistry()
  result.transport = none(McpTransport)  # Initialize with no transport
  result.customData = initTable[string, pointer]()
  
  # Initialize logging with server-specific component name
  result.logger = newLogger(llInfo)
  result.logger.setComponent("mcp-server-" & name)
  result.logger.setupChroniclesLogging()
  
  # Initialize taskpool with specified or auto-detected thread count
  let threads = if numThreads > 0: numThreads else: countProcessors()
  result.taskpool = Taskpool.new(numThreads = threads)
  
  # Log server initialization
  result.logger.info("MCP server initialized", 
    context = {"name": %name, "version": %version, "threads": %threads}.toTable)


# Server-aware context creation
proc newMcpRequestContextWithServer(server: McpServer, requestId: string = ""): McpRequestContext =
  ## Create a new request context with server reference
  let id = if requestId.len > 0: requestId else: $now().toTime().toUnix() & "_" & $rand(1000)
  
  result = McpRequestContext(
    server: cast[pointer](server),
    requestId: id,
    startTime: now(),
    cancelled: false,
    metadata: initTable[string, JsonNode](),
    progressCallback: nil,
    logCallback: nil
  )

# Context helper methods
proc getServer*(ctx: McpRequestContext): McpServer =
  ## Get the server instance from the request context
  if ctx.server != nil:
    return cast[McpServer](ctx.server)
  else:
    return nil

# Custom data storage and retrieval methods
proc setCustomData*[T](server: McpServer, key: string, data: T) =
  ## Store custom data in the server for access by server-aware handlers
  server.customData[key] = cast[pointer](data)

proc getCustomData*[T](server: McpServer, key: string, dataType: typedesc[T]): T =
  ## Retrieve custom data from the server
  if key in server.customData:
    return cast[T](server.customData[key])
  else:
    return nil

proc hasCustomData*(server: McpServer, key: string): bool =
  ## Check if custom data exists for the given key
  return key in server.customData

proc removeCustomData*(server: McpServer, key: string) =
  ## Remove custom data for the given key
  if key in server.customData:
    server.customData.del(key)









proc shutdown*(server: McpServer) =
  ## Shutdown the server and clean up resources
  server.logger.info("Shutting down MCP server")
  
  if server.taskpool != nil:
    server.taskpool.syncAll()
    server.taskpool.shutdown()
  
  # Clean up any remaining contexts
  cleanupExpiredContexts()
  
  server.logger.info("MCP server shutdown complete")

# Transport helper methods
proc getTransportKind*(server: McpServer): TransportKind =
  ## Get the kind of currently active transport
  if server.transport.isSome:
    return server.transport.get().kind
  else:
    return tkNone

proc hasTransport*(server: McpServer): bool =
  ## Check if server has an active transport
  return server.transport.isSome

proc clearTransport*(server: McpServer) =
  ## Clear the active transport
  server.transport = none(McpTransport)

# Transport configuration methods
proc setSseTransport*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: pointer = nil, sseEndpoint: string = "/sse", messageEndpoint: string = "/messages") =
  ## Set SSE transport with configuration
  let sseData = SseTransportData(
    port: port,
    host: host,
    authConfig: authConfig,
    connectionPool: nil,
    sseEndpoint: sseEndpoint,
    messageEndpoint: messageEndpoint
  )
  server.transport = some(McpTransport(
    kind: tkSSE,
    capabilities: {tcBroadcast, tcEvents, tcUnicast},
    sseData: sseData
  ))

proc setWebSocketTransport*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: pointer = nil) =
  ## Set WebSocket transport with configuration
  let wsData = WebSocketTransportData(
    port: port,
    host: host,
    authConfig: authConfig,
    connectionPool: nil
  )
  server.transport = some(McpTransport(
    kind: tkWebSocket,
    capabilities: {tcBroadcast, tcEvents, tcUnicast, tcBidirectional},
    wsData: wsData
  ))

proc setHttpTransport*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: pointer = nil, allowedOrigins: seq[string] = @[]) =
  ## Set HTTP transport with configuration
  let httpData = HttpTransportData(
    port: port,
    host: host,
    authConfig: authConfig,
    allowedOrigins: allowedOrigins,
    connections: nil
  )
  server.transport = some(McpTransport(
    kind: tkHttp,
    capabilities: {tcBroadcast, tcEvents},
    httpData: httpData
  ))

# Helper functions to reduce registration code duplication
proc validateRegistration(itemType: string, itemKey: string) =
  ## Common validation logic for all registration functions
  if itemKey.len == 0:
    raise newException(ValueError, itemType & " name/URI cannot be empty")

proc ensureToolsCapability(server: McpServer) =
  ## Ensure tools capability is initialized
  if server.capabilities.tools.isNone:
    server.capabilities.tools = some(McpToolsCapability())

proc ensureResourcesCapability(server: McpServer) =
  ## Ensure resources capability is initialized
  if server.capabilities.resources.isNone:
    server.capabilities.resources = some(McpResourcesCapability())

proc ensurePromptsCapability(server: McpServer) =
  ## Ensure prompts capability is initialized
  if server.capabilities.prompts.isNone:
    server.capabilities.prompts = some(McpPromptsCapability())

# Registration functions (consolidated with validation)
proc registerTool*(server: McpServer, tool: McpTool, handler: McpToolHandler) =
  ## Register a tool with its handler function.
  validateRegistration("Tool", tool.name)
  if handler == nil:
    raise newException(ValueError, "Tool handler cannot be nil")

  withLock toolsLock:
    server.tools[tool.name] = tool
    server.toolHandlers[tool.name] = handler

  server.ensureToolsCapability()
  server.logger.debug("Registered tool", context = {"toolName": %tool.name}.toTable)

proc registerToolWithContext*(server: McpServer, tool: McpTool, handler: McpToolHandlerWithContext) =
  ## Register a context-aware tool with its handler function.
  validateRegistration("Tool", tool.name)
  if handler == nil:
    raise newException(ValueError, "Tool handler cannot be nil")

  withLock toolsLock:
    server.tools[tool.name] = tool
    server.contextAwareToolHandlers[tool.name] = handler

  server.ensureToolsCapability()


proc registerResource*(server: McpServer, resource: McpResource, handler: McpResourceHandler) =
  ## Register a resource with its handler function.
  validateRegistration("Resource", resource.uri)
  if handler == nil:
    raise newException(ValueError, "Resource handler cannot be nil")

  withLock resourcesLock:
    server.resources[resource.uri] = resource
    server.resourceHandlers[resource.uri] = handler

  server.ensureResourcesCapability()

proc registerResourceWithContext*(server: McpServer, resource: McpResource, handler: McpResourceHandlerWithContext) =
  ## Register a context-aware resource with its handler function.
  validateRegistration("Resource", resource.uri)
  if handler == nil:
    raise newException(ValueError, "Resource handler cannot be nil")

  withLock resourcesLock:
    server.resources[resource.uri] = resource
    server.contextAwareResourceHandlers[resource.uri] = handler

  server.ensureResourcesCapability()

proc registerPrompt*(server: McpServer, prompt: McpPrompt, handler: McpPromptHandler) =
  ## Register a prompt with its handler function.
  validateRegistration("Prompt", prompt.name)
  if handler == nil:
    raise newException(ValueError, "Prompt handler cannot be nil")

  withLock promptsLock:
    server.prompts[prompt.name] = prompt
    server.promptHandlers[prompt.name] = handler

  server.ensurePromptsCapability()

proc registerPromptWithContext*(server: McpServer, prompt: McpPrompt, handler: McpPromptHandlerWithContext) =
  ## Register a context-aware prompt with its handler function.
  validateRegistration("Prompt", prompt.name)
  if handler == nil:
    raise newException(ValueError, "Prompt handler cannot be nil")

  withLock promptsLock:
    server.prompts[prompt.name] = prompt
    server.contextAwarePromptHandlers[prompt.name] = handler

  server.ensurePromptsCapability()

proc registerResourceTemplate*(server: McpServer, resourceTemplate: McpResourceTemplate, handler: ResourceTemplateHandler) =
  ## Register a resource template with its handler function.
  validateRegistration("Resource template", resourceTemplate.uriTemplate)
  if handler == nil:
    raise newException(ValueError, "Resource template handler cannot be nil")

  server.resourceTemplates.registerTemplate(resourceTemplate, handler)
  server.ensureResourcesCapability()

proc registerResourceTemplateWithContext*(server: McpServer, resourceTemplate: McpResourceTemplate, handler: ResourceTemplateHandlerWithContext) =
  ## Register a context-aware resource template with its handler function.
  validateRegistration("Resource template", resourceTemplate.uriTemplate)
  if handler == nil:
    raise newException(ValueError, "Resource template handler cannot be nil")

  server.resourceTemplates.registerTemplateWithContext(resourceTemplate, handler)
  server.ensureResourcesCapability()

# UFCS Fluent API Extensions
# These functions enable method call syntax for more fluent server configuration

# Generic fluent API template to reduce duplication
template createFluentApi(name: untyped, itemType: typedesc, handlerType: typedesc, registerProc: untyped): untyped =
  proc name*(server: McpServer, item: itemType, handler: handlerType): McpServer =
    ## Fluent API: Register and return the server for chaining
    registerProc(server, item, handler)
    server

# Generate fluent API functions using the template
createFluentApi(withTool, McpTool, McpToolHandler, registerTool)
createFluentApi(withToolContext, McpTool, McpToolHandlerWithContext, registerToolWithContext)
createFluentApi(withResource, McpResource, McpResourceHandler, registerResource)
createFluentApi(withResourceContext, McpResource, McpResourceHandlerWithContext, registerResourceWithContext)
createFluentApi(withPrompt, McpPrompt, McpPromptHandler, registerPrompt)
createFluentApi(withPromptContext, McpPrompt, McpPromptHandlerWithContext, registerPromptWithContext)
createFluentApi(withResourceTemplate, McpResourceTemplate, ResourceTemplateHandler, registerResourceTemplate)
createFluentApi(withResourceTemplateContext, McpResourceTemplate, ResourceTemplateHandlerWithContext, registerResourceTemplateWithContext)


# Middleware management
proc registerMiddleware*(server: McpServer, middleware: McpMiddleware) =
  ## Register middleware for request/response processing
  server.middleware.add(middleware)
  # Sort by priority (lower numbers first)
  server.middleware.sort(proc(a, b: McpMiddleware): int = cmp(a.priority, b.priority))

proc setLogLevel*(server: McpServer, level: LogLevel) =
  ## Set the minimum log level for the server
  server.logger.setMinLevel(level)

proc addLogHandler*(server: McpServer, handler: LogHandler) =
  ## Add a log handler to the server's logger
  server.logger.addHandler(handler)

proc enableFileLogging*(server: McpServer, filename: string) =
  ## Enable file logging for the server
  server.logger.addHandler(fileHandler(filename))

proc enableJSONLogging*(server: McpServer) =
  ## Enable JSON structured logging for the server
  server.logger.addHandler(jsonHandler)

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
  return createInitializeResponseJson(server.serverInfo, server.capabilities)

proc handleToolsList(server: McpServer): JsonNode {.gcsafe.} =
  var tools: seq[McpTool] = @[]
  withLock toolsLock:
    for tool in server.tools.values:
      tools.add(tool)
  return createToolsListResponseJson(tools)

proc handleToolsCall(server: McpServer, params: JsonNode, ctx: McpRequestContext = nil): JsonNode {.gcsafe.} =
  let toolName = requireStringField(params, "name")
  if toolName.len == 0:
    raise newException(ValueError, "Tool name cannot be empty")

  let args = if params.hasKey("arguments"): params["arguments"] else: newJObject()
  
  # Check for handlers in order of preference: context-aware, regular
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
    let requestCtx = if ctx != nil: ctx else: newMcpRequestContextWithServer(server)
    
    if server.enableContextLogging:
      requestCtx.logMessage("info", "Executing tool: " & toolName)
    
    let res = if hasContextHandler:
      contextHandler(requestCtx, args)
    else:
      regularHandler(args)
    
    # Use consolidated JSON utilities for consistent serialization
    return %*{
      "content": contentsToJsonArray(res.content)
    }
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
  return createResourcesListResponseJson(resources)

proc handleResourcesRead(server: McpServer, params: JsonNode, ctx: McpRequestContext = nil): JsonNode {.gcsafe.} =
  let uri = requireStringField(params, "uri")
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
  
  # If no direct handler found, try resource templates
  if not hasContextHandler and not hasRegularHandler:
    let requestCtx = if ctx != nil: ctx else: newMcpRequestContextWithServer(server)
    let templateResult = server.resourceTemplates.handleTemplateRequestWithContext(requestCtx, uri)
    if templateResult.isSome:
      # Create response manually to avoid GC safety issues
      let res = templateResult.get()
      var responseJson = newJObject()
      responseJson["content"] = newJArray()
      for content in res.content:
        var contentJson = newJObject()
        contentJson["type"] = newJString(content.`type`)
        case content.kind:
        of TextContent:
          contentJson["text"] = newJString(content.text)
        of ImageContent:
          contentJson["data"] = newJString(content.data)
          contentJson["mimeType"] = newJString(content.mimeType)
        of ResourceContent:
          # Serialize the nested resource contents
          var resourceJson = newJObject()
          resourceJson["uri"] = newJString(content.resource.uri)
          if content.resource.mimeType.isSome:
            resourceJson["mimeType"] = newJString(content.resource.mimeType.get)
          resourceJson["content"] = newJArray()
          for nestedContent in content.resource.content:
            var nestedContentJson = newJObject()
            nestedContentJson["type"] = newJString(nestedContent.`type`)
            case nestedContent.kind:
            of TextContent:
              nestedContentJson["text"] = newJString(nestedContent.text)
            of ImageContent:
              nestedContentJson["data"] = newJString(nestedContent.data)
              nestedContentJson["mimeType"] = newJString(nestedContent.mimeType)
            of ResourceContent:
              # Avoid infinite recursion - just include URI for nested resources
              nestedContentJson["uri"] = newJString(nestedContent.resource.uri)
            resourceJson["content"].add(nestedContentJson)
          contentJson["resource"] = resourceJson
        responseJson["content"].add(contentJson)
      return responseJson
    else:
      raise newException(ValueError, "Resource not found: " & uri)
  
  try:
    let requestCtx = if ctx != nil: ctx else: newMcpRequestContextWithServer(server)
    
    if server.enableContextLogging:
      requestCtx.logMessage("info", "Accessing resource: " & uri)
    
    let res = if hasContextHandler:
      contextHandler(requestCtx, uri)
    else:
      regularHandler(uri)
    
    # Use consolidated JSON utilities for consistent serialization
    return %res
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
  return createPromptsListResponseJson(prompts)

proc handlePromptsGet(server: McpServer, params: JsonNode, ctx: McpRequestContext = nil): JsonNode {.gcsafe.} =
  let promptName = requireStringField(params, "name")
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
    let requestCtx = if ctx != nil: ctx else: newMcpRequestContextWithServer(server)
    
    if server.enableContextLogging:
      requestCtx.logMessage("info", "Executing prompt: " & promptName)
    
    let res = if hasContextHandler:
      contextHandler(requestCtx, promptName, args)
    else:
      regularHandler(promptName, args)
    
    # Create response manually to avoid GC safety issues
    var responseJson = newJObject()
    if res.description.isSome:
      responseJson["description"] = newJString(res.description.get)
    responseJson["messages"] = newJArray()
    for message in res.messages:
      var messageJson = newJObject()
      messageJson["role"] = newJString($message.role)
      var contentJson = newJObject()
      let content = message.content
      contentJson["type"] = newJString(content.`type`)
      case content.kind:
      of TextContent:
        contentJson["text"] = newJString(content.text)
      of ImageContent:
        contentJson["data"] = newJString(content.data)
        contentJson["mimeType"] = newJString(content.mimeType)
      of ResourceContent:
        # Serialize the nested resource contents
        var resourceJson = newJObject()
        resourceJson["uri"] = newJString(content.resource.uri)
        if content.resource.mimeType.isSome:
          resourceJson["mimeType"] = newJString(content.resource.mimeType.get)
        contentJson["resource"] = resourceJson
      messageJson["content"] = contentJson
      responseJson["messages"].add(messageJson)
    return responseJson
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
    result = JsonRpcResponse()
    return
  
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
      result = JsonRpcResponse(jsonrpc: "2.0", id: id, error: some(error.toJsonRpcError()))
      return
    
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
        result = JsonRpcResponse(jsonrpc: "2.0", id: id, error: some(error.toJsonRpcError()))
        return

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





# Server Composition and Mounting functionality
proc newMountPoint*(path: string, server: McpServer, prefix: Option[string] = none(string)): MountPoint =
  ## Create a new mount point
  MountPoint(
    path: path,
    server: server,  # Direct ref assignment instead of unsafe pointer cast
    prefix: prefix
  )

proc newComposedServer*(name: string, version: string, numThreads: int = 0): ComposedServer =
  ## Create a new composed server that can mount other servers
  let mainServer = newMcpServer(name, version, numThreads)
  ComposedServer(
    mainServer: mainServer,  # Direct ref assignment instead of unsafe pointer cast
    mountPoints: @[],
    pathMappings: initTable[string, MountPoint]()
  )


proc mountServer*(composed: ComposedServer, mountPoint: MountPoint) =
  ## Mount a server at the specified mount point
  if mountPoint.path in composed.pathMappings:
    raise newException(ValueError, "Mount point already exists: " & mountPoint.path)
  
  composed.mountPoints.add(mountPoint)
  composed.pathMappings[mountPoint.path] = mountPoint

proc mountServerAt*(composed: ComposedServer, path: string, server: McpServer, prefix: Option[string] = none(string)) =
  ## Mount a server at the specified path with optional prefix
  let mountPoint = newMountPoint(path, server, prefix)
  composed.mountServer(mountPoint)

proc unmountServer*(composed: ComposedServer, path: string): bool =
  ## Unmount a server from the specified path, returns true if unmounted
  if path notin composed.pathMappings:
    result = false
    return

  composed.pathMappings.del(path)

  # Remove from mountPoints sequence
  for i in countdown(composed.mountPoints.len - 1, 0):
    if composed.mountPoints[i].path == path:
      composed.mountPoints.del(i)
      break

  return true

proc findMountPointForTool*(composed: ComposedServer, toolName: string): Option[MountPoint] =
  ## Find the mount point that should handle a given tool name
  for mountPoint in composed.mountPoints:
    if mountPoint.prefix.isSome:
      let prefix = mountPoint.prefix.get()
      if toolName.startsWith(prefix):
        result = some(mountPoint)
        return
    else:
      # Check if the mounted server has this tool
      let server = mountPoint.server
      let tools = server.getRegisteredToolNames()
      if toolName in tools:
        result = some(mountPoint)
        return

  return none(MountPoint)

proc findMountPointForResource*(composed: ComposedServer, uri: string): Option[MountPoint] =
  ## Find the mount point that should handle a given resource URI
  for mountPoint in composed.mountPoints:
    if mountPoint.prefix.isSome:
      let prefix = mountPoint.prefix.get()
      if uri.startsWith(mountPoint.path) or uri.startsWith(prefix):
        result = some(mountPoint)
        return
    else:
      # Check if the mounted server has this resource
      let server = mountPoint.server
      let resources = server.getRegisteredResourceUris()
      if uri in resources:
        result = some(mountPoint)
        return

  return none(MountPoint)

proc findMountPointForPrompt*(composed: ComposedServer, promptName: string): Option[MountPoint] =
  ## Find the mount point that should handle a given prompt name
  for mountPoint in composed.mountPoints:
    if mountPoint.prefix.isSome:
      let prefix = mountPoint.prefix.get()
      if promptName.startsWith(prefix):
        return some(mountPoint)
    else:
      # Check if the mounted server has this prompt
      let server = mountPoint.server
      let prompts = server.getRegisteredPromptNames()
      if promptName in prompts:
        return some(mountPoint)
  
  return none(MountPoint)

proc stripPrefix*(name: string, prefix: Option[string]): string =
  ## Strip prefix from a name if present
  if prefix.isSome:
    let prefixStr = prefix.get()
    if name.startsWith(prefixStr):
      return name[prefixStr.len..^1]
  return name

proc addPrefix*(name: string, prefix: Option[string]): string =
  ## Add prefix to a name if specified
  if prefix.isSome:
    return prefix.get() & name
  return name

proc listMountPoints*(composed: ComposedServer): seq[MountPoint] =
  ## List all mount points
  return composed.mountPoints

proc getMountedServerInfo*(composed: ComposedServer): Table[string, JsonNode] =
  ## Get information about all mounted servers
  result = initTable[string, JsonNode]()
  
  for mountPoint in composed.mountPoints:
    let server = mountPoint.server
    var info = newJObject()
    info["path"] = %mountPoint.path
    info["serverName"] = %server.serverInfo.name
    info["serverVersion"] = %server.serverInfo.version
    if mountPoint.prefix.isSome:
      info["prefix"] = %mountPoint.prefix.get()
    info["toolCount"] = %server.getRegisteredToolNames().len
    info["resourceCount"] = %server.getRegisteredResourceUris().len
    info["promptCount"] = %server.getRegisteredPromptNames().len
    
    result[mountPoint.path] = info
