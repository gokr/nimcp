## Working Calculator MCP Server
## Fixed version of calculator_server.nim using manual API instead of broken macros

import ../src/nimcp
import json, asyncdispatch, math, strutils, options

let server = newMcpServer("calculator", "1.0.0")

# Register add tool
let addTool = McpTool(
  name: "add",
  description: some("Add two numbers together"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "a": {"type": "number", "description": "First number"},
      "b": {"type": "number", "description": "Second number"}
    },
    "required": ["a", "b"]
  }
)

proc addHandler(args: JsonNode): Future[McpToolResult] {.async.} =
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  return McpToolResult(content: @[createTextContent($(a + b))], isError: some(false))

server.registerTool(addTool, addHandler)

# Register multiply tool
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

proc multiplyHandler(args: JsonNode): Future[McpToolResult] {.async.} =
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  return McpToolResult(content: @[createTextContent($(a * b))], isError: some(false))

server.registerTool(multiplyTool, multiplyHandler)

# Register power tool
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

proc powerHandler(args: JsonNode): Future[McpToolResult] {.async.} =
  let base = args["base"].getFloat()
  let exponent = args["exponent"].getFloat()
  return McpToolResult(content: @[createTextContent($pow(base, exponent))], isError: some(false))

server.registerTool(powerTool, powerHandler)

# Register math constants resource
let constantsResource = McpResource(
  uri: "math://constants",
  name: "Mathematical Constants",
  description: some("Common mathematical constants")
)

proc constantsHandler(uri: string): Future[McpResourceContents] {.async.} =
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent("""Mathematical Constants:
- π (Pi): 3.14159265359
- e (Euler's number): 2.71828182846  
- φ (Golden ratio): 1.61803398875
- √2 (Square root of 2): 1.41421356237""")]
  )

server.registerResource(constantsResource, constantsHandler)

# Run the server
when isMainModule:
  waitFor server.runStdio()