import ../src/nimcp, ../src/nimcp/stdio_transport

let calculatorServer = mcpServer("calculator", "1.0.0"):
  
  mcpTool:
    proc add(a: int, b: int): int =
      ## Add two integers
      ## - a: First integer
      ## - b: Second integer
      return a + b

  mcpTool:
    proc subtract(a: int, b: int): int =
      ## Subtract two integers
      ## - a: First integer
      ## - b: Second integer
      return a - b

  mcpTool:
    proc multiply(a: int, b: int): int =
      ## Multiply two integers
      ## - a: First integer
      ## - b: Second integer
      return a * b

  mcpTool:
    proc divide(a: float, b: float): float =
      ## Divide two numbers
      ## - a: Dividend
      ## - b: Divisor
      if b == 0:
        raise newException(ValueError, "Division by zero")
      return a / b

when isMainModule:
  echo "Starting calculator MCP server..."
  echo "Server: ", calculatorServer.serverInfo.name, " v", calculatorServer.serverInfo.version
  echo "Available tools: add, subtract, multiply, divide"
  echo "Use Ctrl+C to stop the server"
  
  let transport = newStdioTransport()
  transport.serve(calculatorServer)