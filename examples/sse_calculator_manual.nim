## SSE (Server-Sent Events) calculator example using manual API
## Demonstrates manual server setup with SSE transport for MCP
## Note: SSE transport is deprecated but maintained for backwards compatibility

import ../src/nimcp
import json, math, strformat, options

proc addTool(args: JsonNode): McpToolResult =
  let a = args.getOrDefault("a").getFloat()
  let b = args.getOrDefault("b").getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a + b}")])

proc multiplyTool(args: JsonNode): McpToolResult =
  let x = args.getOrDefault("x").getInt()
  let y = args.getOrDefault("y").getInt()
  return McpToolResult(content: @[createTextContent(fmt"Result: {x * y}")])

proc compareTool(args: JsonNode): McpToolResult =
  let num1 = args.getOrDefault("num1").getFloat()
  let num2 = args.getOrDefault("num2").getFloat()
  let strict = args.getOrDefault("strict").getBool()
  
  if strict:
    if num1 == num2:
      return McpToolResult(content: @[createTextContent("Numbers are exactly equal")])
    elif num1 > num2:
      return McpToolResult(content: @[createTextContent("First number is greater")])
    else:
      return McpToolResult(content: @[createTextContent("Second number is greater")])
  else:
    let diff = abs(num1 - num2)
    if diff < 0.001:
      return McpToolResult(content: @[createTextContent("Numbers are approximately equal")])
    elif num1 > num2:
      return McpToolResult(content: @[createTextContent("First number is greater")])
    else:
      return McpToolResult(content: @[createTextContent("Second number is greater")])

proc factorialTool(args: JsonNode): McpToolResult =
  let n = args.getOrDefault("n").getInt()
  if n < 0:
    return McpToolResult(content: @[createTextContent("Error: Factorial not defined for negative numbers")])
  elif n == 0 or n == 1:
    return McpToolResult(content: @[createTextContent("Result: 1")])
  else:
    var res = 1
    for i in 2..n:
      res *= i
    return McpToolResult(content: @[createTextContent(fmt"Result: {res}")])

proc mathConstantsResource(uri: string): McpResourceContents =
  return McpResourceContents(
    uri: uri,
    content: @[createTextContent("""# Mathematical Constants

## Common Constants
- π (pi): 3.14159265359
- e (euler): 2.71828182846
- φ (golden ratio): 1.61803398875

## Basic Formulas
- Circle area: π × r²
- Circle circumference: 2 × π × r
- Sphere volume: (4/3) × π × r³

## Factorial Examples
- 0! = 1
- 5! = 120
- 10! = 3,628,800
""")]
  )

when isMainModule:
  let server = newMcpServer("sse-calculator", "1.0.0")
  
  # Register tools
  server.registerTool(McpTool(
    name: "add",
    description: some("Add two numbers together"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "a": {"type": "number", "description": "First number to add"},
        "b": {"type": "number", "description": "Second number to add"}
      },
      "required": ["a", "b"]
    }
  ), addTool)
  
  server.registerTool(McpTool(
    name: "multiply",
    description: some("Multiply two integers"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "x": {"type": "integer", "description": "First integer"},
        "y": {"type": "integer", "description": "Second integer"}
      },
      "required": ["x", "y"]
    }
  ), multiplyTool)
  
  server.registerTool(McpTool(
    name: "compare",
    description: some("Compare two numbers"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "num1": {"type": "number", "description": "First number"},
        "num2": {"type": "number", "description": "Second number"},
        "strict": {"type": "boolean", "description": "Whether to use strict comparison"}
      },
      "required": ["num1", "num2", "strict"]
    }
  ), compareTool)
  
  server.registerTool(McpTool(
    name: "factorial",
    description: some("Calculate factorial of a number"),
    inputSchema: %*{
      "type": "object",
      "properties": {
        "n": {"type": "integer", "description": "Number to calculate factorial for"}
      },
      "required": ["n"]
    }
  ), factorialTool)
  
  # Register resource
  server.registerResource(McpResource(
    uri: "math://constants",
    name: "Math Constants",
    description: some("Common mathematical constants"),
    mimeType: some("text/plain")
  ), mathConstantsResource)

  echo "Starting SSE Calculator MCP Server..."
  echo "This server uses Server-Sent Events (SSE) transport for MCP communication"
  echo ""
  echo "SSE transport provides:"
  echo "- Server-to-client: SSE event stream"  
  echo "- Client-to-server: HTTP POST requests"
  echo ""
  echo "Endpoints:"
  echo "- SSE stream: http://127.0.0.1:8080/sse"
  echo "- Messages: http://127.0.0.1:8080/messages"
  echo ""
  echo "Test the SSE connection:"
  echo "1. Open SSE stream: curl -N http://127.0.0.1:8080/sse"
  echo "2. Send message via POST:"
  echo """   curl -X POST http://127.0.0.1:8080/messages \"""
  echo """     -H "Content-Type: application/json" \"""
  echo """     -d '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}'"""
  echo ""
  echo "Available tools: add, multiply, compare, factorial"
  echo "Available resources: math-constants"
  echo ""
  echo "For Claude Code integration, use:"
  echo "- SSE endpoint: http://127.0.0.1:8080/sse"
  echo "- Message endpoint: http://127.0.0.1:8080/messages"
  echo ""
  
  # Create and start SSE transport
  let transport = newSseTransport(8080, "127.0.0.1")
  transport.serve(server)