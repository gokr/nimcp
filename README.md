# NimCP - Easy Model Context Protocol (MCP) Servers in Nim

![Nim](https://img.shields.io/badge/nim-2.0+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**NimCP** is a macro-based library for creating [Model Context Protocol (MCP)](https://modelcontextprotocol.io) servers in Nim. It leverages Nim's macro system to provide an incredibly easy-to-use API for building MCP servers that integrate seamlessly with LLM applications.

**NOTE: 99.9% of this library was written using Claude Code "vibe coding"**

## Features

- **Macro-driven API** - Define servers, tools, resources, and prompts with simple, declarative syntax
- **Full MCP 2024-11-05 Support** - Complete implementation of MCP specification with JSON-RPC 2.0
- **Multiple Transports** - Supports stdio, HTTP, and WebSocket transports with authentication
- **Enhanced Type System** - Support for objects, unions, enums, optional types, and arrays
- **Automatic Schema Generation** - JSON schemas generated from Nim type signatures
- **Request Context System** - Progress tracking, cancellation, and request lifecycle management
- **Structured Error Handling** - Enhanced error types with context propagation and categorization
- **Resource URI Templates** - Dynamic URI patterns with parameter extraction (`/users/{id}`)
- **Server Composition** - Mount multiple MCP servers with prefixes and routing for API gateways
- **Pluggable Logging** - Flexible logging system with multiple handlers, levels, and structured output
- **Real-time Communication** - WebSocket transport for bidirectional real-time updates and live data streaming
- **Middleware Pipeline** - Request/response transformation and processing hooks
- **Fluent UFCS API** - Method chaining patterns for elegant server configuration
- **High Performance** - Mummy based HTTP and WebSockets implementation and modern taskpools for stdio transport
- **Comprehensive Testing** - Full test suite covering all features and edge cases
- **Minimal Dependencies** - Uses only essential, well-maintained packages
- **Easy Integration** - Works with any MCP-compatible LLM application

## Quick Start

### Installation

```bash
nimble install nimcp
```

### Simple Example

```nim
import nimcp

mcpServer("my-server", "1.0.0"):
  
  mcpTool:
    proc echo(text: string): string =
      ## Echo back the input text
      return "Echo: " & text
  
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      return $fmt"Result: {a + b}"
```

Run your server with:

```nim
when isMainModule:
  runServer()  # Uses stdio transport (default)
  
  # Or specify HTTP transport:
  # runServer(HttpTransport(8080, "127.0.0.1"))
  
  # Or specify WebSocket transport for real-time communication:
  # runServer(WebSocketTransport(8080, "127.0.0.1"))
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
  server.runStdio()
finally:
  server.shutdown()
```

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
- [`server_composition_example.nim`](examples/server_composition_example.nim) - Server mounting and API gateway patterns
- [`logging_example.nim`](examples/logging_example.nim) - Pluggable logging system with multiple handlers
- [`fluent_api_example.nim`](examples/fluent_api_example.nim) - Method chaining and fluent UFCS API
- [`enhanced_calculator.nim`](examples/enhanced_calculator.nim) - Comprehensive example showcasing all features

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