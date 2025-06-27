## Tests resource templates, server composition, logging, and streaming

import unittest, json, tables, options, strutils, times
import ../src/nimcp

suite "Extra Features Tests":
  
  test "Resource URI Templates - Basic functionality":
    # Test URI template compilation
    let matcher = compileUriTemplate("/users/{id}")
    check matcher.paramNames == @["id"]
    check matcher.uriTemplate == "/users/{id}"
    
    # Test URI matching
    let params = matchUri(matcher, "/users/123")
    check params.isSome
    check params.get()["id"] == "123"
    
    # Test non-matching URI
    let noMatch = matchUri(matcher, "/posts/123")
    check noMatch.isNone
  
  test "Resource URI Templates - Complex patterns":
    # Test nested parameters
    let nestedMatcher = compileUriTemplate("/projects/{projectId}/issues/{issueId}")
    check nestedMatcher.paramNames == @["projectId", "issueId"]
    
    let nestedParams = matchUri(nestedMatcher, "/projects/abc/issues/456")
    check nestedParams.isSome
    let params = nestedParams.get()
    check params["projectId"] == "abc"
    check params["issueId"] == "456"
    
    # Test utility functions
    check validateTemplate("/users/{id}") == true
    check validateTemplate("/invalid/{}") == false
    check getTemplateParams("/users/{id}/posts/{postId}") == @["id", "postId"]
  
  test "Resource URI Templates - Registry functionality":
    var registry = newResourceTemplateRegistry()
    
    # Create test template and handler
    let resourceTemplate = McpResourceTemplate(
      uriTemplate: "/test/{id}",
      name: "Test Resource",
      description: some("Test resource template"),
      mimeType: some("application/json")
    )
    
    proc testHandler(uri: string, params: Table[string, string]): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        mimeType: some("application/json"),
        content: @[McpContent(
          `type`: "text",
          kind: TextContent,
          text: "ID: " & params.getOrDefault("id", "unknown")
        )]
      )
    
    # Register template
    registry.registerTemplate(resourceTemplate, testHandler)
    
    # Test template finding
    let found = registry.findTemplate("/test/123")
    check found.isSome
    
    # Test template handling
    let result = registry.handleTemplateRequest("/test/123")
    check result.isSome
    check result.get().content[0].text == "ID: 123"
  
  test "Server Composition - Basic mounting":
    # Create servers
    let mainServer = newComposedServer("main", "1.0.0")
    let serviceServer = newMcpServer("service", "1.0.0")
    
    # Register a tool in service server
    proc testTool(args: JsonNode): McpToolResult =
      return McpToolResult(
        content: @[McpContent(
          `type`: "text",
          kind: TextContent,
          text: "Service response"
        )]
      )
    
    serviceServer.registerTool(
      McpTool(
        name: "test_tool",
        description: some("Test tool"),
        inputSchema: newJObject()
      ),
      testTool
    )
    
    # Mount service
    mainServer.mountServerAt("/service", serviceServer, some("svc_"))
    
    # Test mount point finding
    let mountPoint = mainServer.findMountPointForTool("svc_test_tool")
    check mountPoint.isSome
    check mountPoint.get().path == "/service"
    check mountPoint.get().prefix.get() == "svc_"
    
    # Test prefix utilities
    check stripPrefix("svc_test_tool", some("svc_")) == "test_tool"
    check addPrefix("test_tool", some("svc_")) == "svc_test_tool"
  
  test "Server Composition - Mount point management":
    let composed = newComposedServer("composed", "1.0.0")
    let server1 = newMcpServer("server1", "1.0.0")
    let server2 = newMcpServer("server2", "1.0.0")
    
    # Mount servers
    composed.mountServerAt("/s1", server1, some("s1_"))
    composed.mountServerAt("/s2", server2, some("s2_"))
    
    # Check mount points
    let mountPoints = composed.listMountPoints()
    check mountPoints.len == 2
    
    # Test unmounting
    let unmounted = composed.unmountServer("/s1")
    check unmounted == true
    check composed.listMountPoints().len == 1
    
    # Test unmounting non-existent
    let notUnmounted = composed.unmountServer("/nonexistent")
    check notUnmounted == false
  
  test "Pluggable Logging - Basic functionality":
    # Test logger creation
    let logger = newLogger(llInfo)
    check logger.minLevel == llInfo
    check logger.enabled == true
    
    # Test log level filtering
    check logger.shouldLog(llError) == true
    check logger.shouldLog(llDebug) == false
    
    # Test component setting
    logger.setComponent("test-component")
    check logger.component.get() == "test-component"
    
    # Test enable/disable
    logger.disable()
    check logger.enabled == false
    logger.enable()
    check logger.enabled == true
  
  test "Pluggable Logging - Message creation":
    let msg = newLogMessage(
      llInfo,
      "Test message",
      some("test-component"),
      some("req-123"),
      {"key": %"value"}.toTable
    )
    
    check msg.level == llInfo
    check msg.message == "Test message"
    check msg.component.get() == "test-component"
    check msg.requestId.get() == "req-123"
    check msg.context["key"].getStr() == "value"
  
  test "Pluggable Logging - Handlers":
    var loggedMessages = newSeq[LogMessage]()

    proc testHandler(msg: LogMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        loggedMessages.add(msg)

    let logger = newLogger(llDebug)
    logger.addHandler(testHandler)

    # Test logging
    logger.info("Test info message")
    logger.error("Test error message")

    check loggedMessages.len == 2
    check loggedMessages[0].level == llInfo
    check loggedMessages[1].level == llError
  
  test "Pluggable Logging - Server integration":
    let server = newMcpServer("logging-test", "1.0.0")

    # Test default logger setup
    check server.logger != nil

    # Test log level setting
    server.setLogLevel(llWarn)
    check server.logger.minLevel == llWarn
    
    # Test custom handler addition
    var captured = newSeq[LogMessage]()
    proc captureHandler(msg: LogMessage) {.gcsafe.} =
      {.cast(gcsafe).}:
        captured.add(msg)
    
    server.addLogHandler(captureHandler)
    
    # Log a message and verify capture
    server.logger.warn("Test warning")
    check captured.len >= 1
  
  # TODO: Implement HTTP Streaming functionality
  # test "HTTP Streaming - Message formatting":
  #   # Test basic SSE message
  #   let msg = newStreamingMessage("Hello World")
  #   let formatted = msg.formatSSE()
  #   check "data: Hello World\n\n" in formatted
  #
  #   # Test message with event and ID
  #   let complexMsg = newStreamingMessage(
  #     data = "Complex data",
  #     event = some("test-event"),
  #     id = some("msg-123"),
  #     retry = some(5000)
  #   )
  #   let complexFormatted = complexMsg.formatSSE()
  #   check "event: test-event\n" in complexFormatted
  #   check "id: msg-123\n" in complexFormatted
  #   check "retry: 5000\n" in complexFormatted
  #   check "data: Complex data\n" in complexFormatted
  #
  # test "HTTP Streaming - Multi-line data":
  #   let multiLineMsg = newStreamingMessage("Line 1\nLine 2\nLine 3")
  #   let formatted = multiLineMsg.formatSSE()
  #   check "data: Line 1\n" in formatted
  #   check "data: Line 2\n" in formatted
  #   check "data: Line 3\n" in formatted
  #
  # test "HTTP Streaming - Connection management":
  #   let mcpServer = newMcpServer("streaming-test", "1.0.0")
  #   let streamingServer = newStreamingServer(mcpServer, 8091, "127.0.0.1")
  #
  #   check streamingServer.port == 8091
  #   check streamingServer.host == "127.0.0.1"
  #   check streamingServer.connections.len == 0
  
  test "Request Context - Basic functionality":
    let ctx = newMcpRequestContext("test-req")
    
    check ctx.requestId == "test-req"
    check ctx.cancelled == false
    check ctx.metadata.len == 0
    
    # Test metadata
    ctx.setMetadata("key", %"value")
    check ctx.getMetadata("key").get().getStr() == "value"
    
    # Test cancellation
    ctx.cancel()
    check ctx.cancelled == true
    
    # Test cancellation check
    expect RequestCancellation:
      ctx.ensureNotCancelled()
  
  test "Request Context - Progress tracking":
    let ctx = newMcpRequestContext("progress-test")
    
    var progressUpdates = newSeq[McpProgressInfo]()

    ctx.progressCallback = proc(message: string, progress: float) {.gcsafe, closure.} =
      {.cast(gcsafe).}:
        progressUpdates.add(McpProgressInfo(
          message: message,
          progress: progress,
          timestamp: now()
        ))
    
    # Test progress updates
    ctx.reportProgress("Starting", 0.0)
    ctx.reportProgress("Halfway", 0.5)
    ctx.reportProgress("Complete", 1.0)
    
    check progressUpdates.len == 3
    check progressUpdates[0].message == "Starting"
    check progressUpdates[1].progress == 0.5
    check progressUpdates[2].progress == 1.0
  
  test "Request Context - Logging integration":
    let ctx = newMcpRequestContext("log-test")
    
    var logMessages = newSeq[string]()

    ctx.logCallback = proc(level: string, message: string) {.gcsafe, closure.} =
      {.cast(gcsafe).}:
        logMessages.add(level & ": " & message)
    
    # Test context logging
    ctx.logMessage("info", "Test info message")
    ctx.logMessage("error", "Test error message")
    
    check logMessages.len == 2
    check "info: Test info message" in logMessages
    check "error: Test error message" in logMessages
  
  test "Structured Errors - Error creation":
    let structuredError = newMcpStructuredError(
      InvalidParams,
      melError,
      "Test error message",
      details = "Additional details",
      requestId = "req-123"
    )
    
    check structuredError.code == InvalidParams
    check structuredError.level == melError
    check structuredError.message == "Test error message"
    check structuredError.details.get() == "Additional details"
    check structuredError.requestId.get() == "req-123"
    
    # Test JSON-RPC error conversion
    let jsonRpcError = structuredError.toJsonRpcError()
    check jsonRpcError.code == InvalidParams
    check jsonRpcError.message == "Test error message"
  
  test "Structured Errors - Error with context":
    var errorWithContext = newMcpStructuredError(
      McpValidationError,
      melWarning,
      "Validation failed"
    )

    # Add context using the addErrorContext proc
    errorWithContext.addErrorContext("param", %"value")
    errorWithContext.addErrorContext("step", %"validation")

    check errorWithContext.context.isSome
    check errorWithContext.context.get()["param"].getStr() == "value"
    check errorWithContext.level == melWarning
  
  test "Integration - Resource templates with server":
    let server = newMcpServer("integration-test", "1.0.0")
    
    # Register resource template
    proc templateHandler(ctx: McpRequestContext, uri: string, params: Table[string, string]): McpResourceContents =
      return McpResourceContents(
        uri: uri,
        mimeType: some("text/plain"),
        content: @[McpContent(
          `type`: "text",
          kind: TextContent,
          text: "Resource " & params.getOrDefault("id", "unknown")
        )]
      )
    
    server.registerResourceTemplateWithContext(
      McpResourceTemplate(
        uriTemplate: "/items/{id}",
        name: "Item Resource",
        description: some("Dynamic item access"),
        mimeType: some("text/plain")
      ),
      templateHandler
    )
    
    # Initialize the server first
    let initRequest = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridString, str: "init")),
      `method`: "initialize",
      params: some(%{
        "protocolVersion": %"2024-11-05",
        "clientInfo": %{"name": %"test-client", "version": %"1.0.0"},
        "capabilities": newJObject()
      })
    )
    let initResponse = server.handleRequest(initRequest)
    check initResponse.result.isSome
    
    # Test resource access through server
    let request = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridString, str: "test")),
      `method`: "resources/read",
      params: some(%{"uri": %"/items/123"})
    )
    
    let response = server.handleRequest(request)
    check response.result.isSome
    # Note: Full JSON parsing would require more detailed checking
  
  test "Integration - Composed server with logging":
    let composedServer = newComposedServer("integration-composed", "1.0.0")
    let serviceServer = newMcpServer("service", "1.0.0")
    
    # Set up logging capture
    var logCaptured = newSeq[LogMessage]()
    proc logCapture(msg: LogMessage) {.gcsafe, closure.} =
      {.cast(gcsafe).}:
        logCaptured.add(msg)

    serviceServer.addLogHandler(logCapture)
    
    # Register tool that uses logging
    proc loggingTool(ctx: McpRequestContext, args: JsonNode): McpToolResult =
      ctx.logMessage("info", "Tool executed")
      return McpToolResult(
        content: @[McpContent(
          `type`: "text",
          kind: TextContent, 
          text: "Success"
        )]
      )
    
    serviceServer.registerToolWithContext(
      McpTool(
        name: "logging_tool",
        description: some("Tool with logging"),
        inputSchema: newJObject()
      ),
      loggingTool
    )
    
    # Mount service
    composedServer.mountServerAt("/logs", serviceServer, some("log_"))
    
    # Verify composition worked
    let mountPoint = composedServer.findMountPointForTool("log_logging_tool")
    check mountPoint.isSome
    check mountPoint.get().path == "/logs"

echo "✅ All extra feature tests completed!"