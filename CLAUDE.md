# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**NimCP** is a Nim library for creating Model Context Protocol (MCP) servers using macro-based APIs. It implements the MCP specification with JSON-RPC 2.0 over stdio, allowing integration with LLM applications.

## Development Commands

### Testing
```bash
nimble test           # Run all tests (basic, simple_server, calculator_server)
nim c -r tests/test_basic.nim           # Run basic MCP server tests
nim c -r tests/test_simple_server.nim   # Run simple_server functionality tests  
nim c -r tests/test_calculator_server.nim # Run calculator server tests
nim c -r tests/test_sse_transport.nim   # Run SSE transport tests
```

### Building Examples
```bash
nim c examples/simple_server.nim      # Compile simple server example
nim c examples/calculator_server.nim  # Compile calculator example
nim c examples/sse_calculator.nim       # Compile SSE calculator example
nim c -r examples/simple_server.nim   # Compile and run simple server
nim c -r examples/sse_calculator.nim  # Compile and run SSE server
```

### Documentation
```bash
nimble docs  # Generate HTML documentation in docs/ directory
```

### Package Management
```bash
nimble install       # Install dependencies
nimble build         # Build the package
```

## Architecture

### Core Modules Structure
- `src/nimcp.nim` - Main module that exports the public API
- `src/nimcp/types.nim` - Core MCP type definitions
- `src/nimcp/protocol.nim` - JSON-RPC protocol implementation  
- `src/nimcp/server.nim` - MCP server implementation that also includes the stdio transport
- `src/nimcp/mcpmacros.nim` - High-level macro API for easy server creation
- `src/nimcp/mummy_transport.nim` - HTTP transport implementation
- `src/nimcp/websocket_transport.nim` - WebSocket transport implementation
- `src/nimcp/sse_transport.nim` - SSE (Server-Sent Events) transport implementation

### Two API Styles

**Macro API** (automatic introspection, recommended):
```nim
mcpServer("name", "1.0.0"):
  mcpTool:
    proc add(a: float, b: float): Future[string] {.async.} =
      ## Add two numbers together
      return fmt"Result: {a + b}"
```

**Manual API** (for advanced control):
```nim
let server = newMcpServer("name", "1.0.0")
server.registerTool(tool, handler)
await server.runStdio()  # Stdio transport
```

### Key Types
- `McpServer` - Main server instance
- `McpTool` - Tool definitions with JSON schemas
- `McpResource` - Data resources accessible by URI
- `McpPrompt` - Reusable prompt templates
- `McpToolResult`, `McpResourceContents` - Response types

### Protocol Flow
MCP servers communicate via JSON-RPC 2.0 over multiple transport options:

**Stdio Transport**:
- Communication over stdin/stdout
- Suitable for CLI integration and process spawning
- Primary transport for MCP specification

**HTTP Transport**:
- JSON-RPC 2.0 over HTTP POST requests
- RESTful interface with CORS support
- Bearer token authentication support

**WebSocket Transport**:
- Real-time bidirectional communication
- Persistent connections with lower latency
- Ideal for interactive applications
- Supports Bearer token authentication during handshake

**SSE Transport** (deprecated but supported):
- Server-to-client: Server-Sent Events stream
- Client-to-server: HTTP POST requests
- CORS support for web clients
- Bearer token authentication support
- Backwards compatibility with older MCP clients

The server handles:
- Tool calls with JSON schema validation
- Resource access by URI
- Prompt template rendering
- Server capability negotiation

**Transport Examples**: 
- stdio: `examples/calculator_server.nim`
- HTTP: `examples/macro_mummy_calculator.nim` 
- WebSocket: `examples/websocket_calculator.nim`
- SSE: `examples/sse_calculator.nim`

## Dependencies
- You find all dependencies in `nimcp.nimble`

## Examples
- `examples/simple_server.nim` - Basic echo and time tools with info resource (stdio)
- `examples/calculator_server.nim` - More complex calculator with multiple tools (manual API, stdio)
- `examples/macro_calculator.nim` - Calculator using macro API with automatic introspection (stdio)
- `examples/macro_mummy_calculator.nim` - HTTP-based calculator using macro API
- `examples/websocket_calculator.nim` - WebSocket calculator with real-time communication (macro API)
- `examples/authenticated_websocket_calculator.nim` - WebSocket calculator with Bearer token authentication
- `examples/sse_calculator_manual.nim` - SSE calculator with Server-Sent Events transport (manual API)
- `examples/sse_notifications_demo.nim` - Demonstrates SSE's key advantage: server-initiated events and real-time notifications

## Macro API Features
The macro API automatically extracts:
- **Tool names** from proc names
- **Descriptions** from doc comments (first line)
- **JSON schemas** from parameter types (int, float, string, bool, seq)
- **Parameter documentation** from doc comment parameter lists
- **Type-safe wrappers** for JSON parameter conversion

## Coding Guidelines

### Variable Naming
- Do not introduce a local variable called "result" since Nim has such a variable already defined that represents the return value
- Always use doc comment with double "##" right below the signature for Nim procs, not above

### Result Variable and Return Statement Style
Follow these patterns for idiomatic Nim code:

