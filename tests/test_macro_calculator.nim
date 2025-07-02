import unittest
import json
import tables
import options
import ../src/nimcp/mcpmacros
import ../src/nimcp/types
import ../src/nimcp/server

# Create a test server instance using the new mcpServer macro
let testCalculatorServer = mcpServer("test-calculator", "1.0.0"):
  # Test proc with doc comments (same as in macro_calculator.nim)
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers together
      ## - a: First number to add
      ## - b: Second number to add
      return "result"
  
  mcpTool:
    proc multiply(x: int, y: int): string =
      ## Multiply two integers
      ## - x: First integer
      ## - y: Second integer  
      return "result"

# Test case for add tool
test "add tool extracts doc comments correctly":
  # Get the registered tool
  let tool = testCalculatorServer.tools["add"]
  
  # Verify tool description
  check tool.description.isSome
  check tool.description.get == "Add two numbers together"
  
  # Verify parameter descriptions
  let props = tool.inputSchema["properties"]
  check props["a"].hasKey("description")
  check props["a"]["description"].getStr == "First number to add"
  check props["b"].hasKey("description")
  check props["b"]["description"].getStr == "Second number to add"
  
  # Verify parameter types
  check props["a"]["type"].getStr == "number"
  check props["b"]["type"].getStr == "number"

# Test case for multiply tool
test "multiply tool extracts doc comments correctly":
  # Get the registered tool
  let tool = testCalculatorServer.tools["multiply"]
  
  # Verify tool description
  check tool.description.isSome
  check tool.description.get == "Multiply two integers"
  
  # Verify parameter descriptions
  let props = tool.inputSchema["properties"]
  check props["x"].hasKey("description")
  check props["x"]["description"].getStr == "First integer"
  check props["y"].hasKey("description")
  check props["y"]["description"].getStr == "Second integer"
  
  # Verify parameter types
  check props["x"]["type"].getStr == "integer"
  check props["y"]["type"].getStr == "integer"
