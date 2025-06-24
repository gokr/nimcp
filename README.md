# NimCP - Easy Model Context Protocol (MCP) Servers in Nim

![Nim](https://img.shields.io/badge/nim-2.0+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**NimCP** is a powerful, macro-based library for creating [Model Context Protocol (MCP)](https://modelcontextprotocol.io) servers in Nim. It leverages Nim's excellent macro system to provide an incredibly easy-to-use API for building MCP servers that integrate seamlessly with LLM applications.

## Features

- 🚀 **Macro-driven API** - Define servers, tools, resources, and prompts with simple, declarative syntax
- 📡 **Full MCP Support** - Complete implementation of MCP specification with JSON-RPC 2.0 over stdio
- ⚡ **Async by Default** - Built on Nim's async system for high performance
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
import json, asyncdispatch

mcpServer("my-server", "1.0.0"):
  
  # Define a simple tool
  mcpTool("echo", "Echo back the input", %*{
    "type": "object",
    "properties": {
      "text": {"type": "string", "description": "Text to echo"}
    },
    "required": ["text"]
  }):
    proc echo_handler(args: JsonNode): Future[string] {.async.} =
      return "Echo: " & args["text"].getStr()
  
  # Define a resource  
  mcpResource("info://server", "Server Info", "Server information"):
    proc info_handler(uri: string): Future[string] {.async.} =
      return "This server is built with NimCP!"
```

That's it! Your MCP server is ready to run.

## Core Concepts

### Tools

Tools are functions that LLM applications can call. Define them with the `mcpTool` macro:

```nim
mcpTool("calculate", "Perform calculations", %*{
  "type": "object",
  "properties": {
    "expression": {"type": "string", "description": "Math expression to evaluate"}
  },
  "required": ["expression"]
}):
  proc calculator(args: JsonNode): Future[string] {.async.} =
    # Your calculation logic here
    return "Result: 42"
```

### Resources

Resources provide data that can be read by LLM applications:

```nim
mcpResource("data://config", "Configuration", "Application configuration"):
  proc get_config(uri: string): Future[string] {.async.} =
    return readFile("config.json")
```

### Prompts

Prompts are reusable templates for LLM interactions:

```nim
mcpPrompt("code_review", "Code review prompt", @[
  McpPromptArgument(name: "language", description: some("Programming language")),
  McpPromptArgument(name: "code", description: some("Code to review"))
]):
  proc review_prompt(name: string, args: Table[string, JsonNode]): Future[seq[McpPromptMessage]] {.async.} =
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

proc customHandler(args: JsonNode): Future[McpToolResult] {.async.} =
  return McpToolResult(content: @[createTextContent("Custom result")])

server.registerTool(tool, customHandler)

# Run the server
waitFor server.runStdio()
```

### Error Handling

NimCP automatically handles JSON-RPC errors, but you can throw exceptions in your handlers:

```nim
mcpTool("validate", "Validate input", schema):
  proc validator(args: JsonNode): Future[string] {.async.} =
    if not args.hasKey("data"):
      raise newException(ValueError, "Missing 'data' parameter")
    return "Valid!"
```

## Examples

Check out the `examples/` directory for complete examples:

- [`simple_server.nim`](examples/simple_server.nim) - Basic server with echo and time tools
- [`calculator_server.nim`](examples/calculator_server.nim) - Calculator with multiple tools and resources

If you are using Claude Code, this is how you can try it:

1. Add the MCP server to Claude Code:

    claude mcp add calculator_server --transport stdio /home/gokr/tankfeud/mcp/examples/calculator_server_fixed

2. Verify it was added:

    claude mcp list

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

Alternative manual configuration:

If the CLI method doesn't work, you can manually edit your MCP configuration file (usually at ~/.config/claude-code/mcp.json):

    {
      "mcpServers": {
        "calculator_server": {
          "command": "/home/gokr/tankfeud/mcp/examples/calculator_server_fixed",
          "args": [],
          "transport": "stdio"
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