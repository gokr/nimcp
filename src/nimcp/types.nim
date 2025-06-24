## Core MCP protocol types and data structures

import json, tables, options
import json_serialization

type
  # JSON-RPC 2.0 base types
  JsonRpcIdKind* = enum
    jridString, jridInt
  
  JsonRpcId* = object
    case kind*: JsonRpcIdKind
    of jridString: str*: string
    of jridInt: num*: int
  
  JsonRpcRequest* = object
    jsonrpc*: string
    id*: Option[JsonRpcId]
    `method`*: string
    params*: Option[JsonNode]

  JsonRpcResponse* = object
    jsonrpc*: string
    id*: JsonRpcId
    result*: Option[JsonNode]
    error*: Option[JsonRpcError]

  JsonRpcNotification* = object
    jsonrpc*: string
    `method`*: string
    params*: Option[JsonNode]

  JsonRpcError* = object
    code*: int
    message*: string
    data*: Option[JsonNode]

  # MCP-specific types
  McpCapabilities* = object
    experimental*: Option[Table[string, JsonNode]]
    logging*: Option[JsonNode]
    prompts*: Option[McpPromptsCapability]
    resources*: Option[McpResourcesCapability]
    tools*: Option[McpToolsCapability]

  McpPromptsCapability* = object
    listChanged*: Option[bool]

  McpResourcesCapability* = object
    subscribe*: Option[bool]
    listChanged*: Option[bool]

  McpToolsCapability* = object
    listChanged*: Option[bool]

  McpServerInfo* = object
    name*: string
    version*: string

  McpClientInfo* = object
    name*: string
    version*: string

  # Tool types
  McpTool* = object
    name*: string
    description*: Option[string]
    inputSchema*: JsonNode

  McpToolCall* = object
    name*: string
    arguments*: Option[JsonNode]

  McpToolResult* = object
    content*: seq[McpContent]

  # Resource types
  McpResource* = object
    uri*: string
    name*: string
    description*: Option[string]
    mimeType*: Option[string]

  McpResourceTemplate* = object
    uriTemplate*: string
    name*: string
    description*: Option[string]
    mimeType*: Option[string]

  McpResourceContents* = object
    uri*: string
    mimeType*: Option[string]
    content*: seq[McpContent]

  # Prompt types  
  McpPrompt* = object
    name*: string
    description*: Option[string]
    arguments*: seq[McpPromptArgument]

  McpPromptArgument* = object
    name*: string
    description*: Option[string]
    required*: Option[bool]

  McpPromptMessage* = object
    role*: McpRole
    content*: McpContent

  McpGetPromptResult* = object
    description*: Option[string]
    messages*: seq[McpPromptMessage]

  # Content types
  McpContentType* = enum
    TextContent = "text"
    ImageContent = "image" 
    ResourceContent = "resource"

  McpContent* = object
    `type`*: string
    case kind*: McpContentType
    of TextContent:
      text*: string
    of ImageContent:
      data*: string
      mimeType*: string
    of ResourceContent:
      resource*: McpResourceContents

  McpRole* = enum
    User = "user"
    Assistant = "assistant"
    System = "system"

  # Handler function types
  McpToolHandler* = proc(args: JsonNode): McpToolResult {.gcsafe, closure.}
  McpResourceHandler* = proc(uri: string): McpResourceContents {.gcsafe, closure.}
  McpPromptHandler* = proc(name: string, args: Table[string, JsonNode]): McpGetPromptResult {.gcsafe, closure.}

# Custom JSON serialization for JsonRpcId
proc `%`*(id: JsonRpcId): JsonNode =
  case id.kind
  of jridString:
    return %id.str
  of jridInt:
    return %id.num

proc to*(node: JsonNode, T: typedesc[JsonRpcId]): JsonRpcId =
  case node.kind
  of JString:
    return JsonRpcId(kind: jridString, str: node.getStr())
  of JInt:
    return JsonRpcId(kind: jridInt, num: node.getInt())
  else:
    raise newException(ValueError, "Invalid JsonRpcId format")

# JSON-RPC error codes
const
  ParseError* = -32700
  InvalidRequest* = -32600
  MethodNotFound* = -32601
  InvalidParams* = -32602
  InternalError* = -32603