**Single-line functions**: Use direct expression without `result =` assignment
```nim
proc getTimeout*(server: McpServer): int =
  server.requestTimeout

proc `%`*(id: JsonRpcId): JsonNode =
  case id.kind
  of jridString: %id.str
  of jridNumber: %id.num
```

**Multi-line functions with return at end**: Use `return expression` for clarity
```nim
proc handleInitialize(server: McpServer, params: JsonNode): JsonNode =
  server.initialized = true
  return createInitializeResponseJson(server.serverInfo, server.capabilities)
```

**Early exits**: Use `return value` instead of `result = value; return`
```nim
proc validateInput(value: string): bool =
  if value.len == 0:
    return false
  # ... more validation
  true
```

**Exception handlers**: Use `return expression` for error cases
```nim
proc processRequest(): McpToolResult =
  try:
    # ... processing
    McpToolResult(content: @[result])
  except ValueError:
    return McpToolResult(content: @[createTextContent("Error: Invalid input")])
```

**Avoid**: The verbose pattern of `result = value; return` for early exits

### Field Access Guidelines

**Direct Field Access**: Prefer direct field access over trivial getter/setter procedures
```nim
# Preferred: Direct field access for simple get/set operations
server.requestTimeout = 5000        # Direct assignment
let timeout = server.requestTimeout # Direct access
composed.mainServer                 # Direct access to public fields
mountPoint.server                   # Direct access to public fields

# Avoid: Trivial getter/setter procedures
proc getRequestTimeout*(server: McpServer): int = server.requestTimeout
proc setRequestTimeout*(server: McpServer, timeout: int) = server.requestTimeout = timeout
```

**When to Use Procedures**: Reserve procedures for complex operations with logic
```nim
# Appropriate: Complex logic, validation, or side effects
proc setLogLevel*(server: McpServer, level: LogLevel) =
  server.logger.setMinLevel(level)  # Calls method on nested object

proc getServerStats*(server: McpServer): Table[string, JsonNode] =
  # Complex computation combining multiple fields
  result = initTable[string, JsonNode]()
  result["serverName"] = %server.serverInfo.name
  result["toolCount"] = %server.getRegisteredToolNames().len
```

**Public Field Declaration**: Use `*` to export fields that should be directly accessible
```nim
type
  McpServer* = ref object
    serverInfo*: McpServerInfo      # Public - direct access allowed
    requestTimeout*: int            # Public - direct access allowed
    initialized*: bool              # Public - direct access allowed
    internalState: SomePrivateType  # Private - no direct access
```

### JSON Handling Style Guidelines

**JSON Object Construction**: Prefer the `%*{}` syntax for clean, readable JSON creation
```nim
# Preferred: Clean and readable
let response = %*{
  "content": contentsToJsonArray(contents),
  "isError": false
}

# Avoid: Manual construction when %*{} is sufficient
let response = newJObject()
response["content"] = contentsToJsonArray(contents)
response["isError"] = %false
```

**Field Access**: Use consolidated utility functions for consistent error handling
```nim
# Preferred: Type-safe field access with clear error messages
let toolName = requireStringField(params, "name")
let optionalArg = getStringField(params, "argument", "default")

# Avoid: Direct access without proper error handling
let toolName = params["name"].getStr()  # Can throw exceptions
```

**Content Serialization**: Use centralized utilities for consistent formatting
```nim
# Preferred: Consolidated utilities
let jsonContent = contentToJsonNode(content)
let jsonArray = contentsToJsonArray(contents)

# Avoid: Manual serialization patterns
let jsonContent = %*{
  "type": content.`type`,
  "text": content.text  # Missing proper variant handling
}
```

**Error Response Creation**: Use standardized error utilities across all transport layers
```nim
# Preferred: Consistent error responses
let errorResponse = createParseError(details = e.msg)
let invalidResponse = createInvalidRequest(id, "Missing required field")

# Avoid: Manual error construction
let errorResponse = JsonRpcResponse(
  jsonrpc: "2.0",
  id: id,
  error: some(JsonRpcError(code: -32700, message: "Parse error"))
)
```

**Field Validation**: Combine validation with field access for cleaner code
```nim
# Preferred: Validation integrated with access
proc handleToolCall(params: JsonNode): JsonNode =
  let toolName = requireStringField(params, "name")  # Validates and extracts
  let arguments = params.getOrDefault("arguments", newJObject())

# Avoid: Separate validation and access steps
proc handleToolCall(params: JsonNode): JsonNode =
  if not params.hasKey("name"):
    raise newException(ValueError, "Missing name field")
  let toolName = params["name"].getStr()
```

## Development Best Practices
- Always end todolists by running all the tests at the end to verify everything compiles and works

### Async and Concurrency Guidelines
- **DO NOT USE `asyncdispatch`** - This project explicitly avoids asyncdispatch for concurrency
- Use **`taskpools`** for concurrent processing and background tasks
- Use **synchronous I/O** with taskpools rather than async/await patterns
- For HTTP/WebSocket transports, use Mummy's built-in async capabilities but avoid introducing asyncdispatch dependencies
- All concurrent operations should be implemented using taskpools and synchronous patterns for stdio transport
- Real-time capabilities are provided via WebSocket transport using Mummy's built-in WebSocket support