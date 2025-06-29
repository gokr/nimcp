## Authenticated HTTP calculator server example using Bearer token authentication
## This example demonstrates how to add token-based authentication to an MCP HTTP server

import ../src/nimcp, ../src/nimcp/auth, json, options, strformat

# Example token validator - in production, this would validate against a real auth system
proc validateToken(token: string): bool =
  # Simple example: accept specific test tokens
  case token:
    of "valid-token-123", "admin-token-456", "user-token-789":
      echo fmt"Token validation successful for: {token[0..10]}..."
      return true
    else:
      echo fmt"Token validation failed for: {token[0..min(10, token.len-1)]}..."
      return false

let server = newMcpServer("authenticated-calculator", "1.0.0")

# Register calculator tools
proc addHandler(args: JsonNode): McpToolResult =
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a + b}")])

proc multiplyHandler(args: JsonNode): McpToolResult =
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  return McpToolResult(content: @[createTextContent(fmt"Result: {a * b}")])

proc factorialHandler(args: JsonNode): McpToolResult =
  let n = args["n"].getInt()
  if n < 0 or n > 20:
    return McpToolResult(content: @[createTextContent("Error: factorial input must be between 0 and 20")])
  
  var factorial = 1
  for i in 1..n:
    factorial *= i
  return McpToolResult(content: @[createTextContent(fmt"Result: {factorial}")])

# Register tools
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
server.registerTool(addTool, addHandler)

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
server.registerTool(multiplyTool, multiplyHandler)

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
server.registerTool(factorialTool, factorialHandler)

# Create authentication configuration
let authConfig = newAuthConfig(validateToken, requireHttps = false)

echo "Starting authenticated MCP HTTP server..."
echo "Valid tokens: valid-token-123, admin-token-456, user-token-789"
echo ""
echo "Test with curl:"
echo "# Valid request with authentication:"
echo "curl -X POST http://localhost:8080 \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -H \"Authorization: Bearer valid-token-123\" \\"
echo "  -d '{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"add\",\"arguments\":{\"a\":5,\"b\":3}},\"id\":1}'"
echo ""
echo "# Request without authentication (will fail):"
echo "curl -X POST http://localhost:8080 \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"add\",\"arguments\":{\"a\":5,\"b\":3}},\"id\":1}'"
echo ""

# Start the authenticated HTTP server
server.runHttp(8080, "127.0.0.1", authConfig)