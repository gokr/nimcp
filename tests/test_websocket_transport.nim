## Tests for WebSocket transport functionality

import unittest, json, options, tables
import ../src/nimcp/[types, protocol, server, websocket_transport, auth]

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
    
    let authConfig = auth.newAuthConfig(testValidator, false)
    let transport = newWebSocketTransport(server, 8081, "127.0.0.1", authConfig)
    
    check transport != nil
    check transport.authConfig.enabled == true
    check transport.authConfig.validator != nil
    check transport.authConfig.validator("valid-token") == true
    check transport.authConfig.validator("invalid-token") == false
    
    transport.shutdown()
  
  test "WebSocket transport configuration types":
    let server = newMcpServer("config-test", "1.0.0")
    let transport = newWebSocketTransport(server, 8080, "127.0.0.1")
    check transport.port == 8080
    check transport.host == "127.0.0.1"
    check transport.authConfig.enabled == false
    
    proc testAuth(token: string): bool {.gcsafe.} = token == "test"
    let authConfig = auth.newAuthConfig(testAuth, true)
    let authTransport = newWebSocketTransport(server, 8081, "localhost", authConfig)
    check authTransport.port == 8081
    check authTransport.host == "localhost"
    check authTransport.authConfig.enabled == true
    check authTransport.authConfig.requireHttps == true
    check authTransport.authConfig.validator != nil
    
    transport.shutdown()
    authTransport.shutdown()

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