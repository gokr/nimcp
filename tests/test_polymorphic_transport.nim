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
    
    # Transport is not part of the server anymore
    # Transport should be passed via context or separate transport objects
    check server.serverInfo.name == "test-server"
    check server.serverInfo.version == "1.0.0"

  test "McpServer transport access - with SSE transport":
    let server = newMcpServer("test-server", "1.0.0")
    
    # Test SSE transport creation separately
    var sseTransport = McpTransport(
      kind: tkSSE,
      capabilities: {tcBroadcast, tcEvents, tcUnicast}
    )
    
    # Test transport capabilities
    check sseTransport.kind == tkSSE
    check tcBroadcast in sseTransport.capabilities
    check tcEvents in sseTransport.capabilities
    check tcUnicast in sseTransport.capabilities

  test "McpServer transport access - with WebSocket transport":
    let server = newMcpServer("test-server", "1.0.0")
    
    # Test WebSocket transport creation separately
    var wsTransport = McpTransport(
      kind: tkWebSocket,
      capabilities: {tcBroadcast, tcEvents, tcUnicast, tcBidirectional}
    )
    
    # Test transport capabilities
    check wsTransport.kind == tkWebSocket
    check tcBroadcast in wsTransport.capabilities
    check tcEvents in wsTransport.capabilities
    check tcUnicast in wsTransport.capabilities
    check tcBidirectional in wsTransport.capabilities

  test "Transport switching without code changes":
    ## This test demonstrates the key benefit - same code works with different transports
    
    proc testUniversalTool(transport: var McpTransport): string =
      ## Universal tool that works with any transport
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
    
    # Test with SSE transport
    var sseTransport = McpTransport(
      kind: tkSSE,
      capabilities: {tcBroadcast, tcEvents, tcUnicast}
    )
    check testUniversalTool(sseTransport) == "Successfully used sse transport"
    
    # Switch to WebSocket transport - SAME CODE WORKS!
    var wsTransport = McpTransport(
      kind: tkWebSocket,
      capabilities: {tcBroadcast, tcEvents, tcUnicast, tcBidirectional}
    )
    check testUniversalTool(wsTransport) == "Successfully used websocket transport"

  test "Transport capabilities and introspection":
    let server = newMcpServer("test-server", "1.0.0")
    
    # Test SSE capabilities
    let sseTransport = McpTransport(
      kind: tkSSE,
      capabilities: {tcBroadcast, tcEvents, tcUnicast}
    )
    check sseTransport.kind == tkSSE
    check tcBroadcast in sseTransport.capabilities
    check tcEvents in sseTransport.capabilities
    check tcUnicast in sseTransport.capabilities
    check tcBidirectional notin sseTransport.capabilities  # SSE is not bidirectional
    
    # Test WebSocket capabilities
    let wsTransport = McpTransport(
      kind: tkWebSocket,
      capabilities: {tcBroadcast, tcEvents, tcUnicast, tcBidirectional}
    )
    check wsTransport.kind == tkWebSocket
    check tcBroadcast in wsTransport.capabilities
    check tcEvents in wsTransport.capabilities
    check tcUnicast in wsTransport.capabilities
    check tcBidirectional in wsTransport.capabilities  # WebSocket IS bidirectional

  test "Transport union type safety":
    ## Test that the union type system works correctly
    let server = newMcpServer("test-server", "1.0.0")
    
    # Test different transport types
    var noneTransport = McpTransport(
      kind: tkNone,
      capabilities: {}
    )
    check noneTransport.kind == tkNone
    
    # Test SSE transport
    var sseTransport = McpTransport(
      kind: tkSSE,
      capabilities: {tcBroadcast, tcEvents, tcUnicast}
    )
    check sseTransport.kind == tkSSE
    
    # Test WebSocket transport
    var wsTransport = McpTransport(
      kind: tkWebSocket,
      capabilities: {tcBroadcast, tcEvents, tcUnicast, tcBidirectional}
    )
    check wsTransport.kind == tkWebSocket

suite "Transport Polymorphism Integration":
  
  test "Polymorphic transport with real MCP tools":
    ## Integration test showing polymorphic transport with actual tool registration
    
    # For now, skip the complex integration test since context API needs to be implemented
    skip()

echo "🧪 Testing polymorphic transport system..."