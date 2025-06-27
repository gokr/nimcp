## Example demonstrating HTTP Streaming with Server-Sent Events in NimCP
## Shows real-time streaming capabilities over HTTP

import ../src/nimcp, asyncdispatch, json, options

proc longRunningTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
  ## Tool that simulates long-running operation with progress updates
  let duration = args.getOrDefault("duration").getInt(5)
  let taskName = args.getOrDefault("task").getStr("default-task")
  
  ctx.logMessage("info", "Starting long-running task: " & taskName & " (" & $duration & "s)")
  
  # Simulate work with progress updates
  for i in 0..duration:
    let progress = i.float / duration.float
    ctx.updateProgress("Step " & $i & " of " & $duration, progress)
    
    # Sleep to simulate work (in real implementation, use actual async work)
    sleep(1000)
  
  ctx.logMessage("info", "Task completed: " & taskName)
  
  return McpToolResult(
    content: @[McpContent(
      `type`: "text",
      kind: TextContent,
      text: "Task '" & taskName & "' completed in " & $duration & " seconds"
    )]
  )

proc dataStreamTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
  ## Tool that generates streaming data
  let count = args.getOrDefault("count").getInt(10)
  let delay = args.getOrDefault("delay").getInt(500)
  
  ctx.logMessage("info", "Starting data stream: " & $count & " items with " & $delay & "ms delay")
  
  var results: seq[string] = @[]
  
  for i in 1..count:
    let dataItem = """{"id": """ & $i & """, "value": """ & $(i * 10) & """, "timestamp": """ & $epochTime() & """}"""
    results.add(dataItem)
    
    let progress = i.float / count.float
    ctx.updateProgress("Generated item " & $i, progress)
    
    # Log each data item
    ctx.logMessage("debug", "Generated data item " & $i & ": " & dataItem)
    
    sleep(delay)
  
  return McpToolResult(
    content: @[McpContent(
      `type`: "text",
      kind: TextContent,
      text: "[" & results.join(", ") & "]"
    )]
  )

proc errorTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
  ## Tool that demonstrates error handling in streaming
  let errorType = args.getOrDefault("error_type").getStr("generic")
  
  ctx.logMessage("warn", "Error tool called with type: " & errorType)
  
  case errorType:
  of "timeout":
    ctx.updateProgress("Starting operation that will timeout...", 0.1)
    sleep(2000)
    raise newRequestTimeout("Operation timed out")
  of "cancelled":
    ctx.updateProgress("Starting operation that will be cancelled...", 0.1) 
    ctx.cancel()
    raise newRequestCancellation("Operation was cancelled")
  else:
    ctx.updateProgress("About to fail...", 0.5)
    raise newException(ValueError, "Generic error: " & errorType)

when isMainModule:
  echo "=== HTTP Streaming with Server-Sent Events Example ==="
  
  # Create MCP server
  let mcpServer = newMcpServer("streaming-example", "1.0.0")
  
  # Register streaming-friendly tools
  mcpServer.registerToolWithContext(
    McpTool(
      name: "long_task",
      description: some("Long-running task with progress updates"),
      inputSchema: parseJson("""{"type": "object", "properties": {"duration": {"type": "integer", "minimum": 1, "maximum": 30}, "task": {"type": "string"}}}""")
    ),
    longRunningTool
  )
  
  mcpServer.registerToolWithContext(
    McpTool(
      name: "data_stream",
      description: some("Generate streaming data"),
      inputSchema: parseJson("""{"type": "object", "properties": {"count": {"type": "integer", "minimum": 1, "maximum": 100}, "delay": {"type": "integer", "minimum": 100, "maximum": 5000}}}""")
    ),
    dataStreamTool
  )
  
  mcpServer.registerToolWithContext(
    McpTool(
      name: "error_demo",
      description: some("Demonstrate error handling"),
      inputSchema: parseJson("""{"type": "object", "properties": {"error_type": {"type": "string", "enum": ["generic", "timeout", "cancelled"]}}}""")
    ),
    errorTool
  )
  
  # Enable streaming for the MCP server
  let streamingServer = mcpServer.enableStreaming(8090, "127.0.0.1")
  
  echo "✓ Created streaming server with tools:"
  echo "  - long_task: Simulates long-running operations"
  echo "  - data_stream: Generates streaming data"
  echo "  - error_demo: Demonstrates error handling"
  echo ""
  
  # Demonstrate streaming message creation
  echo "Streaming message examples:"
  
  let toolResultMsg = newStreamingMessage(
    data = """{"result": "example"}""",
    event = some("tool-result"),
    id = some("tool-123")
  )
  echo "✓ Tool result message: " & toolResultMsg.formatSSE().strip()
  
  let progressMsg = newStreamingMessage(
    data = """{"progress": 0.5, "message": "Halfway done"}""",
    event = some("progress"),
    id = some("progress-456")
  )
  echo "✓ Progress message: " & progressMsg.formatSSE().strip()
  
  let logMsg = newStreamingMessage(
    data = """{"level": "info", "message": "Task started"}""",
    event = some("log"),
    retry = some(5000)
  )
  echo "✓ Log message: " & logMsg.formatSSE().strip()
  
  echo ""
  
  # Show connection management
  echo "Connection management:"
  echo "✓ Streaming server ready on http://127.0.0.1:8090"
  echo "  Endpoints:"
  echo "  - GET /events - Server-Sent Events stream"
  echo "  - POST /api/stream - MCP requests with streaming response"
  echo "  - POST / - Regular MCP requests"
  echo ""
  
  # Simulate client interaction examples
  echo "Example client usage:"
  echo ""
  echo "1. Connect to SSE stream:"
  echo "   curl -N http://127.0.0.1:8090/events"
  echo ""
  echo "2. Send MCP request with streaming:"
  echo """   curl -X POST http://127.0.0.1:8090/api/stream \"""
  echo """     -H "Content-Type: application/json" \"""
  echo """     -d '{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"long_task","arguments":{"duration":5,"task":"example"}}}'"""
  echo ""
  echo "3. Regular MCP request:"
  echo """   curl -X POST http://127.0.0.1:8090/ \"""
  echo """     -H "Content-Type: application/json" \"""
  echo """     -d '{"jsonrpc":"2.0","id":"1","method":"tools/list"}'"""
  echo ""
  
  # Note about running the server
  echo "🚀 To run the streaming server:"
  echo "   Uncomment the lines below and run this example"
  echo "   The server will run indefinitely until stopped with Ctrl+C"
  echo ""
  
  # Uncomment these lines to actually run the server:
  # echo "Starting streaming server... (Press Ctrl+C to stop)"
  # waitFor streamingServer.runStreamingServer()
  
  echo "🎯 HTTP Streaming example completed!"
  echo "This demonstrates real-time streaming with Server-Sent Events."
  echo ""
  echo "Key features shown:"
  echo "- Real-time progress updates"
  echo "- Structured log streaming"
  echo "- Error handling in streams"
  echo "- Connection management"
  echo "- Multiple streaming endpoints"