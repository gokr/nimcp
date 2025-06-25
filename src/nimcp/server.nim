## MCP Server implementation with stdio transport

import json, tables, options, locks
import json_serialization
import types, protocol

{.push warning[GcUnsafe2]:off.}

type
  McpServer* = ref object
    serverInfo*: McpServerInfo
    capabilities*: McpCapabilities
    tools*: Table[string, McpTool]
    toolHandlers*: Table[string, McpToolHandler]
    resources*: Table[string, McpResource]
    resourceHandlers*: Table[string, McpResourceHandler]  
    prompts*: Table[string, McpPrompt]
    promptHandlers*: Table[string, McpPromptHandler]
    initialized*: bool

proc newMcpServer*(name: string, version: string): McpServer =
  result = McpServer(
    serverInfo: McpServerInfo(name: name, version: version),
    capabilities: McpCapabilities(),
    tools: initTable[string, McpTool](),
    toolHandlers: initTable[string, McpToolHandler](),
    resources: initTable[string, McpResource](),
    resourceHandlers: initTable[string, McpResourceHandler](),
    prompts: initTable[string, McpPrompt](),
    promptHandlers: initTable[string, McpPromptHandler](),
    initialized: false
  )

# Tool registration
proc registerTool*(server: McpServer, tool: McpTool, handler: McpToolHandler) =
  server.tools[tool.name] = tool
  server.toolHandlers[tool.name] = handler
  
  # Enable tools capability
  if server.capabilities.tools.isNone:
    server.capabilities.tools = some(McpToolsCapability())

# Resource registration  
proc registerResource*(server: McpServer, resource: McpResource, handler: McpResourceHandler) =
  server.resources[resource.uri] = resource
  server.resourceHandlers[resource.uri] = handler
  
  # Enable resources capability
  if server.capabilities.resources.isNone:
    server.capabilities.resources = some(McpResourcesCapability())

# Prompt registration
proc registerPrompt*(server: McpServer, prompt: McpPrompt, handler: McpPromptHandler) =
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
  for tool in server.tools.values:
    tools.add(tool)
  return createToolsListResponse(tools)

proc handleToolsCall(server: McpServer, params: JsonNode): JsonNode {.gcsafe.} =
  let toolName = params["name"].getStr()
  let args = if params.hasKey("arguments"): params["arguments"] else: newJObject()
  
  if toolName notin server.toolHandlers:
    raise newException(ValueError, "Tool not found: " & toolName)
  
  let handler = server.toolHandlers[toolName]
  let res = handler(args)
  return parseJson(toJson(res))

proc handleResourcesList(server: McpServer): JsonNode {.gcsafe.} =
  var resources: seq[McpResource] = @[]
  for resource in server.resources.values:
    resources.add(resource)
  return createResourcesListResponse(resources)

proc handleResourcesRead(server: McpServer, params: JsonNode): JsonNode {.gcsafe.} =
  let uri = params["uri"].getStr()
  
  if uri notin server.resourceHandlers:
    raise newException(ValueError, "Resource not found: " & uri)
  
  let handler = server.resourceHandlers[uri]
  let res = handler(uri)
  return parseJson(toJson(res))

proc handlePromptsList(server: McpServer): JsonNode {.gcsafe.} =
  var prompts: seq[McpPrompt] = @[]
  for prompt in server.prompts.values:
    prompts.add(prompt)
  return createPromptsListResponse(prompts)

proc handlePromptsGet(server: McpServer, params: JsonNode): JsonNode {.gcsafe.} =
  let promptName = params["name"].getStr()
  var args = initTable[string, JsonNode]()
  
  if params.hasKey("arguments"):
    for key, value in params["arguments"]:
      args[key] = value
  
  if promptName notin server.promptHandlers:
    raise newException(ValueError, "Prompt not found: " & promptName)
  
  let handler = server.promptHandlers[promptName]
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

# Thread data for request processing
type
  RequestThread* = Thread[tuple[server: McpServer, line: string]]

proc processRequestThread(data: tuple[server: McpServer, line: string]) {.thread.} =
  let (server, requestLine) = data
  var requestId: JsonRpcId = JsonRpcId(kind: jridString, str: "")
  
  try:
    let request = parseJsonRpcMessage(requestLine)
    
    # Extract ID for error handling
    if request.id.isSome:
      requestId = request.id.get
    
    # Check if this is a notification (no ID) - don't send response
    if request.id.isNone:
      server.handleNotification(request)
    else:
      # This is a request - send response
      let response = server.handleRequest(request)
      # Manual JSON creation to avoid thread safety issues
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

# Stdio transport implementation with concurrent request handling
proc runStdio*(server: McpServer) =
  var threads: seq[RequestThread] = @[]
  
  while true:
    try:
      let line = stdin.readLine()
      if line.len == 0:
        break
      
      # Create and start a new thread for this request
      var thread: RequestThread
      createThread(thread, processRequestThread, (server, line))
      threads.add(thread)
      
    except EOFError:
      # Input stream ended, wait for all threads to complete
      for thread in threads:
        joinThread(thread)
      break
    except Exception:
      # Other exceptions while reading input
      for thread in threads:
        joinThread(thread)
      break
  
  # Wait for any remaining threads to complete
  for thread in threads:
    joinThread(thread)