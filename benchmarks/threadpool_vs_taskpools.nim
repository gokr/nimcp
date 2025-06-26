## Performance benchmark comparing deprecated threadpool vs modern taskpools
## This benchmark measures throughput, latency, and resource usage

import ../src/nimcp/[server, taskpool_server, types, protocol], json, options, times, strutils, os

# Shared tool definition for both servers
let benchTool = McpTool(
  name: "compute",
  description: some("Perform a simple computation"),
  inputSchema: %*{
    "type": "object",
    "properties": {
      "iterations": {"type": "integer", "description": "Number of iterations to compute"}
    },
    "required": ["iterations"]
  }
)

proc computeHandler(args: JsonNode): McpToolResult =
  let iterations = args["iterations"].getInt()
  var sum = 0
  for i in 1..iterations:
    sum += i * i
  return McpToolResult(content: @[createTextContent("Computed sum: " & $sum)])

proc benchmarkThreadpool(numRequests: int): float =
  ## Benchmark the old threadpool-based server
  echo "Benchmarking threadpool server..."
  let server = newMcpServer("threadpool-bench", "1.0.0")

  # Initialize the server
  let initRequest = JsonRpcRequest(
    jsonrpc: "2.0",
    id: some(JsonRpcId(kind: jridInt, num: 0)),
    `method`: "initialize",
    params: some(%*{
      "protocolVersion": "2024-11-05",
      "capabilities": {"tools": {}}
    })
  )
  discard server.handleRequest(initRequest)

  server.registerTool(benchTool, computeHandler)

  let startTime = cpuTime()
  
  # Simulate multiple requests
  for i in 1..numRequests:
    let request = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: i)),
      `method`: "tools/call",
      params: some(%*{
        "name": "compute",
        "arguments": {"iterations": 1000}
      })
    )
    
    discard server.handleRequest(request)
  
  let endTime = cpuTime()
  return endTime - startTime

proc benchmarkTaskpools(numRequests: int): float =
  ## Benchmark the new taskpools-based server
  echo "Benchmarking taskpools server..."
  let server = newTaskpoolMcpServer("taskpools-bench", "1.0.0", numThreads = 4)

  # Initialize the server
  let initRequest = JsonRpcRequest(
    jsonrpc: "2.0",
    id: some(JsonRpcId(kind: jridInt, num: 0)),
    `method`: "initialize",
    params: some(%*{
      "protocolVersion": "2024-11-05",
      "capabilities": {"tools": {}}
    })
  )
  discard server.handleRequest(initRequest)

  server.registerTool(benchTool, computeHandler)

  let startTime = cpuTime()
  
  # Simulate multiple requests
  for i in 1..numRequests:
    let request = JsonRpcRequest(
      jsonrpc: "2.0",
      id: some(JsonRpcId(kind: jridInt, num: i)),
      `method`: "tools/call",
      params: some(%*{
        "name": "compute",
        "arguments": {"iterations": 1000}
      })
    )
    
    discard server.handleRequest(request)
  
  server.shutdown()
  let endTime = cpuTime()
  return endTime - startTime

proc main() =
  echo "MCP Server Performance Benchmark"
  echo "================================="
  echo ""
  
  let numRequests = 1000
  echo "Running ", numRequests, " requests on each server type..."
  echo ""
  
  # Benchmark threadpool
  let threadpoolTime = benchmarkThreadpool(numRequests)
  echo "Threadpool server: ", threadpoolTime.formatFloat(ffDecimal, 4), " seconds"
  echo "Throughput: ", (numRequests.float / threadpoolTime).formatFloat(ffDecimal, 2), " requests/second"
  echo ""
  
  # Benchmark taskpools
  let taskpoolsTime = benchmarkTaskpools(numRequests)
  echo "Taskpools server: ", taskpoolsTime.formatFloat(ffDecimal, 4), " seconds"
  echo "Throughput: ", (numRequests.float / taskpoolsTime).formatFloat(ffDecimal, 2), " requests/second"
  echo ""
  
  # Calculate improvement
  let improvement = ((threadpoolTime - taskpoolsTime) / threadpoolTime) * 100
  if improvement > 0:
    echo "Taskpools is ", improvement.formatFloat(ffDecimal, 1), "% faster than threadpool"
  else:
    echo "Threadpool is ", (-improvement).formatFloat(ffDecimal, 1), "% faster than taskpools"
  
  echo ""
  echo "Note: This benchmark measures single-threaded performance."
  echo "Real-world concurrent performance differences may vary."

when isMainModule:
  main()
