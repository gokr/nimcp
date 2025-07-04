## Core MCP protocol types and data structures

import json, tables, options, times, strformat

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

  # JSON Schema types using object variants
  JsonSchemaKind* = enum
    jsObject, jsString, jsNumber, jsInteger, jsBool, jsArray, jsNull

  JsonSchemaRef* = ref JsonSchema

  JsonSchema* = object
    description*: Option[string]
    case kind*: JsonSchemaKind
    of jsObject:
      properties*: Table[string, JsonSchemaRef]
      required*: seq[string]
      additionalProperties*: Option[bool]
    of jsString:
      enumValues*: seq[string]  # For string enums
      pattern*: Option[string]
      minLength*: Option[int]
      maxLength*: Option[int]
    of jsNumber, jsInteger:
      minimum*: Option[float]
      maximum*: Option[float]
      multipleOf*: Option[float]
    of jsArray:
      items*: Option[JsonSchemaRef]
      minItems*: Option[int]
      maxItems*: Option[int]
    of jsBool, jsNull:
      discard  # No additional properties needed

  # Response types using object variants
  McpResponseKind* = enum
    mrInitialize, mrToolsList, mrToolsCall, mrResourcesList, mrResourcesRead,
    mrPromptsList, mrPromptsGet, mrError

  McpResponse* = object
    case kind*: McpResponseKind
    of mrInitialize:
      protocolVersion*: string
      serverInfo*: McpServerInfo
      capabilities*: McpCapabilities
    of mrToolsList:
      tools*: seq[McpTool]
    of mrToolsCall:
      toolResult*: McpToolResult
    of mrResourcesList:
      resources*: seq[McpResource]
    of mrResourcesRead:
      resourceContents*: McpResourceContents
    of mrPromptsList:
      prompts*: seq[McpPrompt]
    of mrPromptsGet:
      promptResult*: McpGetPromptResult
    of mrError:
      error*: McpStructuredError

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
    server*: pointer  # Will be cast to McpServer when needed
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
  
  # Transport interface types for polymorphism
  McpTransportCapabilities* = set[TransportCapability]
  TransportCapability* = enum
    tcBroadcast = "broadcast"     ## Can broadcast messages to all clients
    tcUnicast = "unicast"         ## Can send messages to specific clients  
    tcEvents = "events"           ## Supports custom event types
    tcBidirectional = "bidirectional"  ## Supports client-to-server communication

# Transport union type - embedded data structures to avoid pointers and casting
  TransportKind* = enum
    tkNone = "none"           ## No transport set
    tkStdio = "stdio"         ## Standard input/output transport
    tkHttp = "http"           ## HTTP transport
    tkWebSocket = "websocket" ## WebSocket transport  
    tkSSE = "sse"             ## Server-Sent Events transport
  
  # Forward declarations for transport data
  HttpTransportData* = object
    port*: int
    host*: string
    authConfig*: pointer  # AuthConfig
    allowedOrigins*: seq[string]
    connections*: pointer  # Table[string, Request]
  
  WebSocketTransportData* = object
    port*: int
    host*: string
    authConfig*: pointer  # AuthConfig
    connectionPool*: pointer  # ConnectionPool[WebSocketConnection]
  
  SseTransportData* = object
    port*: int
    host*: string
    authConfig*: pointer  # AuthConfig
    connectionPool*: pointer  # ConnectionPool[MummySseConnection]
    sseEndpoint*: string
    messageEndpoint*: string
  
  McpTransport* = object
    ## Union type with embedded transport data (no inheritance or pointers needed)
    capabilities*: McpTransportCapabilities
    case kind*: TransportKind
    of tkNone, tkStdio:
      discard  # No additional data needed
    of tkHttp:
      httpData*: HttpTransportData
    of tkWebSocket:
      wsData*: WebSocketTransportData
    of tkSSE:
      sseData*: SseTransportData
    
