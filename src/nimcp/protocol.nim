## MCP protocol message handling and JSON-RPC 2.0 implementation

import json, options, tables
import types

# JSON-RPC 2.0 message creation helpers
proc createJsonRpcResponse*(id: JsonRpcId, resultData: JsonNode): JsonRpcResponse =
  JsonRpcResponse(
    jsonrpc: "2.0",
    id: id,
    result: some(resultData)
    # Don't set error field for successful responses
  )

proc createJsonRpcError*(id: JsonRpcId, code: int, message: string): JsonRpcResponse =
  let error = JsonRpcError(
    code: code,
    message: message,
    data: none(JsonNode)
  )
  JsonRpcResponse(
    jsonrpc: "2.0", 
    id: id,
    error: some(error)
    # Don't set result field for error responses
  )

proc createJsonRpcNotification*(methodName: string): JsonRpcNotification =
  JsonRpcNotification(
    jsonrpc: "2.0",
    `method`: methodName,
    params: none(JsonNode)
  )

proc createJsonRpcNotification*(methodName: string, params: JsonNode): JsonRpcNotification =
  JsonRpcNotification(
    jsonrpc: "2.0",
    `method`: methodName,
    params: some(params)
  )

# Message parsing
proc parseJsonRpcMessage*(data: string): JsonRpcRequest =
  let parsed = parseJson(data)
  result = JsonRpcRequest(
    jsonrpc: parsed["jsonrpc"].getStr(),
    `method`: parsed["method"].getStr()
  )
  
  if parsed.hasKey("id"):
    let idNode = parsed["id"]
    if idNode.kind == JString:
      result.id = some(JsonRpcId(kind: jridString, str: idNode.getStr()))
    elif idNode.kind == JInt:
      result.id = some(JsonRpcId(kind: jridInt, num: idNode.getInt()))
  
  if parsed.hasKey("params"):
    result.params = some(parsed["params"])

# Helper to create capabilities without null fields
proc cleanCapabilities*(caps: McpCapabilities): JsonNode =
  result = newJObject()
  
  if caps.tools.isSome:
    let toolsCap = newJObject()
    if caps.tools.get.listChanged.isSome:
      toolsCap["listChanged"] = %caps.tools.get.listChanged.get
    result["tools"] = toolsCap
  
  if caps.resources.isSome:
    let resourcesCap = newJObject()
    if caps.resources.get.subscribe.isSome:
      resourcesCap["subscribe"] = %caps.resources.get.subscribe.get
    if caps.resources.get.listChanged.isSome:
      resourcesCap["listChanged"] = %caps.resources.get.listChanged.get
    result["resources"] = resourcesCap
  
  if caps.prompts.isSome:
    let promptsCap = newJObject()
    if caps.prompts.get.listChanged.isSome:
      promptsCap["listChanged"] = %caps.prompts.get.listChanged.get
    result["prompts"] = promptsCap

  if caps.logging.isSome:
    result["logging"] = caps.logging.get

  if caps.experimental.isSome:
    result["experimental"] = %caps.experimental.get

  return result

# MCP-specific message handling using object variants
proc createInitializeResponse*(serverInfo: McpServerInfo, capabilities: McpCapabilities): McpResponse =
  McpResponse(
    kind: mrInitialize,
    protocolVersion: MCP_PROTOCOL_VERSION,
    serverInfo: serverInfo,
    capabilities: capabilities
  )

proc createToolsListResponse*(tools: seq[McpTool]): McpResponse =
  McpResponse(
    kind: mrToolsList,
    tools: tools
  )

proc createResourcesListResponse*(resources: seq[McpResource]): McpResponse =
  McpResponse(
    kind: mrResourcesList,
    resources: resources
  )

proc createPromptsListResponse*(prompts: seq[McpPrompt]): McpResponse =
  McpResponse(
    kind: mrPromptsList,
    prompts: prompts
  )

proc createToolsCallResponse*(toolResult: McpToolResult): McpResponse =
  McpResponse(
    kind: mrToolsCall,
    toolResult: toolResult
  )

proc createResourcesReadResponse*(resourceContents: McpResourceContents): McpResponse =
  McpResponse(
    kind: mrResourcesRead,
    resourceContents: resourceContents
  )

proc createPromptsGetResponse*(promptResult: McpGetPromptResult): McpResponse =
  McpResponse(
    kind: mrPromptsGet,
    promptResult: promptResult
  )

proc createErrorResponse*(error: McpStructuredError): McpResponse =
  McpResponse(
    kind: mrError,
    error: error
  )

# Legacy JSON response functions for backward compatibility
proc createInitializeResponseJson*(serverInfo: McpServerInfo, capabilities: McpCapabilities): JsonNode =
  %*{
    "protocolVersion": MCP_PROTOCOL_VERSION,
    "serverInfo": serverInfo,
    "capabilities": cleanCapabilities(capabilities)
  }

proc createToolsListResponseJson*(tools: seq[McpTool]): JsonNode =
  %*{"tools": tools}

proc createResourcesListResponseJson*(resources: seq[McpResource]): JsonNode =
  %*{"resources": resources}

proc createPromptsListResponseJson*(prompts: seq[McpPrompt]): JsonNode =
  %*{"prompts": prompts}

# Convert McpResponse to JsonNode for serialization
proc toJsonNode*(response: McpResponse): JsonNode =
  case response.kind:
  of mrInitialize:
    result = %*{
      "protocolVersion": response.protocolVersion,
      "serverInfo": response.serverInfo,
      "capabilities": cleanCapabilities(response.capabilities)
    }
  of mrToolsList:
    result = %*{"tools": response.tools}
  of mrToolsCall:
    result = %response.toolResult
  of mrResourcesList:
    result = %*{"resources": response.resources}
  of mrResourcesRead:
    result = %response.resourceContents
  of mrPromptsList:
    result = %*{"prompts": response.prompts}
  of mrPromptsGet:
    result = %response.promptResult
  of mrError:
    # Use custom serialization to avoid DateTime issues
    result = newJObject()
    result["code"] = %response.error.code
    result["message"] = %response.error.message

  return result


# Content creation helpers
proc createTextContent*(text: string): McpContent =
  McpContent(
    `type`: "text",
    kind: TextContent,
    text: text
  )

proc createImageContent*(data: string, mimeType: string): McpContent =
  McpContent(
    `type`: "image", 
    kind: ImageContent,
    data: data,
    mimeType: mimeType
  )

proc createResourceContent*(resource: McpResourceContents): McpContent =
  McpContent(
    `type`: "resource",
    kind: ResourceContent,
    resource: resource
  )