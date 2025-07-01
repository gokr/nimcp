## Enhanced calculator example demonstrating:
## - Basic macro API usage
## - Server configuration
## - Error handling in tools
## - Multiple tool types

import ../src/nimcp
import json, tables, strutils, times, math, options

# Create an enhanced MCP server
mcpServer("enhanced-calculator", "1.0.0"):
  
  # Enable context logging for debugging
  mcpServerInstance.enableContextLogging = true
  # Set request timeout to 10 seconds
  mcpServerInstance.requestTimeout = 10000
  
  # Regular arithmetic tools
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      return "Result: " & $(a + b)
  
  mcpTool:
    proc multiply(x: int, y: int): string =
      ## Multiply two integers
      return "Result: " & $(x * y)
  
  mcpTool:
    proc divide(a: float, b: float): string =
      ## Divide two numbers with proper error handling
      if b == 0.0:
        return "Error: Division by zero is not allowed"
      return "Result: " & $(a / b)
  
  # Advanced math functions
  mcpTool:
    proc power(base: float, exponent: float): string =
      ## Calculate base raised to the power of exponent
      let result = pow(base, exponent)
      return "Result: " & $result
  
  mcpTool:
    proc sqrt_tool(number: float): string =
      ## Calculate square root of a number
      if number < 0:
        return "Error: Cannot calculate square root of negative number"
      return "Result: " & $sqrt(number)
  
  mcpTool:
    proc factorial(n: int): string =
      ## Calculate factorial of a number
      if n < 0:
        return "Error: Factorial not defined for negative numbers"
      elif n == 0 or n == 1:
        return "Result: 1"
      else:
        var result = 1
        for i in 2..n:
          result *= i
        return "Result: " & $result

# Main execution
when isMainModule:
  echo "Starting Enhanced Calculator MCP Server"
  echo "Features:"
  echo "- Basic arithmetic operations"
  echo "- Advanced math functions"
  echo "- Error handling"
  echo "- Context logging enabled"
  echo "- Extended timeout (10s)"
  echo ""
  
  try:
    runServer()
  except CatchableError as e:
    echo "Server error: " & e.msg