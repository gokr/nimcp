# NimCP - Easy Model Context Protocol (MCP) Servers in Nim

![Nim](https://img.shields.io/badge/nim-2.0+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**NimCP** is a macro-based library for creating [Model Context Protocol (MCP)](https://modelcontextprotocol.io) servers in Nim. It leverages Nim's macro system to provide an incredibly easy-to-use API for building MCP servers that integrate seamlessly with LLM applications.

**NOTE: 99.9% of this library was written using Claude Code "vibe coding"**

## Features

- **Macro-driven API** - Define servers, tools, resources, and prompts with simple, declarative syntax
- **Full MCP 2024-11-05 Support** - Complete implementation of MCP specification with JSON-RPC 2.0
- **Multiple Transports** - Supports stdio, SSE, HTTP, and WebSocket transports with authentication
- **Enhanced Type System** - Support for objects, unions, enums, optional types, and arrays
- **Automatic Schema Generation** - JSON schemas generated from Nim type signatures
- **Request Context System** - Progress tracking, cancellation, and request lifecycle management
- **Structured Error Handling** - Enhanced error types with context propagation and categorization
- **Resource URI Templates** - Dynamic URI patterns with parameter extraction (`/users/{id}`)
- **Server Composition** - Compose multiple MCP servers into a single interface with prefixes and routing for API gateways
- **Pluggable Logging** - Flexible logging system with multiple handlers, levels, and structured output
- **Middleware Pipeline** - Request/response transformation and processing hooks
- **Fluent API** - Method chaining patterns for elegant server configuration
- **High Performance** - Mummy based HTTP and WebSockets implementation and modern taskpools for stdio transport
- **Comprehensive Testing** - Full test suite covering all features and edge cases
- **Minimal Dependencies** - Uses only essential, well-maintained packages

## Quick Start

### Installation

```bash
nimble install nimcp
```

### Simple Example

```nim
import nimcp

let server = mcpServer("my-server", "1.0.0"):
  
  mcpTool:
    proc echo(text: string): string =
      ## Echo back the input text
      return "Echo: " & text
  
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      return $fmt"Result: {a + b}"

when isMainModule:
  # Use stdio transport (default):
  let transport = newStdioTransport()
  transport.serve(server)
  
  # Or use HTTP transport:
  # let transport = newMummyTransport(8080, "127.0.0.1")
  # transport.serve(server)
  
  # Or use WebSocket transport for real-time communication:
  # let transport = newWebSocketTransport(8080, "127.0.0.1")
  # transport.serve(server)
```

That's it! Your MCP server is ready to run.

## Core Concepts

### Tools

Tools are functions that LLM applications can call. Define them with the `mcpTool` macro:

```nim
mcpTool:
  proc calculate(expression: string): string =
    ## Perform mathematical calculations
    # Your calculation logic here
    return "Result: 42"
```

#### Context-Aware vs Regular Tools

NimCP supports **two types of tools**:

**Regular Tools** - Simple functions that only receive arguments:
```nim
mcpTool:
  proc add(a: float, b: float): string =
    ## Add two numbers together
    return fmt"Result: {a + b}"
```

**Context-Aware Tools** - Advanced functions that also receive server context for accessing server state and request information:
```nim
# Context aware tools need to have first parameter being an McpRequestContext
mcpTool:
  proc notifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
    ## Log request and track progress
    ctx.logMessage("info", "Processing notification request")
    ctx.reportProgress("Processing...", 0.5)
    
    # Your notification logic here
    let message = args.getOrDefault("message", %"").getStr()
    
    ctx.reportProgress("Complete!", 1.0)
    return McpToolResult(content: @[createTextContent("Notification: " & message)])
```

**When to use Context-Aware Tools:**
- Server-initiated events (SSE notifications, WebSocket broadcasts)
- Progress tracking during long operations  
- Access to server configuration or transport-specific features
- Custom logging or middleware integration

**Manual Registration Methods:**
- `server.registerTool(tool, handler)` - Regular tools
- `server.registerToolWithContext(tool, handler)` - Context-aware tools
- Same pattern applies to resources and prompts

### Resources

Resources provide data that can be read by LLM applications:

```nim
mcpResource("data://config", "Configuration", "Application configuration"):
  proc get_config(uri: string): string =
    return readFile("config.json")
```

### Prompts

Prompts are reusable templates for LLM interactions:

```nim
mcpPrompt("code_review", "Code review prompt", @[
  McpPromptArgument(name: "language", description: some("Programming language")),
  McpPromptArgument(name: "code", description: some("Code to review"))
]):
  proc review_prompt(name: string, args: Table[string, JsonNode]): seq[McpPromptMessage] =
    let language = args.getOrDefault("language", %"unknown").getStr()
    let code = args.getOrDefault("code", %"").getStr()
    
    return @[
      McpPromptMessage(
        role: System,
        content: createTextContent(&"Review this {language} code for best practices and potential issues.")
      ),
      McpPromptMessage(
        role: User,
        content: createTextContent(code)
      )
    ]
```

## Advanced Usage

### Manual Server Creation

For more control, you can create servers manually:

```nim
import nimcp

let server = newMcpServer("advanced-server", "2.0.0")

# Register tools manually
let tool = McpTool(
  name: "custom_tool",
  description: some("A custom tool"),
  inputSchema: %*{"type": "object"}
)

proc customHandler(args: JsonNode): McpToolResult =
  return McpToolResult(content: @[createTextContent("Custom result")])

server.registerTool(tool, customHandler)

# Run the server
try:
  let transport = newStdioTransport()
  transport.serve(server)
finally:
  server.shutdown()
```

### Server Composition

NimCP supports composing multiple servers into a single interface - perfect for API gateways:

```nim
import nimcp, nimcp/composed_server

# Create individual servers using macro API
let calculatorServer = mcpServer("calculator-service", "1.0.0"):
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      return fmt"Result: {a + b}"

let fileServer = mcpServer("file-service", "1.0.0"):
  mcpTool:
    proc readFile(path: string): string =
      ## Read contents of a file
      try:
        return readFile(path)
      except IOError as e:
        return fmt"Error reading file: {e.msg}"

# Compose them into a single gateway
let apiGateway = newComposedServer("api-gateway", "1.0.0")

# Mount each service with prefixes for namespacing
apiGateway.mountServerAt("/calc", calculatorServer, some("calc_"))
apiGateway.mountServerAt("/files", fileServer, some("file_"))

# Run the composed server
let transport = newStdioTransport()
transport.serve(apiGateway)

# Tools are now available as: calc_add, file_readFile
```

**Benefits of Composition**:
- 🔧 **Modular architecture** - Build focused, single-purpose servers
- 🏷️ **Namespace isolation** - Avoid tool name conflicts with prefixes  
- 🔄 **Code reuse** - Mount the same server in multiple gateways
- 🛡️ **Memory safety** - Uses composition over inheritance for better safety
- 🎯 **Simple routing** - Flat delegation model, no complex hierarchies

### Error Handling

NimCP automatically handles JSON-RPC errors, but you can throw exceptions in your handlers:

```nim
mcpTool:
  proc validate(data: string): string =
    ## Validate input data
    if data.len == 0:
      raise newException(ValueError, "Empty data parameter")
    return "Valid!"
```

## Examples

Check out the `examples/` directory for comprehensive examples:

- [`simple_server.nim`](examples/simple_server.nim) - Basic server with echo and time tools (stdio)
- [`calculator_server.nim`](examples/calculator_server.nim) - Calculator with multiple tools and resources (manual API, stdio)
- [`macro_calculator.nim`](examples/macro_calculator.nim) - Calculator using macro API with automatic introspection (stdio)
- [`macro_mummy_calculator.nim`](examples/macro_mummy_calculator.nim) - Calculator using macro API over HTTP transport
- [`mummy_calculator.nim`](examples/mummy_calculator.nim) - Calculator using manual API over HTTP transport
- [`authenticated_mummy_calculator.nim`](examples/authenticated_mummy_calculator.nim) - HTTP calculator with Bearer token authentication
- [`websocket_calculator.nim`](examples/websocket_calculator.nim) - Calculator using macro API over WebSocket transport (real-time)
- [`authenticated_websocket_calculator.nim`](examples/authenticated_websocket_calculator.nim) - WebSocket calculator with Bearer token authentication
- [`resource_templates_example.nim`](examples/resource_templates_example.nim) - Dynamic URI patterns with parameter extraction
- [`macro_composition_example.nim`](examples/macro_composition_example.nim) - Server composition and API gateway patterns
- [`logging_example.nim`](examples/logging_example.nim) - Pluggable logging system with multiple handlers
- [`fluent_api_example.nim`](examples/fluent_api_example.nim) - Method chaining and fluent API patterns
- [`enhanced_calculator.nim`](examples/enhanced_calculator.nim) - Comprehensive example showcasing all features
- [`sse_notifications_demo.nim`](examples/sse_notifications_demo.nim) - Server-initiated events and real-time notifications with context-aware tools
- [`sse_notifications_macro.nim`](examples/sse_notifications_macro.nim) - Mixed approach: macro API + manual context-aware registration  
- [`sse_notifications_full_macro.nim`](examples/sse_notifications_full_macro.nim) - Pure macro API with automatic context detection
- [`websocket_notifications_demo.nim`](examples/websocket_notifications_demo.nim) - WebSocket notifications using unified transport API

See the [examples README](examples/README.md) for detailed explanations and architecture comparisons.

Just from command line you can test and list tools with for example:
```bash
echo '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}' | ./examples/calculator_server
```

If you are using Claude Code, this is how you can add it as an MCP server:

1. Add the MCP server to Claude Code:
```bash
claude mcp add calculator_server --transport stdio $PWD/examples/calculator_server
```

2. Verify it was added:

```bash
claude mcp list
```

3. Test the server from within Claude Code:

Once added, you should be able to use the calculator tools directly in Claude Code conversations:

  - add: Add two numbers together
  - multiply: Multiply two numbers
  - power: Calculate exponentiation
  - math://constants: Access mathematical constants resource

Example usage in Claude Code:

  - "Can you add 15 and 27 for me?"
  - "What's 12 raised to the power of 3?"
  - "Show me the mathematical constants"

If the CLI method doesn't work, you can manually edit your MCP configuration file (usually at ~/.claude.json). Just **change the path** to what you have:

    {
      "mcpServers": {
        "calculator_server": {
          "type": "stdio",
          "command": "/path/to/examples/calculator_server",
          "args": [],
          "env": {}
        }
      }
    }

## Testing

Run the test suite:

```bash
nimble test
```


## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License. See [LICENSE](LICENSE) for details.

## MCP Resources

- [Model Context Protocol Specification](https://modelcontextprotocol.io)
- [MCP GitHub Repository](https://github.com/modelcontextprotocol/modelcontextprotocol)
- [MCP SDK Documentation](https://modelcontextprotocol.io/docs)