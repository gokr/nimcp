## MCP Stdio Transport implementation using taskpools for concurrent request processing
##
## This module provides the stdio transport implementation for MCP servers.
## It handles JSON-RPC communication over stdin/stdout with concurrent request processing.

import json, locks, options
import taskpools, cpuinfo
import types, protocol, server

type StdioTransport* = ref object
  ## Stdio transport implementation for MCP servers
  taskpool: Taskpool
  stdoutLock: Lock

proc newStdioTransport*(numThreads: int = 0): StdioTransport =
  ## Args:
  ##   numThreads: Number of worker threads (0 = auto-detect)
  new(result)
  let threads = if numThreads > 0: numThreads else: countProcessors()
  result.taskpool = Taskpool.new(numThreads = threads)
  initLock(result.stdoutLock)

proc safeEcho(transport: StdioTransport, msg: string) =
  ## Thread-safe output handling
  withLock transport.stdoutLock:
    echo msg
    stdout.flushFile()

# Request processing task for taskpools - uses global pointer to avoid isolation issues
proc processRequestTask(transport: ptr StdioTransport, server: ptr McpServer, requestLine: string) {.gcsafe.} =
  var requestId: JsonRpcId = JsonRpcId(kind: jridString, str: "")
  try:
    let request = parseJsonRpcMessage(requestLine)
    if request.id.isSome():
      requestId = request.id.get
    if not request.id.isSome():
      server[].handleNotification(request)
    else:
      let response = server[].handleRequest(request)

      # Create JSON response manually for thread safety
      var responseJson = newJObject()
      responseJson["jsonrpc"] = %response.jsonrpc
      responseJson["id"] = %response.id
      if response.result.isSome:
        responseJson["result"] = response.result.get
      if response.error.isSome:
        let errorObj = newJObject()
        errorObj["code"] = %response.error.get.code
        errorObj["message"] = %response.error.get.message
        if response.error.get.data.isSome:
          errorObj["data"] = response.error.get.data.get
        responseJson["error"] = errorObj
      transport[].safeEcho($responseJson)
  except Exception as e:
    let errorResponse = createJsonRpcError(requestId, ParseError, "Parse error: " & e.msg)
    transport[].safeEcho($(%errorResponse))

# Main stdio transport serving procedure
proc serve*(transport: StdioTransport, server: McpServer) =
  ## Serve the MCP server with stdio transport using modern taskpools
  while true:
    try:
      let line = stdin.readLine()
      if line.len == 0:
        break
      # Spawn task using taskpools - returns void so no need to track
      transport.taskpool.spawn processRequestTask(addr transport, addr server, line)
    except EOFError:
      # Sync all pending tasks before shutdown
      transport.taskpool.syncAll()
      break
    except Exception:
      # Sync all pending tasks before shutdown
      transport.taskpool.syncAll()
      break

  # Wait for all remaining tasks and shutdown
   
  if transport.taskpool != nil:
    transport.taskpool.syncAll()
    transport.taskpool.shutdown()
  server.shutdown()