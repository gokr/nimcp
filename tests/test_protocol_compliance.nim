## Tests for MCP protocol compliance and JSON-RPC 2.0 specification
## Ensures the server correctly implements the protocol standards

import unittest, json, options, tables, strutils
import ../src/nimcp

suite "Protocol Compliance Tests":
  
  test "JSON-RPC 2.0 response format compliance":
    let server = newMcpServer("protocol-test", "1.0.0")
    
    # Test successful response format
    let request = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 42)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {}
      })
    )
    
    let response = server.handleRequest(request)
    
    # Check JSON-RPC 2.0 compliance
    check response.jsonrpc == "2.0"
    check response.id.kind == jridInt
    check response.id.num == 42
    check response.result.isSome
    check response.error.isNone
    
    # Check result structure
    let result = response.result.get
    check result.hasKey("protocolVersion")
    check result.hasKey("serverInfo")
    check result.hasKey("capabilities")
    check result["protocolVersion"].getStr() == "2024-11-05"
  
  test "Error response format compliance":
    let server = newMcpServer("protocol-test", "1.0.0")

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

    let badRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridString, str: "test-id")),
      `method`: "nonexistent/method",
      params: some(%*{})
    )

    let response = server.handleRequest(badRequest)
    
    # Check error response format
    check response.jsonrpc == "2.0"
    check response.id.kind == jridString
    check response.id.str == "test-id"
    check response.result.isNone
    check response.error.isSome
    
    let error = response.error.get
    check error.code == MethodNotFound
    check error.message.len > 0
  
  test "MCP initialization protocol":
    let server = newMcpServer("protocol-test", "1.0.0")
    
    # Server should not be initialized initially
    check not server.initialized
    
    # Send initialize request
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": "2024-11-05",
        "capabilities": {
          "tools": {},
          "resources": {},
          "prompts": {}
        },
        "clientInfo": {
          "name": "test-client",
          "version": "1.0.0"
        }
      })
    )
    
    let response = server.handleRequest(initRequest)
    check response.error.isNone
    check server.initialized
    
    # Check response contains required fields
    let result = response.result.get
    check result.hasKey("protocolVersion")
    check result.hasKey("serverInfo")
    check result.hasKey("capabilities")
    
    let serverInfo = result["serverInfo"]
    check serverInfo["name"].getStr() == "protocol-test"
    check serverInfo["version"].getStr() == "1.0.0"
  
  test "Tools list protocol compliance":
    let server = newMcpServer("protocol-test", "1.0.0")
    
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
    
    # Register a tool
    let tool = McpTool(
      name: "test_tool",
      description: some("A test tool for protocol compliance"),
      inputSchema: %*{
        "type": "object",
        "properties": {
          "param1": {"type": "string", "description": "First parameter"}
        },
        "required": ["param1"]
      }
    )
    
    proc handler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("test result")])
    
    server.registerTool(tool, handler)
    
    # Test tools/list
    let listRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "tools/list",
      params: none(JsonNode)
    )
    
    let response = server.handleRequest(listRequest)
    check response.error.isNone
    
    let result = response.result.get
    check result.hasKey("tools")
    
    let tools = result["tools"]
    check tools.kind == JArray
    check tools.len == 1
    
    let toolData = tools[0]
    check toolData["name"].getStr() == "test_tool"
    check toolData.hasKey("description")
    check toolData.hasKey("inputSchema")
  
  test "Tool call protocol compliance":
    let server = newMcpServer("protocol-test", "1.0.0")
    
    # Initialize and register tool
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
    
    proc echoHandler(args: JsonNode): McpToolResult =
      let message = args["message"].getStr()
      return McpToolResult(content: @[createTextContent("Echo: " & message)])
    
    let echoTool = McpTool(
      name: "echo",
      description: some("Echo the input message"),
      inputSchema: %*{
        "type": "object",
        "properties": {
          "message": {"type": "string"}
        },
        "required": ["message"]
      }
    )
    
    server.registerTool(echoTool, echoHandler)
    
    # Test tool call
    let callRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "tools/call",
      params: some(%*{
        "name": "echo",
        "arguments": {
          "message": "Hello, World!"
        }
      })
    )
    
    let response = server.handleRequest(callRequest)
    check response.error.isNone
    
    let result = response.result.get
    check result.hasKey("content")
    
    let content = result["content"]
    check content.kind == JArray
    check content.len == 1
    check content[0]["type"].getStr() == "text"
    check "Echo: Hello, World!" in content[0]["text"].getStr()
  
  test "Resources protocol compliance":
    let server = newMcpServer("protocol-test", "1.0.0")
    
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
    
    discard server.handleRequest(initRequest)
    
    # Register a resource
    let resource = McpResource(
      uri: "test://resource/1",
      name: "Test Resource",
      description: some("A test resource for protocol compliance"),
      mimeType: some("text/plain")
    )
    
    proc resourceHandler(uri: string): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        mimeType: some("text/plain"),
        content: @[createTextContent("Resource content for: " & uri)]
      )
    
    server.registerResource(resource, resourceHandler)
    
    # Test resources/list
    let listRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "resources/list"
    )
    
    let listResponse = server.handleRequest(listRequest)
    check listResponse.error.isNone
    
    let listResult = listResponse.result.get
    check listResult.hasKey("resources")
    check listResult["resources"].len == 1
    
    # Test resources/read
    let readRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 3)),
      `method`: "resources/read",
      params: some(%*{
        "uri": "test://resource/1"
      })
    )
    
    let readResponse = server.handleRequest(readRequest)
    check readResponse.error.isNone
    
    let readResult = readResponse.result.get
    check readResult.hasKey("uri")
    check readResult.hasKey("content")
    check readResult["uri"].getStr() == "test://resource/1"
