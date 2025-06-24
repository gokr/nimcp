## Tests for the simple_server example
## Verifies that the simple_server implements MCP protocol correctly

import unittest, json, options, times, strutils
import ../src/nimcp

suite "Simple Server Tests":
  
  test "Simple server creation and initialization":
    let server = newMcpServer("example", "1.0.0")
    check server.serverInfo.name == "example"
    check server.serverInfo.version == "1.0.0"
    check not server.initialized
    
    # Test initialization
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {"tools": {}}
      })
    )
    
    let response = server.handleRequest(initRequest)
    check response.error.isNone
    check server.initialized
  
  test "Echo tool registration and execution":
    let server = newMcpServer("example", "1.0.0")
    
    # Register echo tool (same as simple_server.nim)
    let echoTool = McpTool(
      name: "echo",
      description: some("Echo back the input text"),
      inputSchema: %*{
        "type": "object",
        "properties": {
          "text": {"type": "string", "description": "Text to echo back"}
        },
        "required": ["text"] 
      }
    )
    
    proc echoHandler(args: JsonNode): McpToolResult =
      let text = args["text"].getStr()
      return McpToolResult(content: @[createTextContent("Echo: " & text)])
    
    server.registerTool(echoTool, echoHandler)
    
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
    discard server.handleRequest(initRequest)
    
    # Test tools/list
    let listRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "tools/list",
      params: none(JsonNode)
    )
    
    let listResponse = server.handleRequest(listRequest)
    check listResponse.error.isNone
    check listResponse.result.isSome
    let tools = listResponse.result.get()["tools"].getElems()
    check tools.len >= 1
    check tools[0]["name"].getStr() == "echo"
    
    # Test tools/call
    let callRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 3)),
      `method`: "tools/call",
      params: some(%*{
        "name": "echo",
        "arguments": {"text": "Hello Test!"}
      })
    )
    
    let callResponse = server.handleRequest(callRequest)
    check callResponse.error.isNone
    check callResponse.result.isSome
    let content = callResponse.result.get()["content"].getElems()
    check content.len == 1
    check content[0]["text"].getStr() == "Echo: Hello Test!"
  
  test "Current time tool registration and execution":
    let server = newMcpServer("example", "1.0.0")
    
    # Register time tool (same as simple_server.nim)
    let timeTool = McpTool(
      name: "current_time",
      description: some("Get the current date and time"),
      inputSchema: %*{
        "type": "object",
        "properties": {}
      }
    )
    
    proc timeHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("Current time: " & $now())])
    
    server.registerTool(timeTool, timeHandler)
    
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
    discard server.handleRequest(initRequest)
    
    # Test tools/call for current_time
    let callRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "tools/call",
      params: some(%*{
        "name": "current_time",
        "arguments": {}
      })
    )
    
    let callResponse = server.handleRequest(callRequest)
    check callResponse.error.isNone
    check callResponse.result.isSome
    let content = callResponse.result.get()["content"].getElems()
    check content.len == 1
    check content[0]["text"].getStr().startsWith("Current time:")
  
  test "Server info resource registration and access":
    let server = newMcpServer("example", "1.0.0")
    
    # Register resource (same as simple_server.nim)
    let infoResource = McpResource(
      uri: "info://server",
      name: "Server Info", 
      description: some("Information about this server")
    )
    
    proc infoHandler(uri: string): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        content: @[createTextContent("This is a simple MCP server built with nimcp!")]
      )
    
    server.registerResource(infoResource, infoHandler)
    
    # Initialize server first
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {"resources": {}}
      })
    )
    discard server.handleRequest(initRequest)
    
    # Test resources/list
    let listRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "resources/list",
      params: none(JsonNode)
    )
    
    let listResponse = server.handleRequest(listRequest)
    check listResponse.error.isNone
    check listResponse.result.isSome
    let resources = listResponse.result.get()["resources"].getElems()
    check resources.len >= 1
    check resources[0]["uri"].getStr() == "info://server"
    check resources[0]["name"].getStr() == "Server Info"
    
    # Test resources/read
    let readRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 3)),
      `method`: "resources/read",
      params: some(%*{
        "uri": "info://server"
      })
    )
    
    let readResponse = server.handleRequest(readRequest)
    check readResponse.error.isNone
    check readResponse.result.isSome
    check readResponse.result.get()["uri"].getStr() == "info://server"
    let content = readResponse.result.get()["content"].getElems()
    check content.len == 1
    check content[0]["text"].getStr() == "This is a simple MCP server built with nimcp!"