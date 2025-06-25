## Tests for HTTP authentication functionality
## Verifies Bearer token authentication according to MCP specification

import unittest, json, options, tables, httpclient, os, strformat
import ../src/nimcp

suite "HTTP Authentication Tests":
  
  test "AuthConfig creation and configuration":
    # Test default configuration (disabled)
    let defaultConfig = newAuthConfig()
    check not defaultConfig.enabled
    check defaultConfig.validator == nil
    check not defaultConfig.requireHttps
    check defaultConfig.customErrorResponses.len == 0
    
    # Test enabled configuration
    proc testValidator(token: string): bool =
      return token == "valid-token"
    
    let enabledConfig = newAuthConfig(testValidator, requireHttps = true)
    check enabledConfig.enabled
    check enabledConfig.validator != nil
    check enabledConfig.requireHttps
    check enabledConfig.customErrorResponses.len == 0
  
  test "Bearer token extraction":
    # This test would need access to internal functions, so we test the behavior
    # through the public API by checking authentication responses
    
    # Create a simple server for testing
    let server = newMcpServer("auth-test", "1.0.0")
    
    # Register a simple tool
    proc testHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("Test response")])
    
    let testTool = McpTool(
      name: "test_tool",
      description: some("Test tool"),
      inputSchema: %*{
        "type": "object",
        "properties": {},
        "required": []
      }
    )
    server.registerTool(testTool, testHandler)
    
    # Test validator that accepts specific tokens
    proc simpleValidator(token: string): bool =
      case token:
        of "valid-token-123", "admin-token":
          return true
        else:
          return false
    
    let authConfig = newAuthConfig(simpleValidator, requireHttps = false)
    let transport = newMummyTransport(server, 8080, "127.0.0.1", authConfig)
    
    # Note: These tests verify the configuration is properly set up
    # Actual HTTP request testing would require a running server and HTTP client
    check transport.authConfig.enabled
    check transport.authConfig.validator != nil
    check not transport.authConfig.requireHttps
    
  test "Backward compatibility - no authentication by default":
    let server = newMcpServer("compat-test", "1.0.0")
    
    # Create transport without explicit auth config (should use default)
    let transport = newMummyTransport(server, 8080, "127.0.0.1")
    
    # Default should be disabled
    check not transport.authConfig.enabled
    check transport.authConfig.validator == nil
    
    # Using the convenience function should also default to no auth
    # Note: This would normally start a server, so we just test the config creation
    let defaultAuthConfig = newAuthConfig()
    check not defaultAuthConfig.enabled

  test "HTTP Authentication Integration - Real Server":
    # Create a test server with authentication
    let server = newMcpServer("integration-test", "1.0.0")
    
    # Register a simple test tool
    proc testHandler(args: JsonNode): McpToolResult =
      return McpToolResult(content: @[createTextContent("Authenticated response")])
    
    let testTool = McpTool(
      name: "test_tool",
      description: some("Test tool for authentication"),
      inputSchema: %*{
        "type": "object",
        "properties": {},
        "required": []
      }
    )
    server.registerTool(testTool, testHandler)
    
    # Test validator
    proc testValidator(token: string): bool =
      case token:
        of "valid-token-123", "admin-token-456":
          return true
        else:
          return false
    
    let authConfig = newAuthConfig(testValidator, requireHttps = false)
    
    # Start server in a separate thread
    var serverThread: Thread[tuple[server: McpServer, port: int, host: string, auth: AuthConfig]]
    
    proc runServer(params: tuple[server: McpServer, port: int, host: string, auth: AuthConfig]) {.thread.} =
      try:
        params.server.runHttp(params.port, params.host, params.auth)
      except CatchableError:
        discard # Server shutdown expected
    
    # Use a different port to avoid conflicts
    let testPort = 8081
    let testHost = "127.0.0.1"
    
    createThread(serverThread, runServer, (server, testPort, testHost, authConfig))
    
    # Give server time to start
    sleep(500)
    
    try:
      let client = newHttpClient()
      defer: client.close()
      
      let testRequest = %*{
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
          "name": "test_tool",
          "arguments": {}
        },
        "id": 1
      }
      
      # Test 1: Valid token should succeed
      client.headers = newHttpHeaders({
        "Content-Type": "application/json",
        "Authorization": "Bearer valid-token-123"
      })
      
      let validResponse = client.postContent(
        fmt"http://{testHost}:{testPort}",
        $testRequest
      )
      
      let validJson = parseJson(validResponse)
      check validJson.hasKey("result")
      check validJson["result"]["content"][0]["text"].getStr() == "Authenticated response"
      
      # Test 2: Invalid token should fail
      client.headers = newHttpHeaders({
        "Content-Type": "application/json",
        "Authorization": "Bearer invalid-token"
      })
      
      expect(HttpRequestError):
        discard client.postContent(
          fmt"http://{testHost}:{testPort}",
          $testRequest
        )
      
      # Test 3: Missing token should fail
      client.headers = newHttpHeaders({
        "Content-Type": "application/json"
      })
      
      expect(HttpRequestError):
        discard client.postContent(
          fmt"http://{testHost}:{testPort}",
          $testRequest
        )
      
      # Test 4: Another valid token should succeed
      client.headers = newHttpHeaders({
        "Content-Type": "application/json",
        "Authorization": "Bearer admin-token-456"
      })
      
      let adminResponse = client.postContent(
        fmt"http://{testHost}:{testPort}",
        $testRequest
      )
      
      let adminJson = parseJson(adminResponse)
      check adminJson.hasKey("result")
      check adminJson["result"]["content"][0]["text"].getStr() == "Authenticated response"
      
    finally:
      # Cleanup: terminate the server thread
      # Note: In a real scenario, you'd want a more graceful shutdown
      # For testing purposes, we rely on the test process ending
      discard
