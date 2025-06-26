## Comprehensive error handling tests for nimcp
## Tests various error conditions and edge cases

import unittest, json, options, tables, strutils
import ../src/nimcp

suite "Error Handling Tests":
  
  test "Invalid JSON-RPC requests":
    let server = newMcpServer("error-test", "1.0.0")
    
    # Test malformed JSON
    try:
      let badRequest = parseJsonRpcMessage("{invalid json}")
      fail()  # Should not reach here
    except:
      check true  # Expected to fail

    # Test missing required fields
    try:
      let noMethod = parseJsonRpcMessage("""{"jsonrpc": "2.0", "id": 1}""")
      fail()  # Should not reach here
    except:
      check true  # Expected to fail
  
  test "Tool registration edge cases":
    let server = newMcpServer("error-test", "1.0.0")
    
    # Test duplicate tool registration
    let tool1 = McpTool(
      name: "duplicate_tool",
      description: some("First tool"),
      inputSchema: %*{"type": "object"}
    )
    
    let tool2 = McpTool(
      name: "duplicate_tool", 
      description: some("Second tool"),
      inputSchema: %*{"type": "object"}
    )
    
    proc handler1(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("handler1")])
    
    proc handler2(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("handler2")])
    
    server.registerTool(tool1, handler1)
    server.registerTool(tool2, handler2)  # Should overwrite first
    
    check server.tools.hasKey("duplicate_tool")
    check server.tools.len == 1
  
  test "Tool execution with invalid arguments":
    let server = newMcpServer("error-test", "1.0.0")
    
    # Initialize server first
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {"tools": {}}
      })
    )
    
    let initResponse = server.handleRequest(initRequest)
    check initResponse.error.isNone
    
    # Register a tool that expects specific arguments
    proc strictHandler(args: JsonNode): McpToolResult =
      if not args.hasKey("required_param"):
        raise newException(ValueError, "Missing required_param")
      return McpToolResult(content: @[createTextContent("success")])
    
    let strictTool = McpTool(
      name: "strict_tool",
      description: some("Tool with strict requirements"),
      inputSchema: %*{
        "type": "object",
        "properties": {
          "required_param": {"type": "string"}
        },
        "required": ["required_param"]
      }
    )
    
    server.registerTool(strictTool, strictHandler)
    
    # Test call without required parameter
    let badCallRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "tools/call",
      params: some(%*{
        "name": "strict_tool",
        "arguments": {}  # Missing required_param
      })
    )
    
    let badResponse = server.handleRequest(badCallRequest)
    check badResponse.error.isSome
    check badResponse.error.get.code == InvalidParams
  
  test "Resource access errors":
    let server = newMcpServer("error-test", "1.0.0")
    
    # Initialize server
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {"resources": {}}
      })
    )
    
    let initResponse = server.handleRequest(initRequest)
    check initResponse.error.isNone
    
    # Test accessing non-existent resource
    let badResourceRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "resources/read",
      params: some(%*{
        "uri": "nonexistent://resource"
      })
    )
    
    let badResponse = server.handleRequest(badResourceRequest)
    check badResponse.error.isSome
    check badResponse.error.get.code == InvalidParams
    check "not found" in badResponse.error.get.message.toLowerAscii()
  
  test "Prompt execution errors":
    let server = newMcpServer("error-test", "1.0.0")
    
    # Initialize server
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {"prompts": {}}
      })
    )
    
    let initResponse = server.handleRequest(initRequest)
    check initResponse.error.isNone
    
    # Test accessing non-existent prompt
    let badPromptRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "prompts/get",
      params: some(%*{
        "name": "nonexistent_prompt",
        "arguments": {}
      })
    )
    
    let badResponse = server.handleRequest(badPromptRequest)
    check badResponse.error.isSome
    check badResponse.error.get.code == InvalidParams
  
  test "Unknown method handling":
    let server = newMcpServer("error-test", "1.0.0")

    # Initialize server first
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {}
      })
    )
    discard server.handleRequest(initRequest)

    let unknownRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "unknown/method",
      params: some(%*{})
    )

    let response = server.handleRequest(unknownRequest)
    check response.error.isSome
    check response.error.get.code == MethodNotFound
    check "method not found" in response.error.get.message.toLowerAscii()
  
  test "Notification handling (no response expected)":
    let server = newMcpServer("error-test", "1.0.0")
    
    # Test initialized notification
    let notification = JsonRpcRequest(
      jsonrpc: "2.0",
      `method`: "initialized"
      # No id field = notification
    )
    
    let response = server.handleRequest(notification)
    # Should return empty response for notifications
    check response.id.kind == jridString
    check response.id.str == ""
