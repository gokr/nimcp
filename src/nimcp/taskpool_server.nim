## Modern MCP Server implementation using taskpools for concurrent request processing
##
## This module provides an alternative to the deprecated threadpool-based server
## implementation, using the modern taskpools library for better performance
## and energy efficiency.

import json, tables, options, locks, cpuinfo
import json_serialization
import taskpools
import types, protocol

# Fine-grained locks for thread-safe access to server data structures
var toolsLock: Lock
var resourcesLock: Lock
var promptsLock: Lock
initLock(toolsLock)
initLock(resourcesLock)
initLock(promptsLock)

type
  TaskpoolMcpServer* = ref object
    ## Modern MCP server using taskpools for concurrent processing
    serverInfo*: McpServerInfo
    capabilities*: McpCapabilities
    tools*: Table[string, McpTool]
    toolHandlers*: Table[string, McpToolHandler]
    resources*: Table[string, McpResource]
    resourceHandlers*: Table[string, McpResourceHandler]
    prompts*: Table[string, McpPrompt]
    promptHandlers*: Table[string, McpPromptHandler]
    initialized*: bool
    taskpool*: Taskpool

proc newTaskpoolMcpServer*(name: string, version: string, numThreads: int = 0): TaskpoolMcpServer =
  ## Create a new MCP server instance using taskpools for concurrency.
  ##
  ## Args:
  ##   name: Human-readable name for the server
  ##   version: Semantic version string (e.g., "1.0.0")
  ##   numThreads: Number of worker threads (0 = auto-detect)
  ##
  ## Returns:
  ##   A new TaskpoolMcpServer instance ready for registration
  result = TaskpoolMcpServer()
  result.serverInfo = McpServerInfo(name: name, version: version)
  result.capabilities = McpCapabilities()
  result.initialized = false
  
  # Initialize taskpool with specified or auto-detected thread count
  let threads = if numThreads > 0: numThreads else: countProcessors()
  result.taskpool = Taskpool.new(numThreads = threads)

proc shutdown*(server: TaskpoolMcpServer) =
  ## Shutdown the server and clean up resources
  if server.taskpool != nil:
    server.taskpool.syncAll()
    server.taskpool.shutdown()

# Registration functions (same as original server but with validation)
proc registerTool*(server: TaskpoolMcpServer, tool: McpTool, handler: McpToolHandler) =
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

proc registerResource*(server: TaskpoolMcpServer, resource: McpResource, handler: McpResourceHandler) =
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

proc registerPrompt*(server: TaskpoolMcpServer, prompt: McpPrompt, handler: McpPromptHandler) =
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

# Core message handlers (same logic as original server)
proc handleInitialize(server: TaskpoolMcpServer, params: JsonNode): JsonNode {.gcsafe.} =
  server.initialized = true
  return createInitializeResponse(server.serverInfo, server.capabilities)

proc handleToolsList(server: TaskpoolMcpServer): JsonNode {.gcsafe.} =
  var tools: seq[McpTool] = @[]
  withLock toolsLock:
    for tool in server.tools.values:
      tools.add(tool)
  return createToolsListResponse(tools)

proc handleToolsCall(server: TaskpoolMcpServer, params: JsonNode): JsonNode {.gcsafe.} =
  if not params.hasKey("name"):
    raise newException(ValueError, "Missing required parameter: name")
  
  let toolName = params["name"].getStr()
  if toolName.len == 0:
    raise newException(ValueError, "Tool name cannot be empty")
  
  let args = if params.hasKey("arguments"): params["arguments"] else: newJObject()
  
  var handler: McpToolHandler
  withLock toolsLock:
    if toolName notin server.toolHandlers:
      raise newException(ValueError, "Tool not found: " & toolName)
    handler = server.toolHandlers[toolName]
  
  try:
    let res = handler(args)
    return parseJson(toJson(res))
  except Exception as e:
    raise newException(ValueError, "Tool execution failed for '" & toolName & "': " & e.msg)

proc handleResourcesList(server: TaskpoolMcpServer): JsonNode {.gcsafe.} =
  var resources: seq[McpResource] = @[]
  withLock resourcesLock:
    for resource in server.resources.values:
      resources.add(resource)
  return createResourcesListResponse(resources)

