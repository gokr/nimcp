## Macro-based calculator MCP server example
## This demonstrates the high-level macro API for creating MCP servers

import ../src/nimcp
import json, math, strformat, options, asyncdispatch

# Create server using macro API
let server = newMcpServer("macro-calculator", "1.0.0")

# Add tools using direct API (simpler for now)
let addTool = McpTool(
  name: "add",
  description: some("Add two numbers"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "a": {"type": "number", "description": "First number"},
      "b": {"type": "number", "description": "Second number"}
    },
    "required": ["a", "b"]
  }
)

server.registerTool(addTool, proc(args: JsonNode): Future[McpToolResult] {.async.} =
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a + b}")])
)

let multiplyTool = McpTool(
  name: "multiply", 
  description: some("Multiply two numbers"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "a": {"type": "number", "description": "First number"},
      "b": {"type": "number", "description": "Second number"}
    },
    "required": ["a", "b"]
  }
)

server.registerTool(multiplyTool, proc(args: JsonNode): Future[McpToolResult] {.async.} =
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a * b}")])
)

let powerTool = McpTool(
  name: "power",
  description: some("Calculate a raised to the power of b"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "base": {"type": "number", "description": "Base number"},
      "exponent": {"type": "number", "description": "Exponent"}
    },
    "required": ["base", "exponent"]
  }
)

server.registerTool(powerTool, proc(args: JsonNode): Future[McpToolResult] {.async.} =
  let base = args["base"].getFloat()
  let exp = args["exponent"].getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {pow(base, exp)}")])
)

# Add a resource
let mathResource = McpResource(
  uri: "math://constants",
  name: "constants", 
  description: some("Mathematical constants")
)

server.registerResource(mathResource, proc(uri: string): Future[McpResourceContents] {.async.} =
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent("""
Math Constants:
- π (pi) ≈ 3.14159
- e (Euler's number) ≈ 2.71828
- φ (golden ratio) ≈ 1.61803
- √2 ≈ 1.41421
""")]
  )
)

# Run server
when isMainModule:
  waitFor server.runStdio()