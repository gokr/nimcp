## Macro Server Composition Example
## Shows how to compose multiple macro-created MCP servers using the new API

import ../src/nimcp/mcpmacros
import ../src/nimcp/server
import ../src/nimcp/stdio_transport
import ../src/nimcp/composed_server
import json, math, strformat, os, std/syncio, strutils, options

# Calculator service using the macro system
let calculatorServer = mcpServer("calculator-service", "1.0.0"):
  
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      ## - a: First number to add
      ## - b: Second number to add
      return fmt"Result: {a + b}"
  
  mcpTool:
    proc multiply(x: int, y: int): string =
      ## Multiply two integers
      ## - x: First integer
      ## - y: Second integer  
      return fmt"Result: {x * y}"
  
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

# File operations service using the macro system  
let fileServer = mcpServer("file-service", "1.0.0"):
  
  mcpTool:
    proc readFile(path: string): string =
      ## Read contents of a file
      ## - path: Path to the file to read
      try:
        return syncio.readFile(path)
      except IOError as e:
        return fmt"Error reading file: {e.msg}"
  
  mcpTool:
    proc listFiles(directory: string): string =
      ## List files in a directory
      ## - directory: Directory path to list
      try:
        var resultStr = fmt"Files in {directory}:\n"
        for kind, path in walkDir(directory):
          let kindStr = $kind  # Convert enum to string
          resultStr.add(fmt"  {kindStr}: {path}\n")
        return resultStr
      except OSError as e:
        return fmt"Error listing directory: {e.msg}"

# String utilities service using the macro system
let stringServer = mcpServer("string-service", "1.0.0"):
  
  mcpTool:
    proc uppercase(text: string): string =
      ## Convert text to uppercase
      ## - text: Text to convert
      return text.toUpperAscii()
  
  mcpTool:
    proc reverse(text: string): string =
      ## Reverse a string
      ## - text: Text to reverse
      result = ""
      for i in countdown(text.len - 1, 0):
        result.add(text[i])
  
  mcpTool:
    proc wordCount(text: string): string =
      ## Count words in text
      ## - text: Text to analyze
      let words = text.split()
      return fmt"Word count: {words.len}"
  
  mcpTool:
    proc countLettersInWord(word: string, letter: string): string =
      ## Count letters in a word
      ## - word: Word to count occurrences of a letter in
      ## - letter: Letter to count in the word
      var count = 0
      for c in word:
        if c == letter[0]:
          count += 1
      return fmt"There are {count} '{letter}'s in '{word}'."
  

#  This example demonstrates:
# - Creating multiple servers using the macro system
# - Composing them into a single API gateway
# - Using prefixes for tool namespacing

# Create a composed server that mounts all the macro-created servers
var apiGateway: ComposedServer
apiGateway = newComposedServer("api-gateway", "1.0.0")

# Mount each service with different prefixes
apiGateway.mountServerAt("/calc", calculatorServer, some("calc_"))
apiGateway.mountServerAt("/files", fileServer, some("file_"))
apiGateway.mountServerAt("/string", stringServer, some("str_"))
    
# Run the composed server using proper transport integration with taskpools
# ComposedServer now inherits from McpServer, so it can be used directly
var transport = newStdioTransport()
transport.serve(apiGateway)