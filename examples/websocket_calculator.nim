## Macro-based WebSocket calculator example
## Demonstrates automatic tool generation with WebSocket transport for real-time communication

import ../src/nimcp
import json, math, strformat

mcpServer("websocket-calculator", "1.0.0"):
  
  # This proc will be automatically converted to an MCP tool
  # Tool name: "add", schema generated from parameters, description from doc comment
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      ## - a: First number to add
      ## - b: Second number to add
      return fmt"Result: {a + b}"
  
  # Another tool with different parameter types
  mcpTool:
    proc multiply(x: int, y: int): string =
      ## Multiply two integers
      ## - x: First integer
      ## - y: Second integer  
      return fmt"Result: {x * y}"
  
  # Tool with boolean parameter
  mcpTool:
    proc compare(num1: float, num2: float, strict: bool): string =
      ## Compare two numbers
      ## - num1: First number
      ## - num2: Second number
      ## - strict: Whether to use strict comparison
      if strict:
        if num1 == num2:
          return "Numbers are exactly equal"
        elif num1 > num2:
          return "First number is greater"
        else:
          return "Second number is greater"
      else:
        let diff = abs(num1 - num2)
        if diff < 0.001:
          return "Numbers are approximately equal"
        elif num1 > num2:
          return "First number is greater"
        else:
          return "Second number is greater"
  
  # Tool with int parameter
  mcpTool:
    proc factorial(n: int): string =
      ## Calculate factorial of a number
      ## - n: Number to calculate factorial for
      if n < 0:
        return "Error: Factorial not defined for negative numbers"
      elif n == 0 or n == 1:
        return "Result: 1"
      else:
        var res = 1
        for i in 2..n:
          res *= i
        return fmt"Result: {res}"

when isMainModule:
  echo "Starting WebSocket Calculator MCP Server..."
  echo "This server uses macros for automatic tool generation and WebSocket transport for real-time communication"
  echo ""
  echo "WebSocket endpoint: ws://127.0.0.1:8080/"
  echo "HTTP info endpoint: http://127.0.0.1:8080/ (GET request for server info)"
  echo ""
  echo "Test with WebSocket client or use the following curl commands for HTTP fallback:"
  echo """curl -X GET http://127.0.0.1:8080 # Get server info"""
  echo ""
  echo "WebSocket JSON-RPC examples:"
  echo """{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}"""
  echo """{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"add","arguments":{"a":5.5,"b":3.2}}}"""
  echo """{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"factorial","arguments":{"n":5}}}"""
  echo """{"jsonrpc":"2.0","id":"4","method":"tools/call","params":{"name":"compare","arguments":{"num1":3.14159,"num2":3.14160,"strict":false}}}"""
  echo ""
  echo "Features:"
  echo "- Real-time bidirectional communication"
  echo "- Persistent connections"
  echo "- Lower latency than HTTP polling"
  echo "- JSON-RPC 2.0 over WebSocket"
  echo ""
  
  # Use the unified transport API with WebSocket configuration  
  runServer(WebSocketTransport(8080, "127.0.0.1"))