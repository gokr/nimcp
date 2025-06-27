## Core MCP protocol types and data structures

import json, tables, options, times
import json_serialization

# Constants
const
  MCP_PROTOCOL_VERSION* = "2024-11-05"  ## Current MCP protocol version

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

    # Request context types
  McpRequestContext* = ref object
    ## Request context providing access to server state and utilities
    requestId*: string
    startTime*: DateTime
    cancelled*: bool
    progressCallback*: proc(message: string, progress: float) {.gcsafe.}
    logCallback*: proc(level: string, message: string) {.gcsafe.}
    metadata*: Table[string, JsonNode]
  
  McpProgressInfo* = object
    ## Progress tracking information
    message*: string
    progress*: float  # 0.0 to 1.0
    timestamp*: DateTime
  
  # Enhanced error types with context
  McpErrorLevel* = enum
    melInfo = "info"
    melWarning = "warning" 
    melError = "error"
    melCritical = "critical"
  
  McpStructuredError* = object
    ## Enhanced error type with context and categorization
    code*: int
    level*: McpErrorLevel
    message*: string
    details*: Option[string]
    context*: Option[Table[string, JsonNode]]
    timestamp*: DateTime
    requestId*: Option[string]
    stackTrace*: Option[string]
  
  # Enhanced handler function types with context
  McpToolHandler* = proc(args: JsonNode): McpToolResult {.gcsafe, closure.}
  McpToolHandlerWithContext* = proc(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe, closure.}
  McpResourceHandler* = proc(uri: string): McpResourceContents {.gcsafe, closure.}
  McpResourceHandlerWithContext* = proc(ctx: McpRequestContext, uri: string): McpResourceContents {.gcsafe, closure.}
  McpPromptHandler* = proc(name: string, args: Table[string, JsonNode]): McpGetPromptResult {.gcsafe, closure.}
  McpPromptHandlerWithContext* = proc(ctx: McpRequestContext, name: string, args: Table[string, JsonNode]): McpGetPromptResult {.gcsafe, closure.}
  
  # Middleware types
  McpMiddleware* = object
    ## Middleware for request/response processing
    name*: string
    priority*: int  # Lower numbers execute first
    beforeRequest*: proc(ctx: McpRequestContext, request: JsonRpcRequest): JsonRpcRequest {.gcsafe.}
    afterResponse*: proc(ctx: McpRequestContext, response: JsonRpcResponse): JsonRpcResponse {.gcsafe.}
    onError*: proc(ctx: McpRequestContext, error: McpStructuredError): McpStructuredError {.gcsafe.}

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

# JSON-RPC error codes (as per JSON-RPC 2.0 specification)
const
  ParseError* = -32700      ## Invalid JSON was received by the server
  InvalidRequest* = -32600  ## The JSON sent is not a valid Request object
  MethodNotFound* = -32601  ## The method does not exist / is not available
  InvalidParams* = -32602   ## Invalid method parameter(s)
  InternalError* = -32603   ## Internal JSON-RPC error

# MCP-specific error codes (application-defined range)
const
  McpServerNotInitialized* = -32000  ## Server has not been initialized yet
  McpToolNotFound* = -32001          ## Requested tool does not exist
  McpResourceNotFound* = -32002      ## Requested resource does not exist
  McpPromptNotFound* = -32003        ## Requested prompt does not exist
  McpAuthenticationRequired* = -32004 ## Authentication is required
  McpAuthenticationFailed* = -32005   ## Authentication failed
  McpRateLimitExceeded* = -32006     ## Rate limit exceeded
  McpRequestCancelled* = -32007      ## Request was cancelled
  McpValidationError* = -32008       ## Parameter validation failed
  McpMiddlewareError* = -32009       ## Middleware processing error

# Transport configuration types
type
  McpTransportKind* = enum
    mtStdio,    ## Standard input/output transport
    mtHttp,     ## HTTP transport
    mtWebSocket ## WebSocket transport
  
  McpTransportConfig* = object
    case kind*: McpTransportKind
    of mtStdio:
      discard
    of mtHttp:
      port*: int
      host*: string
      requireHttps*: bool
      tokenValidator*: proc(token: string): bool {.gcsafe.}
    of mtWebSocket:
      wsPort*: int
      wsHost*: string
      wsRequireHttps*: bool
      wsTokenValidator*: proc(token: string): bool {.gcsafe.}

# Enhanced content types for advanced schema support
type
  McpSchemaType* = enum
    mstString = "string"
    mstInteger = "integer" 
    mstNumber = "number"
    mstBoolean = "boolean"
    mstArray = "array"
    mstObject = "object"
    mstNull = "null"
    mstUnion = "union"
    mstEnum = "enum"
  
  McpUnionType* = object
    ## Union type for multiple allowed types
    anyOf*: seq[JsonNode]
  
  McpEnumType* = object
    ## Enum type for constrained string values
    `enum`*: seq[string]
    description*: Option[string]
  
  McpObjectProperty* = object
    ## Object property definition
    `type`*: McpSchemaType
    description*: Option[string]
    required*: bool
    default*: Option[JsonNode]
    schema*: Option[JsonNode]  # For nested objects
  
  McpObjectSchema* = object
    ## Object schema definition
    properties*: Table[string, McpObjectProperty]
    required*: seq[string]
    additionalProperties*: bool

# Convenience constructor functions for transport configs
proc StdioTransport*(): McpTransportConfig =
  ## Create a stdio transport configuration
  McpTransportConfig(kind: mtStdio)

proc HttpTransport*(port: int = 8080, host: string = "127.0.0.1"): McpTransportConfig =
  ## Create an HTTP transport configuration
  McpTransportConfig(
    kind: mtHttp,
    port: port,
    host: host,
    requireHttps: false,
    tokenValidator: nil
  )

proc HttpTransportAuth*(port: int = 8080, host: string = "127.0.0.1", 
                       requireHttps: bool = false, 
                       tokenValidator: proc(token: string): bool {.gcsafe.}): McpTransportConfig =
  ## Create an HTTP transport configuration with authentication
  McpTransportConfig(
    kind: mtHttp,
    port: port,
    host: host,
    requireHttps: requireHttps,
    tokenValidator: tokenValidator
  )

proc WebSocketTransport*(port: int = 8080, host: string = "127.0.0.1"): McpTransportConfig =
  ## Create a WebSocket transport configuration
  McpTransportConfig(
    kind: mtWebSocket,
    wsPort: port,
    wsHost: host,
    wsRequireHttps: false,
    wsTokenValidator: nil
  )

proc WebSocketTransportAuth*(port: int = 8080, host: string = "127.0.0.1", 
                            requireHttps: bool = false, 
                            tokenValidator: proc(token: string): bool {.gcsafe.}): McpTransportConfig =
  ## Create a WebSocket transport configuration with authentication
  McpTransportConfig(
    kind: mtWebSocket,
    wsPort: port,
    wsHost: host,
    wsRequireHttps: requireHttps,
    wsTokenValidator: tokenValidator
  )

# Context utility functions are now in context.nim module to avoid duplication

# Structured error utilities are now in context.nim module to avoid duplication

# Convenience functions for content creation are in protocol.nim to avoid duplication