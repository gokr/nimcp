## Comprehensive tests for polymorphic transport system
## Tests the new transport abstraction features

import unittest
import ../src/nimcp
import ../src/nimcp/server as serverModule
import json, options, times, strformat

suite "Polymorphic Transport Tests":
  
  test "TransportInterface base methods":
    # Test that base methods raise appropriate errors
    let transport = TransportInterface()
    transport.capabilities = {tcBroadcast, tcEvents}
    
    check transport.capabilities == {tcBroadcast, tcEvents}
    
    # Base methods should raise errors when not implemented
    expect(CatchableError):
      transport.broadcastMessage(%*{"test": "message"})
    
    expect(CatchableError):
      transport.sendEvent("test_event", %*{"data": "test"})
    
    check transport.getTransportKind() == tkNone

  test "McpServer polymorphic getTransport() - no transport set":
    let server = newMcpServer("test-server", "1.0.0")
    
    # Should return nil when no transport is set
    let transport = server.getTransport()
    check transport == nil
    
    # Transport kind should be tkNone
    check server.getTransportKind() == tkNone
    check not server.hasTransport()

  test "McpServer polymorphic getTransport() - with SSE transport":
    let server = newMcpServer("test-server", "1.0.0")
    let sseTransport = newSseTransport(server, port = 9001, host = "127.0.0.1")
    
    # Set the transport
    server.setTransport(sseTransport)
    
    # Should return valid transport interface
    let transport = server.getTransport()
    check transport != nil
    check transport.getTransportKind() == tkSSE
    check server.hasTransport()
    
    # Should have SSE capabilities
    check tcBroadcast in transport.capabilities
    check tcEvents in transport.capabilities
    check tcUnicast in transport.capabilities

  test "McpServer polymorphic getTransport() - with WebSocket transport":
    let server = newMcpServer("test-server", "1.0.0")
    let wsTransport = newWebSocketTransport(server, port = 9002, host = "127.0.0.1")
    
    # Set the transport
    server.setTransport(wsTransport)
    
    # Should return valid transport interface
    let transport = server.getTransport()
    check transport != nil
    check transport.getTransportKind() == tkWebSocket
    check server.hasTransport()
    
    # Should have WebSocket capabilities (including bidirectional)
    check tcBroadcast in transport.capabilities
    check tcEvents in transport.capabilities
    check tcUnicast in transport.capabilities
    check tcBidirectional in transport.capabilities

  test "Transport switching without code changes":
    ## This test demonstrates the key benefit - same code works with different transports
    
    proc testUniversalTool(server: McpServer): string =
      ## Universal tool that works with any transport
      let transport = server.getTransport()
      if transport == nil:
        return "No transport available"
      
      let kind = transport.getTransportKind()
      
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
    let sseTransport = newSseTransport(server, port = 9003)
    server.setTransport(sseTransport)
    check testUniversalTool(server) == "Successfully used sse transport"
    
    # Switch to WebSocket transport - SAME CODE WORKS!
    let wsTransport = newWebSocketTransport(server, port = 9004)
    server.setTransport(wsTransport)
    check testUniversalTool(server) == "Successfully used websocket transport"

  test "Transport capabilities and introspection":
    let server = newMcpServer("test-server", "1.0.0")
    
    # Test SSE capabilities
    let sseTransport = newSseTransport(server, port = 9005)
    server.setTransport(sseTransport)
    
    let sseInterface = server.getTransport()
    check sseInterface != nil
    check sseInterface.getTransportKind() == tkSSE
    check tcBroadcast in sseInterface.capabilities
    check tcEvents in sseInterface.capabilities
    check tcUnicast in sseInterface.capabilities
    check tcBidirectional notin sseInterface.capabilities  # SSE is not bidirectional
    
    # Test WebSocket capabilities
    let wsTransport = newWebSocketTransport(server, port = 9006)
    server.setTransport(wsTransport)
    
    let wsInterface = server.getTransport()
    check wsInterface != nil
    check wsInterface.getTransportKind() == tkWebSocket
    check tcBroadcast in wsInterface.capabilities
    check tcEvents in wsInterface.capabilities
    check tcUnicast in wsInterface.capabilities
    check tcBidirectional in wsInterface.capabilities  # WebSocket IS bidirectional

  test "Polymorphic transport in request context":
    ## Test accessing transport through request context (like in tools)
    let server = newMcpServer("test-server", "1.0.0")
    let sseTransport = newSseTransport(server, port = 9007)
    server.setTransport(sseTransport)
    
    # Create a request context
    let ctx = newMcpRequestContext("test-request")
    ctx.server = cast[pointer](server)
    
    # Access transport through context (as tools would do)
    let contextServer = ctx.getServer()
    check contextServer != nil
    
    let transport = contextServer.getTransport()
    check transport != nil
    check transport.getTransportKind() == tkSSE

  test "Transport union type safety":
    ## Test that the union type system works correctly
    let server = newMcpServer("test-server", "1.0.0")
    
    # Initially no transport
    check server.getTransportKind() == tkNone
    check server.getSseTransportPtr() == nil
    check server.getWebSocketTransportPtr() == nil
    
    # Set SSE transport
    let sseTransport = newSseTransport(server, port = 9008)
    server.setTransport(sseTransport)
    
    check server.getTransportKind() == tkSSE
    check server.getSseTransportPtr() != nil
    check server.getWebSocketTransportPtr() == nil  # Should be nil for wrong type
    
    # Switch to WebSocket transport
    let wsTransport = newWebSocketTransport(server, port = 9009)
    server.setTransport(wsTransport)
    
    check server.getTransportKind() == tkWebSocket
    check server.getSseTransportPtr() == nil        # Should be nil for wrong type
    check server.getWebSocketTransportPtr() != nil
    
    # Clear transport
    server.clearTransport()
    check server.getTransportKind() == tkNone
    check not server.hasTransport()

