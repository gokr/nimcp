## Fluent API Example - Demonstrating UFCS for more readable server configuration

import ../src/nimcp
import json, times, options, tables

echo "=== Fluent API Example ==="

# Traditional approach (still works)
echo "\n1. Traditional API:"
let traditionalServer = newMcpServer("traditional-server", "1.0.0")

let echoTool = McpTool(
  name: "echo",
  description: some("Echo back the input text"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "text": {"type": "string", "description": "Text to echo back"}
    },
    "required": ["text"] 
  }
)

proc echoHandler(args: JsonNode): McpToolResult =
  let text = args["text"].getStr()
  McpToolResult(content: @[createTextContent("Echo: " & text)])

traditionalServer.registerTool(echoTool, echoHandler)
echo "  ✓ Registered echo tool traditionally"

# New fluent API approach - Method chaining
echo "\n2. Fluent API with method chaining:"
let fluentServer = newMcpServer("fluent-server", "1.0.0")

let timeTool = McpTool(
  name: "current_time",
  description: some("Get the current date and time"),
  inputSchema: %*{
    "type": "object",
    "properties": {}
  }
)

let infoResource = McpResource(
  uri: "info://server",
  name: "Server Info", 
  description: some("Information about this server")
)

let greetPrompt = McpPrompt(
  name: "greeting",
  description: some("Generate a greeting message"),
  arguments: @[
    McpPromptArgument(name: "name", description: some("Name to greet"), required: some(true))
  ]
)

proc timeHandler(args: JsonNode): McpToolResult =
  McpToolResult(content: @[createTextContent("Current time: " & $now())])

proc infoHandler(uri: string): McpResourceContents =
  McpResourceContents(
    uri: uri,
    content: @[createTextContent("This is a fluent MCP server built with nimcp!")]
  )

proc greetHandler(name: string, args: Table[string, JsonNode]): McpGetPromptResult =
  let userName = args.getOrDefault("name", %"World").getStr()
  McpGetPromptResult(
    messages: @[McpPromptMessage(
      role: User,
      content: createTextContent("Hello, " & userName & "! Welcome to the fluent API.")
    )]
  )

# Chain multiple registrations in a fluent style
discard fluentServer
  .withTool(timeTool, timeHandler)
  .withResource(infoResource, infoHandler)
  .withPrompt(greetPrompt, greetHandler)

echo "  ✓ Registered tool, resource, and prompt with fluent chaining"