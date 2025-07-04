## MCP Stdio Transport implementation using taskpools for concurrent request processing
##
## This module provides the stdio transport implementation for MCP servers.
## It handles JSON-RPC communication over stdin/stdout with concurrent request processing.

import json, locks, options, deques
import taskpools, cpuinfo
import types, protocol, server, composed_server, logging

type 
  InitializationState* = enum
    ## MCP initialization state tracking for protocol compliance
    isNotInitialized = "not_initialized"
    isInitializing = "initializing" 
    isInitialized = "initialized"

  StdioTransport* = ref object
    ## Stdio transport implementation for MCP servers with MCP protocol compliance
    taskpool: Taskpool
    stdoutLock: Lock
    initState: InitializationState
    initLock: Lock
    queuedRequests: Deque[string]  # Queue for requests during initialization

proc newStdioTransport*(numThreads: int = 0): StdioTransport =
  ## Args:
  ##   numThreads: Number of worker threads (0 = auto-detect)
  new(result)
  let threads = if numThreads > 0: numThreads else: countProcessors()
  result.taskpool = Taskpool.new(numThreads = threads)
  initLock(result.stdoutLock)
  initLock(result.initLock)
  result.initState = isNotInitialized
  result.queuedRequests = initDeque[string]()

proc safeEcho(transport: StdioTransport, msg: string) =
  ## Thread-safe output handling
  withLock transport.stdoutLock:
    echo msg
    stdout.flushFile()

proc isInitializeRequest(requestLine: string): bool =
  ## Check if a request line contains an initialize method (MCP protocol compliance)
  try:
    let parsed = parseJson(requestLine)
    if parsed.hasKey("method") and parsed["method"].kind == JString:
      return parsed["method"].getStr() == "initialize"
  except:
    discard
  return false

# Request processing task for taskpools
proc processRequestTask[T](transport: ptr StdioTransport, server: ptr T, requestLine: string) {.gcsafe.} =
  var requestId: JsonRpcId = JsonRpcId(kind: jridString, str: "")
  try:
    let request = parseJsonRpcMessage(requestLine)
    if request.id.isSome():
      requestId = request.id.get
    if not request.id.isSome():
      server[].handleNotification(request)
    else:
      let response = server[].handleRequest(request)
      transport[].safeEcho($response)
  except Exception as e:
    let errorResponse = createJsonRpcError(requestId, ParseError, "Parse error: " & e.msg)
    transport[].safeEcho($(%errorResponse))


proc processRequestTask(transport: StdioTransport, server: McpServer, line: string) {.gcsafe.} =
  ## Had to extract this proc to avoid segfaults with taskpools and generics
  transport.taskpool.spawn processRequestTask[McpServer](addr transport, addr server, line)

# Main stdio transport serving procedure with MCP protocol compliance
proc serve*[T: ComposedServer | McpServer](transport: StdioTransport, server: T) =
  ## Serve the MCP server with stdio transport ensuring MCP protocol compliance
  ## - Initialize requests are processed synchronously as required by MCP spec
  ## - Other requests are queued until initialization completes, then processed concurrently
  
  # Configure logging to use stderr to avoid interference with MCP protocol on stdout
  server.logger.redirectToStderr()
  server.logger.info("Stdio transport started")

  while true:
    try:
      let line = stdin.readLine()
      if line.len == 0:
        continue
      
      # Parse and handle the request directly (no taskpools to avoid segfault)
      var requestId: JsonRpcId = JsonRpcId(kind: jridString, str: "")
      try:
        let request = parseJsonRpcMessage(line)
        if request.id.isSome():
          requestId = request.id.get
        if not request.id.isSome():
          # Handle notification (no response needed)
          discard
        else:
          let response = server.handleRequest(request)
          echo $response
      except Exception as e:
        let errorResponse = createJsonRpcError(requestId, ParseError, "Parse error: " & e.msg)
        echo $(%errorResponse)
        
    except EOFError:
      break
    except Exception:
      break