proc handleResourcesRead(server: TaskpoolMcpServer, params: JsonNode): JsonNode {.gcsafe.} =
  if not params.hasKey("uri"):
    raise newException(ValueError, "Missing required parameter: uri")
  
  let uri = params["uri"].getStr()
  if uri.len == 0:
    raise newException(ValueError, "Resource URI cannot be empty")
  
  var handler: McpResourceHandler
  withLock resourcesLock:
    if uri notin server.resourceHandlers:
      raise newException(ValueError, "Resource not found: " & uri)
    handler = server.resourceHandlers[uri]
  
  try:
    let res = handler(uri)
    return parseJson(toJson(res))
  except Exception as e:
    raise newException(ValueError, "Resource access failed for '" & uri & "': " & e.msg)

proc handlePromptsList(server: TaskpoolMcpServer): JsonNode {.gcsafe.} =
  var prompts: seq[McpPrompt] = @[]
  withLock promptsLock:
    for prompt in server.prompts.values:
      prompts.add(prompt)
  return createPromptsListResponse(prompts)

proc handlePromptsGet(server: TaskpoolMcpServer, params: JsonNode): JsonNode {.gcsafe.} =
  if not params.hasKey("name"):
    raise newException(ValueError, "Missing required parameter: name")
  
  let promptName = params["name"].getStr()
  if promptName.len == 0:
    raise newException(ValueError, "Prompt name cannot be empty")
  
  var args = initTable[string, JsonNode]()
  if params.hasKey("arguments"):
    for key, value in params["arguments"]:
      args[key] = value
  
  var handler: McpPromptHandler
  withLock promptsLock:
    if promptName notin server.promptHandlers:
      raise newException(ValueError, "Prompt not found: " & promptName)
    handler = server.promptHandlers[promptName]
  
  try:
    let res = handler(promptName, args)
    return parseJson(toJson(res))
  except Exception as e:
    raise newException(ValueError, "Prompt execution failed for '" & promptName & "': " & e.msg)

proc handleNotification*(server: TaskpoolMcpServer, request: JsonRpcRequest) {.gcsafe.} =
  try:
    case request.`method`:
      of "initialized":
        discard
      else:
        discard
  except Exception:
    discard

proc handleRequest*(server: TaskpoolMcpServer, request: JsonRpcRequest): JsonRpcResponse {.gcsafe.} =
  if request.id.isNone:
    server.handleNotification(request)
    return JsonRpcResponse()
  
  let id = request.id.get
  
  try:
    if request.`method` != "initialize" and not server.initialized:
      return createJsonRpcError(id, McpServerNotInitialized, "Server must be initialized before calling " & request.`method`)
    
    let res = case request.`method`:
      of "initialize":
        server.handleInitialize(request.params.get(newJObject()))
      of "tools/list":
        server.handleToolsList()
      of "tools/call":
        server.handleToolsCall(request.params.get(newJObject()))
      of "resources/list":
        server.handleResourcesList()
      of "resources/read":
        server.handleResourcesRead(request.params.get(newJObject()))
      of "prompts/list":
        server.handlePromptsList()
      of "prompts/get":
        server.handlePromptsGet(request.params.get(newJObject()))
      else:
        return createJsonRpcError(id, MethodNotFound, "Method not found: " & request.`method`)
    
    return createJsonRpcResponse(id, res)
    
  except ValueError as e:
    return createJsonRpcError(id, InvalidParams, e.msg)
  except JsonParsingError as e:
    return createJsonRpcError(id, ParseError, "JSON parsing error: " & e.msg)
  except Exception as e:
    return createJsonRpcError(id, InternalError, "Internal error: " & e.msg)

# Thread-safe output handling
var stdoutLock: Lock
initLock(stdoutLock)

proc safeEcho(msg: string) =
  withLock stdoutLock:
    echo msg
    stdout.flushFile()

# Global server pointer for taskpools (similar to threadpool approach)
var globalTaskpoolServerPtr: ptr TaskpoolMcpServer

# Request processing task for taskpools - uses global pointer to avoid isolation issues
proc processRequestTask(requestLine: string) {.gcsafe.} =
  var requestId: JsonRpcId = JsonRpcId(kind: jridString, str: "")

  try:
    let request = parseJsonRpcMessage(requestLine)

    if request.id.isSome:
      requestId = request.id.get

    if request.id.isNone:
      globalTaskpoolServerPtr[].handleNotification(request)
    else:
      let response = globalTaskpoolServerPtr[].handleRequest(request)

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
proc runStdio*(server: TaskpoolMcpServer) =
  ## Run the MCP server with stdio transport using modern taskpools
  globalTaskpoolServerPtr = addr server

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
