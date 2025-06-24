## Core MCP protocol types and data structures

import json, tables, options, asyncdispatch
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
    isError*: Option[bool]

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
  McpToolHandler* = proc(args: JsonNode): Future[McpToolResult] {.async.}
  McpResourceHandler* = proc(uri: string): Future[McpResourceContents] {.async.}
  McpPromptHandler* = proc(name: string, args: Table[string, JsonNode]): Future[McpGetPromptResult] {.async.}

# JSON-RPC error codes
const
  ParseError* = -32700
  InvalidRequest* = -32600
  MethodNotFound* = -32601
  InvalidParams* = -32602
  InternalError* = -32603