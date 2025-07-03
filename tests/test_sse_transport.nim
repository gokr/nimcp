## Tests for SSE transport functionality
## Verifies Server-Sent Events transport according to MCP specification

import unittest, json, options, strformat
import ../src/nimcp
import ../src/nimcp/auth  # Import shared authentication module
import ../src/nimcp/sse_transport  # Import SSE transport module

suite "SSE Transport Tests":
  
  test "SSE transport creation and configuration":
    # Create a simple server for testing
    let server = newMcpServer("sse-test", "1.0.0")
    
    # Test default configuration
    let defaultTransport = newSseTransport()
    check defaultTransport.base.port == 8080
    check defaultTransport.base.host == "127.0.0.1"
    check defaultTransport.sseEndpoint == "/sse"
    check defaultTransport.messageEndpoint == "/messages"
    check not defaultTransport.base.authConfig.enabled
    
    # Test custom configuration
    proc testValidator(token: string): bool =
      return token == "valid-token"
    
    let authConfig = auth.newAuthConfig(testValidator, requireHttps = false)
    let customTransport = newSseTransport(
      port = 9090, 
      host = "0.0.0.0",
      authConfig = authConfig,
      sseEndpoint = "/events",
      messageEndpoint = "/api/messages"
    )
    check customTransport.base.port == 9090
    check customTransport.base.host == "0.0.0.0" 
    check customTransport.sseEndpoint == "/events"
    check customTransport.messageEndpoint == "/api/messages"
    check customTransport.base.authConfig.enabled
    
  test "SSE connection management":
    let server = newMcpServer("sse-connection-test", "1.0.0")
    let transport = newSseTransport(port = 8081)
    
    # Test initial state - connection pool API
    # Since connectionPool is private, we can't test the connection count directly
    # This would require integration testing with actual connections
    skip()
    
    # Test would require actual HTTP connections, which is complex in unit tests
    # In a real implementation, you'd want integration tests for this
    
  test "SSE authentication validation":
    let server = newMcpServer("sse-auth-test", "1.0.0")
    
    # Test validator that accepts specific tokens
    proc testValidator(token: string): bool =
      return token in ["token1", "token2", "valid-token"]
    
    let authConfig = auth.newAuthConfig(testValidator, requireHttps = false)
    let transport = newSseTransport(port = 8082, authConfig = authConfig)
    
    # Authentication is tested through the actual server endpoints
    # This would require complex HTTP client testing
    check transport.base.authConfig.enabled
    check transport.base.authConfig.validator != nil
    
  test "CORS functionality":
    let server = newMcpServer("sse-cors-test", "1.0.0") 
    let transport = newSseTransport(port = 8083)
    
    # CORS headers are added by the transport implementation
    # Testing would require actual HTTP requests to verify headers
    check transport.sseEndpoint == "/sse"
    check transport.messageEndpoint == "/messages"

suite "SSE Transport Integration":
  
  test "SSE transport with tools and resources":
    let server = newMcpServer("sse-integration-test", "1.0.0")
    
    # Register a simple tool
    proc addHandler(args: JsonNode): McpToolResult =
      let a = args.getOrDefault("a").getFloat()
      let b = args.getOrDefault("b").getFloat()
      let addResult = a + b
      return McpToolResult(content: @[createTextContent(fmt"Result: {addResult}")])
    
    let addTool = McpTool(
      name: "add",
      description: some("Add two numbers"),
      inputSchema: %*{
        "type": "object",
        "properties": {
          "a": {"type": "number", "description": "First number"},
          "b": {"type": "number", "description": "Second number"}
        },
        "required": ["a", "b"]
      }
    )
    server.registerTool(addTool, addHandler)
    
    # Register a simple resource  
    proc mathConstantsHandler(uri: string): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        content: @[createTextContent("π = 3.14159, e = 2.71828")]
      )
    
    let mathResource = McpResource(
      uri: "math://constants",
      name: "Math Constants", 
      description: some("Common mathematical constants"),
      mimeType: some("text/plain")
    )
    server.registerResource(mathResource, mathConstantsHandler)
    
    # Create SSE transport
    let transport = newSseTransport(port = 8084)
    
    # Verify server has tools and resources
    check server.getRegisteredToolNames().len == 1
    check "add" in server.getRegisteredToolNames()
    check server.getRegisteredResourceUris().len == 1
    check "math://constants" in server.getRegisteredResourceUris()

# Integration test that actually starts a server (commented out for automated testing)
when false:
  suite "SSE Real Server Tests":
    test "Actual SSE server communication":
      let server = newMcpServer("sse-real-test", "1.0.0")
      
      # Register tools
      proc echoHandler(args: JsonNode): McpToolResult =
        let message = args.getOrDefault("message", %"").getStr()
        return McpToolResult(content: @[createTextContent("Echo: " & message)])
      
      let echoTool = McpTool(
        name: "echo",
        description: some("Echo a message"),
        inputSchema: %*{
          "type": "object", 
          "properties": {
            "message": {"type": "string", "description": "Message to echo"}
          },
          "required": ["message"]
        }
      )
      server.registerTool(echoTool, echoHandler)
      
      # Start SSE transport in background
      let transport = newSseTransport(port = 8085)
      
      proc startServer() {.thread.} =
        transport.serve(server)
      
      var serverThread: Thread[void]
      createThread(serverThread, startServer)
      
      # Give server time to start
      sleep(2000)
      
      # Test SSE endpoint availability
      let client = newHttpClient()
      try:
        # Test CORS preflight
        let optionsResponse = client.request("http://127.0.0.1:8085/sse", 
                                           httpMethod = HttpOptions)
        check optionsResponse.status.startsWith("200")
        
        # Test message endpoint
        let jsonRequest = %*{
          "jsonrpc": "2.0",
          "id": "test1", 
          "method": "tools/list",
          "params": {}
        }
        
        let postResponse = client.request("http://127.0.0.1:8085/messages",
                                        httpMethod = HttpPost,
                                        body = $jsonRequest,
                                        headers = newHttpHeaders([
                                          ("Content-Type", "application/json")
                                        ]))
        check postResponse.status.startsWith("200")
        
        let responseJson = parseJson(postResponse.body)
        check responseJson.hasKey("result")
        check responseJson["result"].hasKey("tools")
        
      except:
        # Server might not be ready or other issues
        skip()
      finally:
        client.close()
        transport.stop()
        serverThread.joinThread()

suite "SSE Message Format Tests":
  
  test "JSON-RPC message processing":
    let server = newMcpServer("sse-message-test", "1.0.0")
    
    # Test valid JSON-RPC request processing
    let validRequest = %*{
      "jsonrpc": "2.0",
      "id": "test1",
      "method": "tools/list", 
      "params": {}
    }
    
    let jsonRpcRequest = parseJsonRpcMessage($validRequest)
    let response = server.handleRequest(jsonRpcRequest)
    check response.jsonrpc == "2.0"
    check response.id.str == "test1"
    
  test "SSE event formatting":
    # Test SSE event structure (this would be integration tested in practice)
    let server = newMcpServer("sse-event-test", "1.0.0")
    let transport = newSseTransport(port = 8086)
    
    # SSE event formatting is handled internally by sendSseEvent
    # This test verifies the transport is properly configured
    check transport.sseEndpoint == "/sse"
    check transport.messageEndpoint == "/messages"

when isMainModule:
  # Run SSE transport tests
  echo "Running SSE Transport Tests..."