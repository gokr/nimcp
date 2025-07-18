## Example demonstrating Pluggable Logging Architecture in NimCP
## Shows different logging configurations and handlers

import ../src/nimcp, json, tables, options

proc exampleTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
  ## Example tool that demonstrates context logging
  let input = args.getOrDefault("input").getStr("default")
  
  # Log with context
  ctx.info("Processing input: " & input)
  
  # Simulate some work with status updates via logging
  ctx.info("Starting processing...")
  
  # Simulate error for demonstration
  if input == "error":
    ctx.error("Simulated error occurred for input: " & input)
    raise newException(ValueError, "Simulated error for input: " & input)
  
  ctx.info("Processing halfway complete...")
  ctx.info("Processing almost finished...")
  ctx.info("Processing complete!")
  
  ctx.info("Processing completed successfully")
  
  return McpToolResult(
    content: @[McpContent(
      `type`: "text",
      kind: TextContent,
      text: "Processed: " & input
    )]
  )

when isMainModule:
  echo "=== Pluggable Logging Example ==="
  
  # Create server with custom logging
  let server = newMcpServer("logging-example", "1.0.0")
  
  # Configure different log levels and handlers
  echo "1. Console Logging (default):"
  server.setLogLevel(llDebug)
  
  # Add JSON logging handler
  echo "2. Adding JSON logging handler:"
  server.addLogHandler(jsonHandler)
  
  # Add file logging handler
  echo "3. Adding file logging handler:"
  server.enableFileLogging("example.log")
  
  # Register a tool that uses context logging
  server.registerToolWithContext(
    McpTool(
      name: "example_tool",
      description: some("Tool that demonstrates logging"),
      inputSchema: parseJson("""{"type": "object", "properties": {"input": {"type": "string"}}}""")
    ),
    exampleTool
  )
  
  # Demonstrate different log levels
  echo "4. Testing different log levels:"
  let logger = server.logger 
  logger.trace("This is a trace message", 
    context = {"component": %"example"}.toTable)
  logger.debug("This is a debug message",
    context = {"operation": %"test"}.toTable)
  logger.info("This is an info message")
  logger.warn("This is a warning message")
  logger.error("This is an error message")
  
  echo ""
  
  # Test context logging with requests
  echo "5. Testing context-aware logging:"
  let ctx = newMcpRequestContext("test-request")
  ctx.info("Request started for operation: example")
  
  # Simulate tool execution with logging
  echo "6. Simulating tool execution:"
  try:
    let args = %*{"input": "test_input"}
    discard exampleTool(ctx, args)
    echo "✓ Tool executed successfully"
  except Exception as e:
    echo "✗ Tool execution failed: " & e.msg
  
  echo ""
  
  # Test error logging
  echo "7. Testing error logging:"
  try:
    let errorArgs = %*{"input": "error"}
    discard exampleTool(ctx, errorArgs)
  except Exception as e:
    logger.error("Tool execution failed", 
      context = {"error": %e.msg, "requestId": %ctx.requestId}.toTable)
    echo "✓ Error logged successfully"
  
  echo ""
  
  # Demonstrate custom logger setup
  echo "8. Creating custom logger:"
  let customLogger = newLogger(llWarn)
  customLogger.setComponent("custom-component")
  customLogger.addHandler(consoleHandler)
  
  customLogger.info("This info message won't appear (below warn level)")
  customLogger.warn("This warning will appear")
  customLogger.error("This error will appear")
  
  echo ""
  
  # Demonstrate global logging functions
  echo "9. Using global logging functions:"
  setupDefaultLogging(llInfo, useChronicles = false)
  
  info("Global info message")
  warn("Global warning message") 
  error("Global error message")
  
  echo ""
  
  # Create a streaming logger that could be used with streaming transport
  echo "10. Custom streaming log handler:"
  var logMessages {.threadvar.}: seq[LogMessage]
  logMessages = @[]
  
  proc streamingLogHandler(msg: LogMessage) {.gcsafe.} =
    logMessages.add(msg)
    echo "📡 STREAM: [" & $msg.level & "] " & msg.message
  
  let streamingLogger = newLogger(llDebug)
  streamingLogger.addHandler(streamingLogHandler)
  
  streamingLogger.info("This message goes to streaming handler")
  streamingLogger.error("Error message for streaming")
  
  echo "Captured " & $logMessages.len & " messages in streaming handler"
  
  echo ""
  echo "🎯 Pluggable Logging example completed!"
  echo "Check 'example.log' file for file logging output."
  echo "This demonstrates flexible logging with multiple handlers and levels."

  let transport = newStdioTransport()
  transport.serve(server)