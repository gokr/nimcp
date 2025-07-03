## MCP protocol message handling and JSON-RPC 2.0 implementation

import json, options
import types, context

# JSON-RPC 2.0 message creation helpers
proc createJsonRpcResponse*(id: JsonRpcId, resultData: JsonNode): JsonRpcResponse =
  JsonRpcResponse(
    jsonrpc: "2.0",
    id: id,
    result: some(resultData)
    # Don't set error field for successful responses
  )

proc createJsonRpcError*(id: JsonRpcId, code: int, message: string, data: Option[JsonNode] = none(JsonNode)): JsonRpcResponse =
  ## Create JSON-RPC error response with optional data
  let error = JsonRpcError(
    code: code,
    message: message,
    data: data
  )
  JsonRpcResponse(
    jsonrpc: "2.0",
    id: id,
    error: some(error)
    # Don't set result field for error responses
  )

# Consolidated error response utilities
proc createParseError*(id: JsonRpcId = JsonRpcId(kind: jridString, str: ""), details: string = ""): JsonRpcResponse =
  ## Create standardized parse error response
  let message = if details.len > 0: "Parse error: " & details else: "Parse error"
  createJsonRpcError(id, ParseError, message)

proc createInvalidRequest*(id: JsonRpcId = JsonRpcId(kind: jridString, str: ""), details: string = ""): JsonRpcResponse =
  ## Create standardized invalid request error response
  let message = if details.len > 0: "Invalid request: " & details else: "Invalid request"
  createJsonRpcError(id, InvalidRequest, message)

proc createMethodNotFound*(id: JsonRpcId, methodName: string): JsonRpcResponse =
  ## Create standardized method not found error response
  createJsonRpcError(id, MethodNotFound, "Method not found: " & methodName)

proc createInvalidParams*(id: JsonRpcId, details: string = ""): JsonRpcResponse =
  ## Create standardized invalid params error response
  let message = if details.len > 0: "Invalid params: " & details else: "Invalid params"
  createJsonRpcError(id, InvalidParams, message)

proc createInternalError*(id: JsonRpcId, details: string = ""): JsonRpcResponse =
  ## Create standardized internal error response
  let message = if details.len > 0: "Internal error: " & details else: "Internal error"
  createJsonRpcError(id, InternalError, message)

proc createStructuredErrorResponse*(id: JsonRpcId, error: McpStructuredError): JsonRpcResponse =
  ## Create JSON-RPC response from structured error using centralized conversion
  JsonRpcResponse(
    jsonrpc: "2.0",
    id: id,
    error: some(error.toJsonRpcError())
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

proc `$`*(response: JsonRpcResponse): string =
  ## Custom string representation for JsonRpcResponse to ensure clean JSON output.
  var responseJson = newJObject()
  responseJson["jsonrpc"] = %response.jsonrpc
  responseJson["id"] = %response.id
  if response.result.isSome():
    responseJson["result"] = response.result.get()
  if response.error.isSome():
    responseJson["error"] = %response.error.get()
  $responseJson

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