suite "Transport Polymorphism Integration":
  
  test "Polymorphic transport with real MCP tools":
    ## Integration test showing polymorphic transport with actual tool registration
    
    # Tool that uses polymorphic transport access
    proc universalNotifyTool(ctx: McpRequestContext, args: JsonNode): McpToolResult {.gcsafe.} =
      let message = args.getOrDefault("message").getStr("test")
      let server = ctx.getServer()
      let transport = if server != nil: server.getTransport() else: nil
      
      if transport == nil:
        return McpToolResult(content: @[createTextContent("No transport available")])
      
      let kind = transport.getTransportKind()
      let notificationData = %*{
        "type": "test_notification",
        "message": message,
        "transport": $kind
      }
      
      # This works with ANY transport!
      transport.broadcastMessage(notificationData)
      transport.sendEvent("test_event", notificationData)
      
      return McpToolResult(content: @[createTextContent(fmt"Sent via {kind}")])
    
    let server = newMcpServer("test-server", "1.0.0")
    
    # Register the universal tool
    server.registerToolWithContext(McpTool(
      name: "universal_notify",
      description: some("Universal notification tool"),
      inputSchema: %*{
        "type": "object",
        "properties": {
          "message": {"type": "string"}
        }
      }
    ), universalNotifyTool)
    
    # Test with SSE transport
    let sseTransport = newSseTransport(server, port = 9010)
    server.setTransport(sseTransport)
    
    let ctx = newMcpRequestContext("test")
    ctx.server = cast[pointer](server)
    
    let args = %*{"message": "Hello SSE"}
    let result = universalNotifyTool(ctx, args)
    check result.content[0].text == "Sent via sse"
    
    # Switch to WebSocket - SAME TOOL WORKS!
    let wsTransport = newWebSocketTransport(server, port = 9011)
    server.setTransport(wsTransport)
    
    let result2 = universalNotifyTool(ctx, args)
    check result2.content[0].text == "Sent via websocket"

echo "🧪 Testing polymorphic transport system..."