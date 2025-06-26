## Tests for the modern taskpools-based MCP server implementation

import unittest, json, options, tables
import ../src/nimcp/[taskpool_server, types, protocol]

suite "Taskpool MCP Server Tests":
  
  test "Server creation and initialization":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    check server.serverInfo.name == "test-server"
    check server.serverInfo.version == "1.0.0"
    check not server.initialized
    check server.taskpool != nil
    server.shutdown()
  
  test "Tool registration and validation":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    
    let tool = McpTool(
      name: "test_tool",
      description: some("A test tool"),
      inputSchema: %*{"type": "object"}
    )
    
    proc handler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("test result")])
    
    server.registerTool(tool, handler)
    
    # Check tool was registered
    check "test_tool" in server.tools
    check "test_tool" in server.toolHandlers
    check server.capabilities.tools.isSome
    
    server.shutdown()
  
  test "Tool registration validation - empty name":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    
    let tool = McpTool(name: "", description: some("Invalid tool"))
    proc handler(args: JsonNode): McpToolResult = discard
    
    expect(ValueError):
      server.registerTool(tool, handler)
    
    server.shutdown()
  
  test "Tool registration validation - nil handler":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    
    let tool = McpTool(name: "test", description: some("Test tool"))
    
    expect(ValueError):
      server.registerTool(tool, nil)
    
    server.shutdown()
  
  test "Resource registration and validation":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    
    let resource = McpResource(
      uri: "test://resource",
      name: "Test Resource",
      description: some("A test resource")
    )
    
    proc handler(uri: string): McpResourceContents =
      return McpResourceContents(uri: uri, content: @[createTextContent("test content")])
    
    server.registerResource(resource, handler)
    
    # Check resource was registered
    check "test://resource" in server.resources
    check "test://resource" in server.resourceHandlers
    check server.capabilities.resources.isSome
    
    server.shutdown()
  
  test "Resource registration validation - empty URI":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    
    let resource = McpResource(uri: "", name: "Invalid resource")
    proc handler(uri: string): McpResourceContents = discard
    
    expect(ValueError):
      server.registerResource(resource, handler)
    
    server.shutdown()
  
  test "Prompt registration and validation":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    
    let prompt = McpPrompt(
      name: "test_prompt",
      description: some("A test prompt")
    )
    
    proc handler(name: string, args: Table[string, JsonNode]): McpGetPromptResult =
      return McpGetPromptResult(description: some("test prompt result"), messages: @[])
    
    server.registerPrompt(prompt, handler)
    
    # Check prompt was registered
    check "test_prompt" in server.prompts
    check "test_prompt" in server.promptHandlers
    check server.capabilities.prompts.isSome
    
    server.shutdown()
  
  test "Initialize request handling":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "initialize",
      params: some(%*{
        "protocolVersion": MCP_PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": "test-client", "version": "1.0.0"}
      })
    )
    
    let response = server.handleRequest(initRequest)
    check response.error.isNone
    check response.result.isSome
    check server.initialized
    
    server.shutdown()
  
  test "Tools list request":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    server.initialized = true  # Skip initialization for this test
    
    # Register a tool
    let tool = McpTool(name: "test_tool", description: some("Test"))
    proc handler(args: JsonNode): McpToolResult = discard
    server.registerTool(tool, handler)
    
    let listRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 2)),
      `method`: "tools/list"
    )
    
    let response = server.handleRequest(listRequest)
    check response.error.isNone
    check response.result.isSome
    
    let tools = response.result.get()["tools"].getElems()
    check tools.len == 1
    check tools[0]["name"].getStr() == "test_tool"
    
    server.shutdown()
  
  test "Tool call request":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    server.initialized = true
    
    # Register a tool
    let tool = McpTool(name: "echo", description: some("Echo tool"))
    proc echoHandler(args: JsonNode): McpToolResult =
      let msg = args["message"].getStr()
      return McpToolResult(content: @[createTextContent("Echo: " & msg)])
    
    server.registerTool(tool, echoHandler)
    
    let callRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 3)),
      `method`: "tools/call",
      params: some(%*{
        "name": "echo",
        "arguments": {"message": "Hello World"}
      })
    )
    
    let response = server.handleRequest(callRequest)
    check response.error.isNone
    check response.result.isSome
    
    let content = response.result.get()["content"].getElems()
    check content.len == 1
    check content[0]["text"].getStr() == "Echo: Hello World"
    
    server.shutdown()
  
  test "Error handling - uninitialized server":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    
    let request = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "tools/list"
    )
    
    let response = server.handleRequest(request)
    check response.error.isSome
    check response.error.get().code == McpServerNotInitialized
    
    server.shutdown()
  
  test "Error handling - unknown method":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    server.initialized = true
    
    let request = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: 1)),
      `method`: "unknown/method"
    )
    
    let response = server.handleRequest(request)
    check response.error.isSome
    check response.error.get().code == MethodNotFound
    
    server.shutdown()
  
  test "Notification handling":
    let server = newTaskpoolMcpServer("test-server", "1.0.0", numThreads = 2)
    
    let notification = JsonRpcRequest(
      jsonrpc: "2.0",
      `method`: "initialized"
    )
    
    # Should not raise an exception
    server.handleNotification(notification)
    
    server.shutdown()
