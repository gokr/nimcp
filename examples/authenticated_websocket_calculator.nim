## Authenticated WebSocket calculator example
## Demonstrates WebSocket transport with Bearer token authentication

import ../src/nimcp
import ../src/nimcp/auth
import json, math, strformat

# Simple token validator for demonstration
proc validateToken(token: string): bool {.gcsafe.} =
  ## Example token validator - in production, verify against your auth system
  case token:
  of "secret123":
    echo "Valid token: secret123"
    return true
  of "admin456":
    echo "Valid token: admin456" 
    return true
  else:
    echo "Invalid token: ", token
    return false

mcpServer("authenticated-websocket-calculator", "1.0.0"):
  
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together (authenticated operation)
      ## - a: First number to add
      ## - b: Second number to add
      return fmt"Result: {a + b}"
  
  mcpTool:
    proc multiply(x: int, y: int): string =
      ## Multiply two integers (authenticated operation)
      ## - x: First integer
      ## - y: Second integer  
      return fmt"Result: {x * y}"
  
  mcpTool:
    proc power(base: float, exponent: float): string =
      ## Calculate base raised to the power of exponent (authenticated operation)
      ## - base: The base number
      ## - exponent: The exponent
      return fmt"Result: {pow(base, exponent)}"

when isMainModule:
  echo "Starting Authenticated WebSocket Calculator MCP Server..."
  echo "This server requires Bearer token authentication for WebSocket connections"
  echo ""
  echo "WebSocket endpoint: ws://127.0.0.1:8081/"
  echo "Authentication: Bearer token required in WebSocket handshake"
  echo ""
  echo "Valid tokens for testing:"
  echo "- secret123"
  echo "- admin456"
  echo ""
  echo "WebSocket connection example with authentication:"
  echo "Add 'Authorization: Bearer secret123' header to WebSocket handshake"
  echo ""
  echo "Example WebSocket client code (JavaScript):"
  echo """
const ws = new WebSocket('ws://127.0.0.1:8081/', [], {
  headers: {
    'Authorization': 'Bearer secret123'
  }
});

ws.onopen = function() {
  // Send JSON-RPC request
  ws.send(JSON.stringify({
    "jsonrpc": "2.0",
    "id": "1", 
    "method": "tools/list",
    "params": {}
  }));
};

ws.onmessage = function(event) {
  console.log('Response:', JSON.parse(event.data));
};
"""
  echo ""
  echo "Test JSON-RPC messages:"
  echo """{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}"""
  echo """{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"add","arguments":{"a":10.5,"b":7.3}}}"""
  echo """{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"power","arguments":{"base":2.0,"exponent":8.0}}}"""
  echo ""
  
  # Use WebSocket transport with authentication  
  runServer(WebSocketTransportAuth(8081, "127.0.0.1", false, validateToken))