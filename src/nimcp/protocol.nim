## MCP protocol message handling and JSON-RPC 2.0 implementation

import json, options, tables
import json_serialization
import types

# JSON-RPC 2.0 message creation helpers
proc createJsonRpcResponse*(id: JsonRpcId, resultData: JsonNode): JsonRpcResponse =
  JsonRpcResponse(
    jsonrpc: "2.0",
    id: id,
    result: some(resultData),
    error: none(JsonRpcError)
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
    result: none(JsonNode),
    error: some(error)
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

# MCP-specific message handling
proc createInitializeResponse*(serverInfo: McpServerInfo, capabilities: McpCapabilities): JsonNode =
  %*{
    "protocolVersion": "2024-11-05",
    "serverInfo": serverInfo,
    "capabilities": capabilities
  }

proc createToolsListResponse*(tools: seq[McpTool]): JsonNode =
  %*{"tools": tools}

proc createResourcesListResponse*(resources: seq[McpResource]): JsonNode =
  %*{"resources": resources}

proc createPromptsListResponse*(prompts: seq[McpPrompt]): JsonNode =
  %*{"prompts": prompts}

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