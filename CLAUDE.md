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
nim c -r examples/simple_server.nim   # Compile and run simple server
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

### Two API Styles

**Macro-based API** (recommended for simplicity):
```nim
mcpServer("name", "1.0.0"):
  mcpTool("tool_name", "description", schema):
    proc handler(args: JsonNode): Future[string] {.async.} = ...
```

**Manual API** (for advanced control):
```nim
let server = newMcpServer("name", "1.0.0")
server.registerTool(tool, handler)
await server.runStdio()
```

### Key Types
- `McpServer` - Main server instance
- `McpTool` - Tool definitions with JSON schemas
- `McpResource` - Data resources accessible by URI
- `McpPrompt` - Reusable prompt templates
- `McpToolResult`, `McpResourceContents` - Response types

### Protocol Flow
All MCP servers communicate via JSON-RPC 2.0 over stdin/stdout. The server handles:
- Tool calls with JSON schema validation
- Resource access by URI
- Prompt template rendering
- Server capability negotiation

## Dependencies
- nim >= 2.0.0
- json_serialization (JSON handling)
- chronos (async runtime)
- stew (utilities)

## Examples
- `examples/simple_server.nim` - Basic echo and time tools with info resource
- `examples/calculator_server.nim` - More complex calculator with multiple tools