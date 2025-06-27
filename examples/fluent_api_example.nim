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

# UFCS style - object.method(args)
echo "\n3. UFCS style (object.method syntax):"
let ufcsServer = newMcpServer("ufcs-server", "1.0.0")

let calcTool = McpTool(
  name: "calculate",
  description: some("Perform basic calculations"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "operation": {"type": "string", "enum": ["add", "subtract", "multiply", "divide"]},
      "a": {"type": "number"},
      "b": {"type": "number"}
    },
    "required": ["operation", "a", "b"]
  }
)

let mathResource = McpResource(
  uri: "math://constants",
  name: "Math Constants",
  description: some("Common mathematical constants")
)

proc calcHandler(args: JsonNode): McpToolResult =
  let op = args["operation"].getStr()
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  
  let calcResult = case op:
    of "add": a + b
    of "subtract": a - b
    of "multiply": a * b
    of "divide":
      if b == 0:
        return McpToolResult(content: @[createTextContent("Error: Division by zero")])
      else: a / b
    else: 0.0

  McpToolResult(content: @[createTextContent("Result: " & $calcResult)])

proc mathHandler(uri: string): McpResourceContents =
  McpResourceContents(
    uri: uri,
    content: @[createTextContent("π = 3.14159, e = 2.71828, φ = 1.61803")]
  )

# Use UFCS style - objects call methods on themselves
discard calcTool.registerWith(ufcsServer, calcHandler)
discard mathResource.registerWith(ufcsServer, mathHandler)

echo "  ✓ Registered tool and resource with UFCS style"

# Mixed approach
echo "\n4. Mixed fluent and UFCS styles:"
let mixedServer = newMcpServer("mixed-server", "1.0.0")

let statusTool = McpTool(
  name: "status",
  description: some("Get server status"),
  inputSchema: %*{"type": "object", "properties": {}}
)

let helpResource = McpResource(
  uri: "help://commands",
  name: "Help Commands",
  description: some("Available commands and their usage")
)

proc statusHandler(args: JsonNode): McpToolResult =
  McpToolResult(content: @[createTextContent("Server is running normally")])

proc helpHandler(uri: string): McpResourceContents =
  McpResourceContents(
    uri: uri,
    content: @[createTextContent("Available commands: echo, current_time, calculate, status")]
  )

# Mix both styles as needed
discard mixedServer.withTool(statusTool, statusHandler)  # Fluent style
discard helpResource.registerWith(mixedServer, helpHandler)  # UFCS style

echo "  ✓ Mixed fluent and UFCS registration styles"

# Summary
echo "\n=== Summary ==="
echo "Traditional server tools: ", traditionalServer.tools.len
echo "Fluent server tools: ", fluentServer.tools.len
echo "Fluent server resources: ", fluentServer.resources.len  
echo "Fluent server prompts: ", fluentServer.prompts.len
echo "UFCS server tools: ", ufcsServer.tools.len
echo "UFCS server resources: ", ufcsServer.resources.len
echo "Mixed server tools: ", mixedServer.tools.len
echo "Mixed server resources: ", mixedServer.resources.len

echo "\n✅ All fluent API styles work correctly!"
echo "\nBenefits of the new fluent API:"
echo "  • Method chaining for readable configuration"
echo "  • UFCS enables object.method() syntax"
echo "  • Backward compatible with existing code"
echo "  • More expressive and idiomatic Nim code"