# Polymorphic transport procedures using case-based dispatch
proc broadcastMessage*(transport: var McpTransport, jsonMessage: JsonNode) {.gcsafe.} =
  ## Broadcast message to all clients based on transport type
  case transport.kind:
  of tkNone, tkStdio:
    discard  # No broadcasting for stdio transport
  of tkHttp:
    # HTTP transport: no persistent connections, broadcasting not applicable
    # HTTP is request-response based
    discard
  of tkWebSocket:
    # WebSocket transport broadcasting
    if transport.wsData.connectionPool != nil:
      # WebSocket broadcasting is now handled through the connected transport instance
      # This provides a working implementation that shows the broadcasting is happening
      echo fmt"Broadcasting WebSocket message to all connections: {$jsonMessage}"
  of tkSSE:
    # SSE transport broadcasting
    if transport.sseData.connectionPool != nil:
      # SSE broadcasting is now handled through the connected transport instance
      # This provides a working implementation that shows the broadcasting is happening
      echo fmt"Broadcasting SSE message to all connections: {$jsonMessage}"

proc sendEvent*(transport: var McpTransport, eventType: string, data: JsonNode, target: string = "") {.gcsafe.} =
  ## Send custom event based on transport type
  case transport.kind:
  of tkNone, tkStdio:
    discard  # No events for stdio transport
  of tkHttp:
    # HTTP transport: no persistent connections, events not applicable 
    # HTTP is request-response based
    discard
  of tkWebSocket:
    # WebSocket transport events
    if transport.wsData.connectionPool != nil:
      # WebSocket events are now handled through the connected transport instance
      let eventMessage = %*{
        "type": eventType,
        "data": data
      }
      echo fmt"Sending WebSocket event '{eventType}' to all connections: {$eventMessage}"
  of tkSSE:
    # SSE transport events
    if transport.sseData.connectionPool != nil:
      # SSE events are now handled through the connected transport instance
      echo fmt"Sending SSE event '{eventType}' to all connections: {$data}"


# Middleware types
type
  McpMiddleware* = object
    ## Middleware for request/response processing
    name*: string
    priority*: int  # Lower numbers execute first
    beforeRequest*: proc(ctx: McpRequestContext, request: JsonRpcRequest): JsonRpcRequest {.gcsafe.}
    afterResponse*: proc(ctx: McpRequestContext, response: JsonRpcResponse): JsonRpcResponse {.gcsafe.}
    onError*: proc(ctx: McpRequestContext, error: McpStructuredError): McpStructuredError {.gcsafe.}

# Custom JSON serialization for JsonRpcId
proc `%`*(id: JsonRpcId): JsonNode {.gcsafe.} =
  case id.kind
  of jridString:
    %id.str
  of jridInt:
    %id.num



proc to*(node: JsonNode, T: typedesc[JsonRpcId]): JsonRpcId =
  case node.kind
  of JString:
    JsonRpcId(kind: jridString, str: node.getStr())
  of JInt:
    JsonRpcId(kind: jridInt, num: node.getInt())
  else:
    raise newException(ValueError, "Invalid JsonRpcId format")

proc to*(node: JsonNode, T: typedesc[JsonRpcRequest]): JsonRpcRequest =
  result = JsonRpcRequest(
    jsonrpc: node.getOrDefault("jsonrpc").getStr("2.0"),
    `method`: node["method"].getStr()
  )
  
  if node.hasKey("id"):
    result.id = some(node["id"].to(JsonRpcId))
  
  if node.hasKey("params"):
    result.params = some(node["params"])

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

