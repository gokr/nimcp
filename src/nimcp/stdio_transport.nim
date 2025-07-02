## MCP Stdio Transport implementation using taskpools for concurrent request processing
##
## This module provides the stdio transport implementation for MCP servers.
## It handles JSON-RPC communication over stdin/stdout with concurrent request processing.

import json, locks, strutils, options
import taskpools
import types, protocol, server

# Thread-safe output handling
var stdoutLock: Lock
initLock(stdoutLock)

proc safeEcho(msg: string) =
  withLock stdoutLock:
    echo msg
    stdout.flushFile()

# Global server pointer for taskpools (similar to threadpool approach)
var globalServerPtr: ptr McpServer

# Request processing task for taskpools - uses global pointer to avoid isolation issues
proc processRequestTask(requestLine: string) {.gcsafe.} =
  var requestId: JsonRpcId = JsonRpcId(kind: jridString, str: "")

  try:
    let request = parseJsonRpcMessage(requestLine)

    if request.id.isSome():
      requestId = request.id.get

    if not request.id.isSome():
      globalServerPtr[].handleNotification(request)
    else:
      let response = globalServerPtr[].handleRequest(request)

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
      safeEcho($responseJson)
  except Exception as e:
    let errorResponse = createJsonRpcError(requestId, ParseError, "Parse error: " & e.msg)
    safeEcho($(%errorResponse))

# Main stdio transport serving procedure
proc serve*(server: McpServer) =
  ## Serve the MCP server with stdio transport using modern taskpools
  globalServerPtr = addr server

  while true:
    try:
      let line = stdin.readLine()
      if line.len == 0:
        break

      # Spawn task using taskpools - returns void so no need to track
      server.taskpool.spawn processRequestTask(line)

    except EOFError:
      # Sync all pending tasks before shutdown
      server.taskpool.syncAll()
      break
    except Exception:
      # Sync all pending tasks before shutdown
      server.taskpool.syncAll()
      break

  # Wait for all remaining tasks and shutdown
  server.shutdown()