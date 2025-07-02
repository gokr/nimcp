## HTTP calculator using macro API  
## Demonstrates automatic tool generation with HTTP transport

import ../src/nimcp
import json, math, strformat

let server = mcpServer("http-calculator", "1.0.0"):
  
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
  # HTTP transport - serves JSON-RPC over HTTP at http://127.0.0.1:8080
  # Test with: curl -X POST http://127.0.0.1:8080 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}'
  let transport = newMummyTransport(8080, "127.0.0.1")
  transport.serve(server)