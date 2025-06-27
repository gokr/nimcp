## MCP Server implementation using taskpools for concurrent request processing
##
## This module provides the main MCP server implementation using the modern
## taskpools library for better performance and energy efficiency.

import json, tables, options, locks, cpuinfo, strutils, times, algorithm
import taskpools
import types, protocol, context, schema, resource_templates, logging

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
  
  # Initialize logging with server-specific component name
  result.logger = newLogger(llInfo)
  result.logger.setComponent("mcp-server-" & name)
  result.logger.setupChroniclesLogging()
  
  # Initialize taskpool with specified or auto-detected thread count
  let threads = if numThreads > 0: numThreads else: countProcessors()
  result.taskpool = Taskpool.new(numThreads = threads)
  
  # Initialize the context manager
  initContextManager()
  
  # Log server initialization
  result.logger.info("MCP server initialized", 
    context = {"name": %name, "version": %version, "threads": %threads}.toTable)

proc shutdown*(server: McpServer) =
  ## Shutdown the server and clean up resources
  server.logger.info("Shutting down MCP server")
  
  if server.taskpool != nil:
    server.taskpool.syncAll()
    server.taskpool.shutdown()
  
  # Clean up any remaining contexts
  cleanupExpiredContexts()
  
  server.logger.info("MCP server shutdown complete")

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

# Alternative UFCS style: object.registerWith(server, handler)

proc registerWith*(tool: McpTool, server: McpServer, handler: McpToolHandler): McpServer =
  ## UFCS: Register this tool with the server
  server.registerTool(tool, handler)
  server

proc registerWithContext*(tool: McpTool, server: McpServer, handler: McpToolHandlerWithContext): McpServer =
  ## UFCS: Register this tool with context support with the server
  server.registerToolWithContext(tool, handler)
  server

proc registerWith*(resource: McpResource, server: McpServer, handler: McpResourceHandler): McpServer =
  ## UFCS: Register this resource with the server
  server.registerResource(resource, handler)
  server

proc registerWithContext*(resource: McpResource, server: McpServer, handler: McpResourceHandlerWithContext): McpServer =
  ## UFCS: Register this resource with context support with the server
  server.registerResourceWithContext(resource, handler)
  server

proc registerWith*(prompt: McpPrompt, server: McpServer, handler: McpPromptHandler): McpServer =
  ## UFCS: Register this prompt with the server
  server.registerPrompt(prompt, handler)
  server

proc registerWithContext*(prompt: McpPrompt, server: McpServer, handler: McpPromptHandlerWithContext): McpServer =
  ## UFCS: Register this prompt with context support with the server
  server.registerPromptWithContext(prompt, handler)
  server

proc registerWith*(resourceTemplate: McpResourceTemplate, server: McpServer, handler: ResourceTemplateHandler): McpServer =
  ## UFCS: Register this resource template with the server
  server.registerResourceTemplate(resourceTemplate, handler)
  server

proc registerWithContext*(resourceTemplate: McpResourceTemplate, server: McpServer, handler: ResourceTemplateHandlerWithContext): McpServer =
  ## UFCS: Register this resource template with context support with the server
  server.registerResourceTemplateWithContext(resourceTemplate, handler)
  server

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
  server.requestTimeout

proc isContextLoggingEnabled*(server: McpServer): bool =
  ## Check if context logging is enabled
  server.enableContextLogging

# Logging configuration methods
proc setLogger*(server: McpServer, logger: Logger) =
  ## Set a custom logger for the server
  server.logger = logger

proc getLogger*(server: McpServer): Logger =
  ## Get the server's logger
  server.logger

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
    
    # Create response manually to avoid GC safety issues  
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
        # Skip resource content for now to avoid more GC safety issues
        discard
      responseJson["content"].add(contentJson)
    return responseJson
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
  
  # If no direct handler found, try resource templates
  if not hasContextHandler and not hasRegularHandler:
    let requestCtx = if ctx != nil: ctx else: newMcpRequestContext()
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
    let requestCtx = if ctx != nil: ctx else: newMcpRequestContext()
    
    if server.enableContextLogging:
      requestCtx.logMessage("info", "Accessing resource: " & uri)
    
    let res = if hasContextHandler:
      contextHandler(requestCtx, uri)
    else:
      regularHandler(uri)
    
    # Create response manually to avoid GC safety issues
    var responseJson = newJObject()
    responseJson["uri"] = newJString(res.uri)
    if res.mimeType.isSome:
      responseJson["mimeType"] = newJString(res.mimeType.get)
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
        # Skip resource content for now to avoid more GC safety issues
        discard
      responseJson["content"].add(contentJson)
    return responseJson
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

proc getMainServer*(composed: ComposedServer): McpServer =
  ## Get the main server from a composed server
  composed.mainServer  # Direct ref access instead of unsafe pointer cast

proc getMountedServer*(mountPoint: MountPoint): McpServer =
  ## Get the server from a mount point
  mountPoint.server  # Direct ref access instead of unsafe pointer cast

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
      let server = getMountedServer(mountPoint)
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
      let server = getMountedServer(mountPoint)
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
      let server = getMountedServer(mountPoint)
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
    let server = getMountedServer(mountPoint)
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
