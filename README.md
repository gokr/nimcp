# NimCP - Easy Model Context Protocol (MCP) Servers in Nim

![Nim](https://img.shields.io/badge/nim-2.0+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**NimCP** is a macro-based library for creating [Model Context Protocol (MCP)](https://modelcontextprotocol.io) servers in Nim. It leverages Nim's excellent macro system to provide an incredibly easy-to-use API for building MCP servers that integrate seamlessly with LLM applications.

**NOTE: 99.9% of this library was written using Claude Code "vibe coding"**

## Features

- 🚀 **Macro-driven API** - Define servers, tools, resources, and prompts with simple, declarative syntax
- 📡 **Full MCP Support** - Complete implementation of MCP specification with JSON-RPC 2.0
- 🌐 **Multiple Transports** - Supports both stdio and HTTP transports (via Mummy web server)
- ⚡ **High Performance** - Efficient implementation without async overhead
- 🛠️ **Type Safe** - Leverages Nim's strong type system for reliability
- 📦 **Minimal Dependencies** - Uses only essential, well-maintained packages
- 🔧 **Easy Integration** - Works with any MCP-compatible LLM application

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
server.runStdio()
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

Check out the `examples/` directory for complete examples:

- [`simple_server.nim`](examples/simple_server.nim) - Basic server with echo and time tools (stdio)
- [`calculator_server.nim`](examples/calculator_server.nim) - Calculator with multiple tools and resources (manual API, stdio)
- [`macro_calculator.nim`](examples/macro_calculator.nim) - Calculator using macro API with automatic introspection (stdio)
- [`macro_mummy_calculator.nim`](examples/macro_mummy_calculator.nim) - Calculator using macro API over HTTP transport
- [`mummy_calculator.nim`](examples/mummy_calculator.nim) - Calculator using manual API over HTTP transport

See the [examples README](examples/README.md) for detailed explanations of the differences between examples.

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