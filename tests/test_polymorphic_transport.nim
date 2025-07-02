## Comprehensive tests for polymorphic transport system
## Tests the new transport abstraction features

import unittest
import ../src/nimcp
import ../src/nimcp/server as serverModule
import json, options, times, strformat

suite "Polymorphic Transport Tests":
  
  test "McpTransport unified interface":
    # Test the new unified transport structure
    var transport = McpTransport(
      kind: tkNone,
      capabilities: {tcBroadcast, tcEvents}
    )
    
    check transport.capabilities == {tcBroadcast, tcEvents}
    check transport.kind == tkNone
    
    # Test direct access to transport kind
    check transport.kind == tkNone

  test "McpServer transport access - no transport set":
    let server = newMcpServer("test-server", "1.0.0")
    
    # Should have no transport set
    check not server.transport.isSome
    
    # Transport kind should be tkNone
    check server.getTransportKind() == tkNone
    check not server.hasTransport()

  test "McpServer transport access - with SSE transport":
    let server = newMcpServer("test-server", "1.0.0")
    
    # Set SSE transport using new API
    server.setSseTransport(port = 9001, host = "127.0.0.1")
    
    # Should have transport set
    check server.transport.isSome
    check server.transport.get().kind == tkSSE
    check server.getTransportKind() == tkSSE
    check server.hasTransport()
    
    # Should have SSE capabilities
    let transport = server.transport.get()
    check tcBroadcast in transport.capabilities
    check tcEvents in transport.capabilities
    check tcUnicast in transport.capabilities

  test "McpServer transport access - with WebSocket transport":
    let server = newMcpServer("test-server", "1.0.0")
    
    # Set WebSocket transport using new API
    server.setWebSocketTransport(port = 9002, host = "127.0.0.1")
    
    # Should have transport set
    check server.transport.isSome
    check server.transport.get().kind == tkWebSocket
    check server.getTransportKind() == tkWebSocket
    check server.hasTransport()
    
    # Should have WebSocket capabilities (including bidirectional)
    let transport = server.transport.get()
    check tcBroadcast in transport.capabilities
    check tcEvents in transport.capabilities
    check tcUnicast in transport.capabilities
    check tcBidirectional in transport.capabilities

  test "Transport switching without code changes":
    ## This test demonstrates the key benefit - same code works with different transports
    
    proc testUniversalTool(server: McpServer): string =
      ## Universal tool that works with any transport
      if not server.transport.isSome:
        return "No transport available"
      
      var transport = server.transport.get()
      let kind = transport.kind
      
      # This same code works with ANY transport type!
      let testData = %*{
        "message": "Universal test",
        "timestamp": $now(),
        "transport": $kind
      }
      
      # These calls work with SSE, WebSocket, or any future transport
      transport.broadcastMessage(testData)
      transport.sendEvent("test_event", testData)
      
      return fmt"Successfully used {kind} transport"
    
    let server = newMcpServer("test-server", "1.0.0")
    
    # Test with no transport
    check testUniversalTool(server) == "No transport available"
    
    # Test with SSE transport
    server.setSseTransport(port = 9003)
    check testUniversalTool(server) == "Successfully used sse transport"
    
    # Switch to WebSocket transport - SAME CODE WORKS!
    server.setWebSocketTransport(port = 9004)
    check testUniversalTool(server) == "Successfully used websocket transport"

  test "Transport capabilities and introspection":
    let server = newMcpServer("test-server", "1.0.0")
    
    # Test SSE capabilities
    server.setSseTransport(port = 9005)
    
    let sseTransport = server.transport.get()
    check sseTransport.kind == tkSSE
    check tcBroadcast in sseTransport.capabilities
    check tcEvents in sseTransport.capabilities
    check tcUnicast in sseTransport.capabilities
    check tcBidirectional notin sseTransport.capabilities  # SSE is not bidirectional
    
    # Test WebSocket capabilities
    server.setWebSocketTransport(port = 9006)
    
    let wsTransport = server.transport.get()
    check wsTransport.kind == tkWebSocket
    check tcBroadcast in wsTransport.capabilities
    check tcEvents in wsTransport.capabilities
    check tcUnicast in wsTransport.capabilities
    check tcBidirectional in wsTransport.capabilities  # WebSocket IS bidirectional

  test "Transport union type safety":
    ## Test that the union type system works correctly
    let server = newMcpServer("test-server", "1.0.0")
    
    # Initially no transport
    check server.getTransportKind() == tkNone
    check not server.hasTransport()
    
    # Set SSE transport
    server.setSseTransport(port = 9008)
    
    check server.getTransportKind() == tkSSE
    check server.hasTransport()
    check server.transport.get().kind == tkSSE
    
    # Switch to WebSocket transport
    server.setWebSocketTransport(port = 9009)
    
    check server.getTransportKind() == tkWebSocket
    check server.hasTransport()
    check server.transport.get().kind == tkWebSocket
    
    # Clear transport
    server.clearTransport()
    check server.getTransportKind() == tkNone
    check not server.hasTransport()

suite "Transport Polymorphism Integration":
  
  test "Polymorphic transport with real MCP tools":
    ## Integration test showing polymorphic transport with actual tool registration
    
    # For now, skip the complex integration test since context API needs to be implemented
    skip()

echo "🧪 Testing polymorphic transport system..."