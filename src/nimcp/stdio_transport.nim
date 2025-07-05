## MCP Stdio Transport implementation using taskpools for concurrent request processing
##
## This module provides the stdio transport implementation for MCP servers.
## It handles JSON-RPC communication over stdin/stdout with concurrent request processing.

import json, locks, options
import taskpools, cpuinfo
import types, protocol, server, composed_server, logging

type 
  StdioTransport* = ref object
    ## Stdio transport implementation for MCP servers
    taskpool: Taskpool
    stdoutLock: Lock
    mcpTransport: McpTransport  # Persistent transport object

proc newStdioTransport*(numThreads: int = 0): StdioTransport =
  ## Args:
  ##   numThreads: Number of worker threads (0 = auto-detect)
  new(result)
  let threads = if numThreads > 0: numThreads else: countProcessors()
  result.taskpool = Taskpool.new(numThreads = threads)
  initLock(result.stdoutLock)
  result.mcpTransport = McpTransport(kind: tkStdio, capabilities: {})

proc safeEcho(transport: StdioTransport, msg: string) =
  ## Thread-safe output handling
  withLock transport.stdoutLock:
    echo msg
    stdout.flushFile()

# Request processing task for taskpools
proc processRequestTask[T](transport: ptr StdioTransport, server: ptr T, requestLine: string) {.gcsafe.} =
  var requestId: JsonRpcId = JsonRpcId(kind: jridString, str: "")
  try:
    let request = parseJsonRpcMessage(requestLine)
    if request.id.isSome():
      requestId = request.id.get
    if not request.id.isSome():
      # Use persistent transport object for notifications
      server[].handleNotification(transport[].mcpTransport, request)
    else:
      let response = server[].handleRequest(request)
      transport[].safeEcho($response)
  except Exception as e:
    let errorResponse = createJsonRpcError(requestId, ParseError, "Parse error: " & e.msg)
    transport[].safeEcho($(%errorResponse))


proc processRequestTask(transport: StdioTransport, server: McpServer, line: string) {.gcsafe.} =
  ## Had to extract this proc to avoid segfaults with taskpools and generics
  transport.taskpool.spawn processRequestTask[McpServer](addr transport, addr server, line)

# Main stdio transport serving procedure
proc serve*[T: ComposedServer | McpServer](transport: StdioTransport, server: T) =
  ## Serve the MCP server with stdio transport
  
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
          # Create transport instance for context access
          let capabilities = {tcUnicast}  # Stdio supports unicast only
          let mcpTransport = McpTransport(kind: tkStdio, capabilities: capabilities)
          let response = server.handleRequest(mcpTransport, request)
          echo $response
      except Exception as e:
        let errorResponse = createJsonRpcError(requestId, ParseError, "Parse error: " & e.msg)
        echo $(%errorResponse)
        
    except EOFError:
      break
    except Exception:
      break

