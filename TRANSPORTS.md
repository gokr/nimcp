# Transport Architecture and Future Tasks

This document describes the NimCP transport architecture and remaining tasks.

## Current Architecture

NimCP now uses direct transport references via Nim object variants with case-switch dispatch, as implemented in commit 2ab6fd7.

### Transport Types

- **stdio**: JSON-RPC over stdin/stdout (traditional MCP)
- **HTTP**: JSON-RPC over HTTP POST (Mummy-based)
- **WebSocket**: Real-time bidirectional JSON-RPC (Mummy-based) 
- **SSE**: Server-Sent Events with HTTP POST for client-to-server (Mummy-based)

### Key Components

- `McpTransport` object variant holds direct transport instance pointers
- Function pointers avoid circular imports between context and transport modules
- `McpRequestContext.sendEvent()` uses case-switch dispatch to call appropriate transport
- Each transport provides wrapper functions matching the function pointer signature

### Architecture Benefits

- ✅ Direct transport access in request context
- ✅ No global state or registries
- ✅ Type-safe transport-specific operations
- ✅ Nim-style object variants instead of OOP inheritance
- ✅ No circular import issues
- ✅ GC-safe function pointers

## Verified Functionality

### MCP Notifications (Bidirectional)

All transports support **bidirectional MCP notifications**, with varying capabilities:

#### Server-to-Client Notifications (`ctx.sendNotification`)

- ✅ **SSE**: Notifications sent as `notifications/message` via Server-Sent Events stream
- ✅ **WebSocket**: Notifications sent as JSON-RPC notifications over WebSocket connection  
- ⚠️ **HTTP**: Limited notification support - only works with active streaming connections (SSE mode)
- ✅ **stdio**: Notifications sent as JSON-RPC notifications to stdout

#### Client-to-Server Notifications (New!)

- ✅ **SSE**: Client sends JSON-RPC notifications via POST to message endpoint
- ✅ **WebSocket**: Client sends JSON-RPC notifications over WebSocket connection
- ✅ **HTTP**: Client sends JSON-RPC notifications via POST (within request scope)
- ✅ **stdio**: Client sends JSON-RPC notifications via stdin

**Registration Example:**
```nim
# Regular notification handler
server.registerNotification("client/hello", proc(params: JsonNode) =
  echo "Client said hello: ", params
)

# Context-aware notification handler (can access transport)
server.registerNotificationWithContext("client/ping", proc(ctx: McpRequestContext, params: JsonNode) =
  echo "Client ping from ", ctx.transport.kind, ": ", params
  # Can send response notifications back
  ctx.sendNotification("server/pong", %*{"timestamp": now()})
)
```

#### HTTP Transport Notification Limitations

HTTP transport has **limited notification support** because it lacks persistent connections:

- **Regular HTTP mode**: Notifications are ignored (no persistent connection)
- **Streaming HTTP mode**: Notifications sent to active SSE streaming connections
- **Use case**: HTTP notifications work best when client uses `Accept: text/event-stream` header

For full notification support, prefer SSE or WebSocket transports over plain HTTP.

### Testing Status

- ✅ End-to-end notification testing with curl
- ✅ All transport types verified working
- ✅ All examples compile successfully
- ✅ All tests pass

## Future Improvements

### High Priority

1. **Consider renaming `ctx.sendEvent()` to `ctx.sendNotification()`**
   - More accurate MCP terminology
   - Clearer intent for API users
   - Would require updating examples and documentation

2. **Add transport-specific event types**
   - Progress notifications
   - Status updates  
   - Error notifications
   - Resource change notifications

### Medium Priority

3. **Enhanced WebSocket support**
   - Bidirectional event streams
   - Client-initiated events
   - Connection lifecycle events

4. **HTTP streaming improvements**
   - Better support for long-lived HTTP connections
   - Chunked transfer encoding optimizations
   - Server-sent events over HTTP/2

5. **Transport multiplexing**
   - Support multiple concurrent transports
   - Transport failover mechanisms
   - Load balancing across transports

### Low Priority

6. **Transport extensions**
   - gRPC transport support
   - Message queue integration (Redis, RabbitMQ)
   - Custom protocol adapters

7. **Performance optimizations**
   - Connection pooling
   - Batched event sending
   - Compression support

## Implementation Notes

### Pointer Safety

The current implementation uses `cast[pointer](transport)` to store transport references and `cast[TransportType](ptr)` to retrieve them. This works because:

- Nim objects don't move during their lifetime
- Transport objects persist for the server's lifetime
- No reference counting or GC movement issues

### Function Pointer Pattern

```nim
# Transport object variant
McpTransport = object
  case kind: TransportKind
  of tkSSE:
    sseTransport: pointer
    sseSendEvent: proc(transport: pointer, eventType: string, data: JsonNode, target: string) {.gcsafe.}

# Wrapper function  
proc sseEventWrapper(transportPtr: pointer, eventType: string, data: JsonNode, target: string) {.gcsafe.} =
  let transport = cast[SseTransport](transportPtr)
  transport.sendEventToSSEClients(eventType, data, target)

# Usage in context
proc sendEvent*(ctx: McpRequestContext, eventType: string, data: JsonNode, target: string = "") =
  case ctx.transport.kind:
  of tkSSE:
    if ctx.transport.sseTransport != nil and ctx.transport.sseSendEvent != nil:
      ctx.transport.sseSendEvent(ctx.transport.sseTransport, eventType, data, target)
```

This pattern provides type safety while avoiding circular imports.

## Security Considerations

- Transport authentication is handled at the HTTP server level
- Function pointers are validated for nil before calling
- Type casting is safe due to transport lifetime guarantees
- No eval or dynamic code execution in transport layer

## Performance Characteristics

- **stdio**: Lowest latency, single client
- **HTTP**: Moderate latency, stateless, multiple clients  
- **WebSocket**: Low latency, stateful, multiple concurrent clients
- **SSE**: Low latency, server-to-client only, multiple clients

Choose transport based on your use case:
- CLI tools → stdio
- Web dashboards → SSE  
- Real-time apps → WebSocket
- REST APIs → HTTP