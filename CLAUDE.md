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
```

### Building Examples
```bash
nim c examples/simple_server.nim      # Compile simple server example
nim c examples/calculator_server.nim  # Compile calculator example
nim c examples/simple_http_calculator.nim # Compile simple HTTP calculator
nim c -r examples/simple_server.nim   # Compile and run simple server
nim c -r examples/simple_http_calculator.nim # Compile and run HTTP server
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
- `src/nimcp/server.nim` - MCP server implementation
- `src/nimcp/mcpmacros.nim` - High-level macro API for easy server creation
- `src/nimcp/mummy_transport.nim` - HTTP transport implementation
- `src/nimcp/websocket_transport.nim` - WebSocket transport implementation

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

The server handles:
- Tool calls with JSON schema validation
- Resource access by URI
- Prompt template rendering
- Server capability negotiation

**Transport Examples**: 
- HTTP: `examples/macro_mummy_calculator.nim` 
- WebSocket: `examples/websocket_calculator.nim`

## Dependencies
- nim >= 2.0.0
- json_serialization (JSON handling)

## Examples
- `examples/simple_server.nim` - Basic echo and time tools with info resource (stdio)
- `examples/calculator_server.nim` - More complex calculator with multiple tools (manual API, stdio)
- `examples/macro_calculator.nim` - Calculator using macro API with automatic introspection (stdio)
- `examples/macro_mummy_calculator.nim` - HTTP-based calculator using macro API
- `examples/websocket_calculator.nim` - WebSocket calculator with real-time communication (macro API)
- `examples/authenticated_websocket_calculator.nim` - WebSocket calculator with Bearer token authentication

## Macro API Features
The macro API automatically extracts:
- **Tool names** from proc names
- **Descriptions** from doc comments (first line)
- **JSON schemas** from parameter types (int, float, string, bool, seq)
- **Parameter documentation** from doc comment parameter lists
- **Type-safe wrappers** for JSON parameter conversion

## Coding Guidelines
- **Variable Naming**:
  * Do not introduce a local variable called "result" since Nim has such a variable already defined that represents the return value
  * Always use doc comment with double "##" right below the signature for Nim procs, not above