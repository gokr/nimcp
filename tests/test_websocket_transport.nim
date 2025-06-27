## Tests for WebSocket transport functionality

import unittest, json, options, tables
import ../src/nimcp/[types, protocol, server, websocket_transport, mummy_transport]

suite "WebSocket Transport Tests":
  
  test "WebSocket transport creation":
    let server = newMcpServer("test-server", "1.0.0")
    let transport = newWebSocketTransport(server, 8080, "127.0.0.1")
    
    check transport != nil
    check transport.port == 8080
    check transport.host == "127.0.0.1"
    check transport.authConfig.enabled == false
    
    transport.shutdown()
  
  test "WebSocket transport with authentication":
    let server = newMcpServer("test-server", "1.0.0")
    
    proc testValidator(token: string): bool {.gcsafe.} =
      return token == "valid-token"
    
    let authConfig = newAuthConfig(testValidator, false)
    let transport = newWebSocketTransport(server, 8081, "127.0.0.1", authConfig)
    
    check transport != nil
    check transport.authConfig.enabled == true
    check transport.authConfig.validator != nil
    check transport.authConfig.validator("valid-token") == true
    check transport.authConfig.validator("invalid-token") == false
    
    transport.shutdown()
  
  test "WebSocket transport configuration types":
    let wsConfig = WebSocketTransport(8080, "127.0.0.1")
    check wsConfig.kind == mtWebSocket
    check wsConfig.wsPort == 8080
    check wsConfig.wsHost == "127.0.0.1"
    check wsConfig.wsRequireHttps == false
    check wsConfig.wsTokenValidator == nil
    
    proc testAuth(token: string): bool {.gcsafe.} = token == "test"
    let wsAuthConfig = WebSocketTransportAuth(8081, "localhost", true, testAuth)
    check wsAuthConfig.kind == mtWebSocket
    check wsAuthConfig.wsPort == 8081
    check wsAuthConfig.wsHost == "localhost"
    check wsAuthConfig.wsRequireHttps == true
    check wsAuthConfig.wsTokenValidator != nil

  test "WebSocket transport integration with McpServer":
    let server = newMcpServer("websocket-test", "1.0.0")
    
    # Create a simple tool for testing
    let tool = McpTool(
      name: "test_tool",
      description: some("A test tool"),
      inputSchema: %*{
        "type": "object",
        "properties": {
          "message": {"type": "string"}
        },
        "required": ["message"]
      }
    )
    
    proc testHandler(args: JsonNode): McpToolResult =
      let message = args["message"].getStr()
      return McpToolResult(content: @[createTextContent("Echo: " & message)])
    
    server.registerTool(tool, testHandler)
    
    # Verify tool registration worked
    check server.tools.len == 1
    check "test_tool" in server.tools
    
    # Create transport (but don't serve - just test creation)
    let transport = newWebSocketTransport(server)
    check transport != nil
    
    transport.shutdown()

  test "WebSocket connection counting":
    let server = newMcpServer("test-server", "1.0.0")
    let transport = newWebSocketTransport(server)
    
    # Initially no connections
    check transport.getActiveConnectionCount() == 0
    
    transport.shutdown()

echo "WebSocket transport tests completed successfully!"