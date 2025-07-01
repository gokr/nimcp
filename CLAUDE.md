# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**NimCP** is a Nim library for creating Model Context Protocol (MCP) servers using macro-based APIs. It implements the MCP specification with JSON-RPC 2.0 over stdio, websockets and SSE, allowing integration with LLM applications.

## Development Commands

### Run all tests
```bash
nimble test
```

### Building Examples
```bash
nim c examples/simple_server.nim      # Compile simple server example
nim c -r examples/sse_calculator.nim  # Compile and run SSE server
```

### Documentation
```bash
nimble docs
```

### Package Management
```bash
nimble install       # Install dependencies
nimble build         # Build the package
```

## Architecture

### Core Modules Structure
- `src/nimcp.nim` - Main module that exports the public API
- `src/nimcp/types.nim` - Core MCP type definitions and polymorphic transport interface
- `src/nimcp/protocol.nim` - JSON-RPC protocol implementation  
- `src/nimcp/server.nim` - MCP server implementation with stdio transport and polymorphic transport support
- `src/nimcp/mcpmacros.nim` - High-level macro API for easy server creation
- `src/nimcp/context.nim` - Request context system for context-aware tools
- `src/nimcp/schema.nim` - JSON schema utilities and validation
- `src/nimcp/auth.nim` - Authentication and authorization framework
- `src/nimcp/cors.nim` - CORS handling utilities
- `src/nimcp/connection_pool.nim` - Connection management for transport layers
- `src/nimcp/logging.nim` - Logging utilities and configuration
- `src/nimcp/resource_templates.nim` - Resource template system
- `src/nimcp/mummy_transport.nim` - HTTP transport implementation
- `src/nimcp/websocket_transport.nim` - WebSocket transport with polymorphic interface
- `src/nimcp/sse_transport.nim` - SSE transport with polymorphic interface (deprecated but supported)

### Two API Styles

**Macro API** (automatic introspection, recommended):
```nim
mcpServer("name", "1.0.0"):
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      return fmt"Result: {a + b}"
```

**Manual API** (for advanced control):
```nim
let server = newMcpServer("name", "1.0.0")
server.registerTool(tool, handler)
server.runStdio()  # Stdio transport (synchronous)

# Or with other transports:
let sseTransport = newSseTransport(server, port = 8080)
server.setTransport(sseTransport)
sseTransport.start()
```

### Key Types
- `McpServer` - Main server instance with polymorphic transport support
- `McpTool` - Tool definitions with JSON schemas
- `McpResource` - Data resources accessible by URI
- `McpPrompt` - Reusable prompt templates
- `McpToolResult`, `McpResourceContents` - Response types
- `McpRequestContext` - Request context for context-aware tools
- `TransportInterface` - Base interface for polymorphic transport abstraction
- `TransportKind` - Enum defining transport types (stdio, SSE, WebSocket, HTTP)
- `McpTransport` - Union type for type-safe transport storage
- `McpTransportCapabilities` - Set of transport capabilities (broadcast, events, etc.)
- `AuthConfig` - Authentication configuration for HTTP/WebSocket/SSE transports
- `ConnectionPool` - Generic connection management for transport layers

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
- Stdio: `examples/calculator_server.nim`, `examples/macro_calculator.nim`
- HTTP: `examples/macro_mummy_calculator.nim`, `examples/mummy_calculator.nim`
- WebSocket: `examples/websocket_calculator.nim`, `examples/authenticated_websocket_calculator.nim`
- SSE: `examples/sse_calculator_manual.nim`, `examples/sse_notifications_demo.nim`
- Polymorphic: `examples/polymorphic_transport_demo.nim`
- Enhanced: `examples/enhanced_calculator.nim`, `examples/logging_example.nim`

## Dependencies
- You find all dependencies in `nimcp.nimble`
- Core dependencies: `nim >= 2.2.4`, `mummy` (HTTP/WebSocket server), `taskpools` (concurrency)

## Polymorphic Transport System

NimCP provides a powerful polymorphic transport abstraction that allows tools to work with any transport without specifying the transport type:

```nim
# Tools can access any transport polymorphically
proc universalTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
  let server = ctx.getServer()
  let transport = server.getTransport()  # No type specification needed!
  
  if transport != nil:
    # These calls work with SSE, WebSocket, or any future transport
    transport.broadcastMessage(%*{"message": "Hello world"})
    transport.sendEvent("notification", %*{"data": "test"})
  
  return McpToolResult(content: @[createTextContent("Success")])
```

**Transport Capabilities**:
- `tcBroadcast` - Can broadcast messages to all connected clients
- `tcEvents` - Can send custom events
- `tcUnicast` - Can send messages to specific clients
- `tcBidirectional` - Supports bidirectional communication

**Polymorphic API**:
- `server.getTransport(): TransportInterface` - Get transport without type specification
- `transport.broadcastMessage(jsonData)` - Broadcast to all clients
- `transport.sendEvent(eventType, data, target)` - Send custom events
- `transport.getTransportKind(): TransportKind` - Get transport type for introspection

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


**Public Field Declaration**: Use `*` to export fields that should be publicly accessible
```nim
type
  McpServer* = ref object
    serverInfo*: McpServerInfo      # Public
    requestTimeout*: int            # Public
    initialized*: bool              # Public
    internalState: SomePrivateType  # Private
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

## Testing

### Running Tests
```bash
nimble test           # Run all tests
```

### Test Structure
- 15 comprehensive test suites covering all modules
- Tests include: basic functionality, macro system, transport layers, authentication, error handling, edge cases, and polymorphic transport system

## Context-Aware Tools

NimCP supports both regular tools and context-aware tools:

**Regular Tools** (simple functions):
```nim
mcpTool:
  proc add(a: float, b: float): string =
    return fmt"Result: {a + b}"
```

**Context-Aware Tools** (access to server and transport):
```nim
mcpTool:
  proc notifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
    let server = ctx.getServer()
    let transport = server.getTransport()
    # ... use transport for notifications
    return McpToolResult(content: @[createTextContent("Sent")])
```

## Development Best Practices
- Always end todolists by running all the tests at the end to verify everything compiles and works
- Use the polymorphic transport system for transport-agnostic tools
- Prefer context-aware tools when you need access to the server or transport layer
- Follow the macro API patterns for automatic schema generation

### Async and Concurrency Guidelines
- **DO NOT USE `asyncdispatch`** - This project explicitly avoids asyncdispatch for concurrency
- Use **`taskpools`** for concurrent processing and background tasks
- Use **synchronous I/O** with taskpools rather than async/await patterns
- For HTTP/WebSocket transports, use Mummy's built-in async capabilities but avoid introducing asyncdispatch dependencies
- All concurrent operations should be implemented using taskpools and synchronous patterns for stdio transport
- Real-time capabilities are provided via WebSocket transport using Mummy's built-in WebSocket support