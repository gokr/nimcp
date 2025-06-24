## MCP Server implementation with stdio transport

import asyncdispatch, json, tables, options, strutils
import json_serialization
import types, protocol

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
proc handleInitialize(server: McpServer, params: JsonNode): Future[JsonNode] {.async.} =
  server.initialized = true
  return createInitializeResponse(server.serverInfo, server.capabilities)

proc handleToolsList(server: McpServer): Future[JsonNode] {.async.} =
  var tools: seq[McpTool] = @[]
  for tool in server.tools.values:
    tools.add(tool)
  return createToolsListResponse(tools)

proc handleToolsCall(server: McpServer, params: JsonNode): Future[JsonNode] {.async.} =
  let toolName = params["name"].getStr()
  let args = if params.hasKey("arguments"): params["arguments"] else: newJObject()
  
  if toolName notin server.toolHandlers:
    raise newException(ValueError, "Tool not found: " & toolName)
  
  let handler = server.toolHandlers[toolName]
  let result = await handler(args)
  return %result

proc handleResourcesList(server: McpServer): Future[JsonNode] {.async.} =
  var resources: seq[McpResource] = @[]
  for resource in server.resources.values:
    resources.add(resource)
  return createResourcesListResponse(resources)

proc handleResourcesRead(server: McpServer, params: JsonNode): Future[JsonNode] {.async.} =
  let uri = params["uri"].getStr()
  
  if uri notin server.resourceHandlers:
    raise newException(ValueError, "Resource not found: " & uri)
  
  let handler = server.resourceHandlers[uri]
  let result = await handler(uri)
  return %result

proc handlePromptsList(server: McpServer): Future[JsonNode] {.async.} =
  var prompts: seq[McpPrompt] = @[]
  for prompt in server.prompts.values:
    prompts.add(prompt)
  return createPromptsListResponse(prompts)

proc handlePromptsGet(server: McpServer, params: JsonNode): Future[JsonNode] {.async.} =
  let promptName = params["name"].getStr()
  var args = initTable[string, JsonNode]()
  
  if params.hasKey("arguments"):
    for key, value in params["arguments"]:
      args[key] = value
  
  if promptName notin server.promptHandlers:
    raise newException(ValueError, "Prompt not found: " & promptName)
  
  let handler = server.promptHandlers[promptName]
  let result = await handler(promptName, args)
  return %result

# Main message dispatcher
proc handleRequest*(server: McpServer, request: JsonRpcRequest): Future[JsonRpcResponse] {.async.} =
  if request.id.isNone:
    # This should be a notification, not a request
    return createJsonRpcError(JsonRpcId(kind: jridString, str: ""), InvalidRequest, "Request missing ID")
  
  let id = request.id.get
  
  try:
    let result = case request.`method`:
      of "initialize":
        await server.handleInitialize(request.params.get(newJObject()))
      of "tools/list":
        await server.handleToolsList()
      of "tools/call":
        await server.handleToolsCall(request.params.get(newJObject()))
      of "resources/list":
        await server.handleResourcesList()  
      of "resources/read":
        await server.handleResourcesRead(request.params.get(newJObject()))
      of "prompts/list":
        await server.handlePromptsList()
      of "prompts/get":
        await server.handlePromptsGet(request.params.get(newJObject()))
      else:
        return createJsonRpcError(id, MethodNotFound, "Method not found: " & request.`method`)
    
    return createJsonRpcResponse(id, result)
    
  except ValueError as e:
    return createJsonRpcError(id, InvalidParams, e.msg)
  except Exception as e:
    return createJsonRpcError(id, InternalError, "Internal error: " & e.msg)

# Stdio transport implementation
proc runStdio*(server: McpServer) {.async.} =
  while true:
    try:
      let line = stdin.readLine()
      if line.len == 0:
        break
      
      try:
        let request = parseJsonRpcMessage(line)
        let response = await server.handleRequest(request)
        let responseJson = %response
        echo $responseJson
      except Exception as e:
        let errorResponse = createJsonRpcError(JsonRpcId(kind: jridString, str: ""), ParseError, "Parse error: " & e.msg)
        echo $(%errorResponse)
    except EOFError:
      # Input stream ended, exit gracefully
      break
    except Exception:
      # Other exceptions while reading input
      break