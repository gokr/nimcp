import unittest
import json
import tables
import options
import ../src/nimcp/mcpmacros
import ../src/nimcp/types
import ../src/nimcp/server

# Create a test server instance using the new mcpServer macro
let testServer = mcpServer("test-server", "1.0.0"):
  # Test proc with doc comments
  mcpTool:
    proc testTool(param1: int, param2: string): string =
      ## Test tool description
      ## - param1: First parameter description
      ## - param2: Second parameter description
      return "result"

# Test case for doc comment extraction
test "mcpTool macro extracts doc comments correctly":
  # Get the registered tool
  let tool = testServer.tools["testTool"]
  
  # Verify tool description
  check tool.description.isSome
  check tool.description.get == "Test tool description"
  
  # Verify parameter descriptions
  let props = tool.inputSchema["properties"]
  check props["param1"].hasKey("description")
  check props["param1"]["description"].getStr == "First parameter description"
  check props["param2"].hasKey("description")
  check props["param2"]["description"].getStr == "Second parameter description"
  
  # Verify parameter types
  check props["param1"]["type"].getStr == "integer"
  check props["param2"]["type"].getStr == "string"

# Test case for tool registration
test "mcpTool macro registers tools correctly":
  check "testTool" in testServer.tools
  let tool = testServer.tools["testTool"]
  check tool.name == "testTool"
  check tool.description.get == "Test tool description"