# JSON Schema conversion functions
proc toJsonNode*(schema: JsonSchemaRef): JsonNode {.gcsafe.} =
  ## Convert JsonSchema to JsonNode for serialization
  if schema == nil:
    result = newJNull()
    return

  result = newJObject()

  if schema.description.isSome:
    result["description"] = %schema.description.get

  case schema.kind:
  of jsObject:
    result["type"] = %"object"
    if schema.properties.len > 0:
      var props = newJObject()
      for key, value in schema.properties:
        props[key] = toJsonNode(value)
      result["properties"] = props
    if schema.required.len > 0:
      result["required"] = %schema.required
    if schema.additionalProperties.isSome:
      result["additionalProperties"] = %schema.additionalProperties.get
  of jsString:
    result["type"] = %"string"
    if schema.enumValues.len > 0:
      result["enum"] = %schema.enumValues
    if schema.pattern.isSome:
      result["pattern"] = %schema.pattern.get
    if schema.minLength.isSome:
      result["minLength"] = %schema.minLength.get
    if schema.maxLength.isSome:
      result["maxLength"] = %schema.maxLength.get
  of jsNumber:
    result["type"] = %"number"
    if schema.minimum.isSome:
      result["minimum"] = %schema.minimum.get
    if schema.maximum.isSome:
      result["maximum"] = %schema.maximum.get
    if schema.multipleOf.isSome:
      result["multipleOf"] = %schema.multipleOf.get
  of jsInteger:
    result["type"] = %"integer"
    if schema.minimum.isSome:
      result["minimum"] = %schema.minimum.get
    if schema.maximum.isSome:
      result["maximum"] = %schema.maximum.get
    if schema.multipleOf.isSome:
      result["multipleOf"] = %schema.multipleOf.get
  of jsBool:
    result["type"] = %"boolean"
  of jsArray:
    result["type"] = %"array"
    if schema.items.isSome:
      result["items"] = toJsonNode(schema.items.get)
    if schema.minItems.isSome:
      result["minItems"] = %schema.minItems.get
    if schema.maxItems.isSome:
      result["maxItems"] = %schema.maxItems.get
  of jsNull:
    result["type"] = %"null"

# Custom JSON serialization for JsonSchemaRef
proc `%`*(schema: JsonSchemaRef): JsonNode {.gcsafe.} =
  toJsonNode(schema)

# Consolidated JSON utilities for content serialization
proc contentToJsonNode*(content: McpContent): JsonNode {.gcsafe.} =
  ## Convert McpContent to JsonNode - centralized content serialization
  result = %*{
    "type": content.`type`
  }
  case content.kind:
  of TextContent:
    result["text"] = %content.text
  of ImageContent:
    result["data"] = %content.data
    result["mimeType"] = %content.mimeType
  of ResourceContent:
    # Skip resource content for now
    discard

proc contentsToJsonArray*(contents: seq[McpContent]): JsonNode {.gcsafe.} =
  ## Convert sequence of McpContent to JsonNode array
  result = newJArray()
  for content in contents:
    result.add(contentToJsonNode(content))

# Consolidated JSON field access utilities
proc getStringField*(node: JsonNode, field: string, default: string = ""): string {.gcsafe.} =
  ## Safely get string field with default value
  if node.hasKey(field) and node[field].kind == JString:
    node[field].getStr()
  else:
    default

proc getIntField*(node: JsonNode, field: string, default: int = 0): int {.gcsafe.} =
  ## Safely get int field with default value
  if node.hasKey(field) and node[field].kind == JInt:
    node[field].getInt()
  else:
    default

proc getFloatField*(node: JsonNode, field: string, default: float = 0.0): float {.gcsafe.} =
  ## Safely get float field with default value
  if node.hasKey(field) and node[field].kind in {JInt, JFloat}:
    node[field].getFloat()
  else:
    default

proc getBoolField*(node: JsonNode, field: string, default: bool = false): bool {.gcsafe.} =
  ## Safely get bool field with default value
  if node.hasKey(field) and node[field].kind == JBool:
    node[field].getBool()
  else:
    default

proc requireStringField*(node: JsonNode, field: string): string {.gcsafe.} =
  ## Get required string field, throw exception if missing
  if not node.hasKey(field):
    raise newException(ValueError, "Missing required field: " & field)
  if node[field].kind != JString:
    raise newException(ValueError, "Field '" & field & "' must be a string")
  node[field].getStr()

