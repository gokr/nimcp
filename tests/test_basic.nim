## Basic tests for nimcp

import unittest, json, options, tables
import ../src/nimcp

suite "Basic MCP Server Tests":
  
  test "Create server":
    let server = newMcpServer("test", "1.0.0")
    check server.serverInfo.name == "test"
    check server.serverInfo.version == "1.0.0"
    check not server.initialized
  
  test "Tool registration":
    let server = newMcpServer("test", "1.0.0")
    
    let tool = McpTool(
      name: "test_tool",
      description: some("A test tool"),
      inputSchema: %*{"type": "object"}
    )
    
    proc testHandler(args: JsonNode): McpToolResult =
      return McpToolResult(
        content: @[createTextContent("test result")]
      )
    
    server.registerTool(tool, testHandler)
    check server.tools.hasKey("test_tool")
    check server.capabilities.tools.isSome