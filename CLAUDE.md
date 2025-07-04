# CLAUDE.md

**NimCP** - Nim library for MCP servers using macro-based APIs. Implements JSON-RPC 2.0 over stdio/websockets/SSE for LLM integration.

## Commands
```bash
nimble test          # Run all tests
nim r tests/test_*.nim  # Run specific test
nim c examples/      # Build examples  
nimble docs         # Generate docs
nim c -r examples/basic_calculator.nim  # Compile and run example
```

## Architecture

Core: `types.nim` (MCP types), `server.nim` (server separete from transports), `mcpmacros.nim` (macro API), `protocol.nim` (JSON-RPC)

**Macro API** (recommended) can be seen in @`examples/macro_calculator.nim`
The macro API automatically extracts:
- **Tool names** from proc names
- **Descriptions** from doc comments (first line)
- **JSON schemas** from parameter types (int, float, string, bool, seq)
- **Parameter documentation** from doc comment parameter lists
- **Type-safe wrappers** for JSON parameter conversion

Key types: `McpServer`, `McpTool`, `McpResource`, `McpPrompt`, `McpRequestContext`

**Transports**: Stdio (CLI), HTTP (REST), WebSocket (realtime), SSE (deprecated)
**Examples**: See `examples/` - calculator variants for each transport
**Dependencies**: `nim >= 2.2.4`, `mummy`, `taskpools`


## Coding Guidelines
- Do not shadow the local `result` variable (Nim built-in)
- Doc comments: `##` below proc signature
- Prefer generics or object variants over methods
- Use `return expression` for early exits
- Prefer direct field access over getters/setters
- JSON: Use `%*{}` syntax
- **NO `asyncdispatch`** - use `taskpools` for concurrency
- Remove old code during refactoring
- Import full modules, not select symbols
- Use `*` to export fields that should be publicly accessible
- If something is not exported, export it instead of doing workarounds
- Do not be afraid to break backwards compatibility
- Do not add comments talking about how good something is, it is just noise. Be brief.
- Do not add comments that reflect what has changed, we use git for change tracking, only describe current code
- Do not add unnecessary commentary or explain code that is self-explanatory
- **Single-line functions**: Use direct expression without `result =` assignment or `return` statement
- **Multi-line functions**: Use `result =` assignment and `return` statement for clarity
- **Early exits**: Use `return value` instead of `result = value; return`
- **Exception handlers**: Use `return expression` for error cases
- **JSON Object Construction**: Prefer the `%*{}` syntax for clean, readable JSON creation
- **Content Serialization**: Use centralized utilities for consistent formatting
- **Error Response Creation**: Use standardized error utilities across all transport layers
- **Field Validation**: Combine validation with field access for cleaner code
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

### Refactoring and Code Cleanup
- **Remove old unused code during refactoring** - We prioritize clean, maintainable code over backwards compatibility
- When implementing new architecture patterns, completely remove the old implementation patterns
- Delete deprecated methods, unused types, and obsolete code paths immediately
- Keep the codebase lean and focused on the current architectural approach

### Async and Concurrency Guidelines
- **DO NOT USE `asyncdispatch`** - This project explicitly avoids asyncdispatch for concurrency
- Use **`taskpools`** for concurrent processing and background tasks
- Use **synchronous I/O** with taskpools rather than async/await patterns
- For HTTP/WebSocket transports, use Mummy's built-in async capabilities but avoid introducing asyncdispatch dependencies
- All concurrent operations should be implemented using taskpools and synchronous patterns for stdio transport
- Real-time capabilities are provided via WebSocket transport using Mummy's built-in WebSocket support