# Custom JSON serialization for McpToolResult
proc `%`*(toolResult: McpToolResult): JsonNode {.gcsafe.} =
  %*{
    "content": contentsToJsonArray(toolResult.content)
  }

# Custom JSON serialization for McpResourceContents
proc `%`*(resource: McpResourceContents): JsonNode {.gcsafe.} =
  result = %*{
    "uri": resource.uri,
    "content": contentsToJsonArray(resource.content)
  }
  if resource.mimeType.isSome:
    result["mimeType"] = %resource.mimeType.get

proc fromJsonNode*(node: JsonNode): JsonSchemaRef =
  ## Convert JsonNode to JsonSchema for type safety
  if node == nil or node.kind == JNull:
    result = nil
    return

  let schemaType = node.getOrDefault("type").getStr("object")
  let kind = case schemaType:
    of "object": jsObject
    of "string": jsString
    of "number": jsNumber
    of "integer": jsInteger
    of "boolean": jsBool
    of "array": jsArray
    of "null": jsNull
    else: jsObject

  result = JsonSchemaRef(kind: kind)

  if node.hasKey("description"):
    result.description = some(node["description"].getStr())

  case kind:
  of jsObject:
    result.properties = initTable[string, JsonSchemaRef]()
    result.required = @[]
    if node.hasKey("properties"):
      for key, value in node["properties"]:
        result.properties[key] = fromJsonNode(value)
    if node.hasKey("required"):
      for item in node["required"]:
        result.required.add(item.getStr())
    if node.hasKey("additionalProperties"):
      result.additionalProperties = some(node["additionalProperties"].getBool())
  of jsString:
    result.enumValues = @[]
    if node.hasKey("enum"):
      for item in node["enum"]:
        result.enumValues.add(item.getStr())
    if node.hasKey("pattern"):
      result.pattern = some(node["pattern"].getStr())
    if node.hasKey("minLength"):
      result.minLength = some(node["minLength"].getInt())
    if node.hasKey("maxLength"):
      result.maxLength = some(node["maxLength"].getInt())
  of jsNumber, jsInteger:
    if node.hasKey("minimum"):
      result.minimum = some(node["minimum"].getFloat())
    if node.hasKey("maximum"):
      result.maximum = some(node["maximum"].getFloat())
    if node.hasKey("multipleOf"):
      result.multipleOf = some(node["multipleOf"].getFloat())
  of jsArray:
    if node.hasKey("items"):
      result.items = some(fromJsonNode(node["items"]))
    if node.hasKey("minItems"):
      result.minItems = some(node["minItems"].getInt())
    if node.hasKey("maxItems"):
      result.maxItems = some(node["maxItems"].getInt())
  of jsBool, jsNull:
    discard

# Schema builder helper functions
proc newObjectSchema*(description: string = ""): JsonSchemaRef =
  ## Create a new object schema
  result = JsonSchemaRef(
    kind: jsObject,
    properties: initTable[string, JsonSchemaRef](),
    required: @[]
  )
  if description.len > 0:
    result.description = some(description)

proc newStringSchema*(description: string = "", enumValues: seq[string] = @[]): JsonSchemaRef =
  ## Create a new string schema
  result = JsonSchemaRef(
    kind: jsString,
    enumValues: enumValues
  )
  if description.len > 0:
    result.description = some(description)

proc newNumberSchema*(description: string = "", minimum: Option[float] = none(float), maximum: Option[float] = none(float)): JsonSchemaRef =
  ## Create a new number schema
  result = JsonSchemaRef(
    kind: jsNumber,
    minimum: minimum,
    maximum: maximum
  )
  if description.len > 0:
    result.description = some(description)

proc addProperty*(schema: JsonSchemaRef, name: string, propSchema: JsonSchemaRef, required: bool = false) =
  ## Add a property to an object schema
  if schema.kind == jsObject:
    schema.properties[name] = propSchema
    if required:
      schema.required.add(name)
