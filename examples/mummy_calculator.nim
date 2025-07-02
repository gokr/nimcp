## Calculator server using the integrated Mummy HTTP transport
## Demonstrates how the new mummy_transport integrates with server.nim mechanisms

import ../src/nimcp
import strformat, json, options

# Create the MCP server
let server = newMcpServer("Mummy Calculator", "1.0.0")

# Define calculator tools with handlers that return McpToolResult
proc addHandler(args: JsonNode): McpToolResult =
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  let res = a + b
  return McpToolResult(content: @[
    McpContent(kind: TextContent, `type`: "text", text: fmt"Result: {res}")
  ])

proc multiplyHandler(args: JsonNode): McpToolResult =
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  let res = a * b
  return McpToolResult(content: @[
    McpContent(kind: TextContent, `type`: "text", text: fmt"Result: {res}")
  ])

proc factorialHandler(args: JsonNode): McpToolResult =
  let n = args["n"].getInt()
  if n < 0 or n > 20:
    return McpToolResult(content: @[
      McpContent(kind: TextContent, `type`: "text", text: "Error: Factorial input must be 0-20")
    ])
  
  var res = 1
  for i in 1..n:
    res *= i
  
  return McpToolResult(content: @[
    McpContent(kind: TextContent, `type`: "text", text: fmt"Factorial of {n} is {res}")
  ])

# Create tool schemas
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

let factorialTool = McpTool(
  name: "factorial",
  description: some("Calculate factorial of a number"),
  inputSchema: %*{
    "type": "object", 
    "properties": {
      "n": {"type": "integer", "description": "Number to calculate factorial for (0-20)"}
    },
    "required": ["n"]
  }
)

# Register tools with handlers
server.registerTool(addTool, addHandler)
server.registerTool(multiplyTool, multiplyHandler)
server.registerTool(factorialTool, factorialHandler)

when isMainModule:
  echo "Starting Mummy Calculator MCP Server..."
  echo "This server integrates fully with the server.nim mechanisms"
  echo ""
  echo "Test with curl:"
  echo """curl -X POST http://127.0.0.1:8080 \"""
  echo """  -H "Content-Type: application/json" \"""
  echo """  -d '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}'"""
  echo ""
  echo """curl -X POST http://127.0.0.1:8080 \"""
  echo """  -H "Content-Type: application/json" \"""
  echo """  -d '{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"add","arguments":{"a":5.5,"b":3.2}}}'"""
  echo ""
  
  # Create and serve with HTTP transport
  let transport = newMummyTransport(8080, "127.0.0.1")
  transport.serve(server)