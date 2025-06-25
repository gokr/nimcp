## MCP Server implementation with stdio transport
# Note: Using deprecated threadpool for concurrent request processing
import json, tables, options, locks, threadpool
import json_serialization
import types, protocol

# Fine-grained locks for specific data structures
var toolsLock: Lock
var resourcesLock: Lock
var promptsLock: Lock
initLock(toolsLock)
initLock(resourcesLock)
initLock(promptsLock)

type
  McpServer* = ref object
    serverInfo*: McpServerInfo
    capabilities*: McpCapabilities
    tools*: Table[string, McpTool]
    toolHandlers*: Table[string, McpToolHandler]
    resourc# Note: Using deprecated threadpool for concurrent request processinges*: Table[string, McpResource]
    resourceHandlers*: Table[string, McpResourceHandler]  
    prompts*: Table[string, McpPrompt]
    promptHandlers*: Table[string, McpPromptHandler]
    initialized*: bool

# Global server reference for taskpool access (using pointer for GC safety)
var globalServerPtr: ptr McpServer

proc newMcpServer*(name: string, version: string): McpServer =
  result = McpServer()
  result.serverInfo = McpServerInfo(name: name, version: version)
  result.capabilities = McpCapabilities()
  result.initialized = false

# Tool registration
proc registerTool*(server: McpServer, tool: McpTool, handler: McpToolHandler) =
  withLock toolsLock:
    server.tools[tool.name] = tool
    server.toolHandlers[tool.name] = handler
  
  # Enable tools capability
  if server.capabilities.tools.isNone:
    server.capabilities.tools = some(McpToolsCapability())

# Resource registration  
proc registerResource*(server: McpServer, resource: McpResource, handler: McpResourceHandler) =
  withLock resourcesLock:
    server.resources[resource.uri] = resource
    server.resourceHandlers[resource.uri] = handler
  
  # Enable resources capability
  if server.capabilities.resources.isNone:
    server.capabilities.resources = some(McpResourcesCapability())

# Prompt registration
proc registerPrompt*(server: McpServer, prompt: McpPrompt, handler: McpPromptHandler) =
  withLock promptsLock:
    server.prompts[prompt.name] = prompt
    server.promptHandlers[prompt.name] = handler
  
  # Enable prompts capability
  if server.capabilities.prompts.isNone:
    server.capabilities.prompts = some(McpPromptsCapability())

# Core message handlers
proc handleInitialize(server: McpServer, params: JsonNode): JsonNode {.gcsafe.} =
  server.initialized = true
  return createInitializeResponse(server.serverInfo, server.capabilities)

proc handleToolsList(server: McpServer): JsonNode {.gcsafe.} =
  var tools: seq[McpTool] = @[]
  withLock toolsLock:
    for tool in server.tools.values:
      tools.add(tool)
  return createToolsListResponse(tools)

proc handleToolsCall(server: McpServer, params: JsonNode): JsonNode {.gcsafe.} =
  let toolName = params["name"].getStr()
  let args = if params.hasKey("arguments"): params["arguments"] else: newJObject()
  
  # Get handler with lock protection
  var handler: McpToolHandler
  withLock toolsLock:
    if toolName notin server.toolHandlers:
      raise newException(ValueError, "Tool not found: " & toolName)
    handler = server.toolHandlers[toolName]
  
  # Execute handler outside lock for true concurrency
  let res = handler(args)
  return parseJson(toJson(res))

proc handleResourcesList(server: McpServer): JsonNode {.gcsafe.} =
  var resources: seq[McpResource] = @[]
  withLock resourcesLock:
    for resource in server.resources.values:
      resources.add(resource)
  return createResourcesListResponse(resources)

proc handleResourcesRead(server: McpServer, params: JsonNode): JsonNode {.gcsafe.} =
  let uri = params["uri"].getStr()
  
  # Get handler with lock protection
  var handler: McpResourceHandler
  withLock resourcesLock:
    if uri notin server.resourceHandlers:
      raise newException(ValueError, "Resource not found: " & uri)
    handler = server.resourceHandlers[uri]
  
  # Execute handler outside lock for true concurrency
  let res = handler(uri)
  return parseJson(toJson(res))

proc handlePromptsList(server: McpServer): JsonNode {.gcsafe.} =
  var prompts: seq[McpPrompt] = @[]
  withLock promptsLock:
    for prompt in server.prompts.values:
      prompts.add(prompt)
  return createPromptsListResponse(prompts)

proc handlePromptsGet(server: McpServer, params: JsonNode): JsonNode {.gcsafe.} =
  let promptName = params["name"].getStr()
  var args = initTable[string, JsonNode]()
  
  if params.hasKey("arguments"):
    for key, value in params["arguments"]:
      args[key] = value
  
  # Get handler with lock protection
  var handler: McpPromptHandler
  withLock promptsLock:
    if promptName notin server.promptHandlers:
      raise newException(ValueError, "Prompt not found: " & promptName)
    handler = server.promptHandlers[promptName]
  
  # Execute handler outside lock for true concurrency
  let res = handler(promptName, args)
  return parseJson(toJson(res))

# Notification handler (messages without ID)
proc handleNotification*(server: McpServer, request: JsonRpcRequest) {.gcsafe.} =
  try:
    case request.`method`:
      of "initialized":
        # Client confirms initialization is complete
        # Nothing to do - just acknowledge internally
        discard
      else:
        # Unknown notification - ignore silently per JSON-RPC 2.0 spec
        discard
  except Exception:
    # Notifications should not generate error responses
    discard

# Main message dispatcher
proc handleRequest*(server: McpServer, request: JsonRpcRequest): JsonRpcResponse {.gcsafe.} =
  if request.id.isNone:
    # This is a notification - handle it but don't return a response
    server.handleNotification(request)
    return JsonRpcResponse() # Return empty response that won't be sent
  
  let id = request.id.get
  
  try:
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
  except Exception as e:
    return createJsonRpcError(id, InternalError, "Internal error: " & e.msg)

# Thread-safe output handling
var stdoutLock: Lock
initLock(stdoutLock)

proc safeEcho(msg: string) =
  withLock stdoutLock:
    echo msg
    stdout.flushFile()

# Request processing for threadpool - parse JSON and use global server
proc processRequest(requestLine: string): void {.gcsafe.} =
  var requestId: JsonRpcId = JsonRpcId(kind: jridString, str: "")
  
  try:
    # Parse JSON in the spawned task
    let request = parseJsonRpcMessage(requestLine)
    
    # Extract ID for error handling
    if request.id.isSome:
      requestId = request.id.get
    
    # Check if this is a notification (no ID) - don't send response
    if request.id.isNone:
      globalServerPtr[].handleNotification(request)
    else:
      # This is a request - send response
      let response = globalServerPtr[].handleRequest(request)
      
      # Manual JSON creation (outside lock to minimize critical section)
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

# Stdio transport implementation with concurrent request handling using threadpool
proc runStdio*(server: McpServer) =
  globalServerPtr = addr server  # Set global pointer for threadpool access
  while true:
    try:
      let line = stdin.readLine()
      if line.len == 0:
        break
      
      # Spawn task in threadpool - pass raw string for parsing in task
      spawn processRequest(line)
      
    except EOFError:
      # Input stream ended - sync all pending tasks
      sync()
      break
    except Exception:
      # Other exceptions while reading input - sync all pending tasks
      sync()
      break
  
  # Wait for all remaining tasks to complete
  sync()