## Enhanced calculator example demonstrating Phase 1 improvements
## - Context-aware tools with progress tracking
## - Structured error handling
## - Advanced type support
## - Middleware for logging and validation
## - Request cancellation and timeout

import ../src/nimcp
import json, tables, strutils, times, math, options

# Create an enhanced MCP server
mcpServer("enhanced-calculator", "1.0.0"):
  
  # Enable context logging for debugging
  mcpServerInstance.enableContextLogging(true)
  # Set request timeout to 10 seconds
  mcpServerInstance.setRequestTimeout(10000)
  
  # Register logging middleware
  mcpMiddleware("logger", 1, 
    beforeReq = proc(ctx: McpRequestContext, req: JsonRpcRequest): JsonRpcRequest {.gcsafe.} =
      ctx.logMessage("info", "Processing request: " & req.`method`)
      return req
    ,
    afterResp = proc(ctx: McpRequestContext, resp: JsonRpcResponse): JsonRpcResponse {.gcsafe.} =
      ctx.logMessage("info", "Request completed in " & $ctx.getElapsedTime().inMilliseconds & "ms")
      return resp
  )
  
  # Context-aware tool with progress tracking
  mcpToolWithContext:
    proc complexCalculation(ctx: McpRequestContext, iterations: int, baseValue: float): string =
      ## Perform a complex calculation with progress tracking
      if iterations <= 0:
        raise newException(ValueError, "Iterations must be positive")
      
      var result = baseValue
      
      for i in 1..iterations:
        # Check for cancellation
        ctx.ensureNotCancelled()
        
        # Report progress
        let progress = i.float / iterations.float
        ctx.reportProgress("Computing iteration " & $i & "/" & $iterations, progress)
        
        # Simulate some work
        result = result * 1.1 + sin(i.float)
        
        # Add some metadata
        if i mod 100 == 0:
          ctx.setMetadata("checkpoint_" & $i, %{"value": %result, "iteration": %i})
      
      return "Complex calculation result: " & $result.formatFloat(ffDecimal, 6)
  
  # Regular tool with enhanced error handling
  mcpTool:
    proc divide(a: float, b: float): string =
      ## Divide two numbers with proper error handling
      if b == 0.0:
        raise newException(DivByZeroError, "Division by zero is not allowed")
      
      let result = a / b
      return "Division result: " & $result
  
  # Tool with advanced type support (using optional and array types)
  mcpTool:
    proc calculateStats(numbers: seq[float]): string =
      ## Calculate statistics for a list of numbers
      if numbers.len == 0:
        return "No numbers provided"
      
      let sum = numbers.foldl(a + b, 0.0)
      let mean = sum / numbers.len.float
      let variance = numbers.mapIt((it - mean) * (it - mean)).foldl(a + b, 0.0) / numbers.len.float
      let stdDev = sqrt(variance)
      
      return "Statistics: mean=" & $mean & ", stddev=" & $stdDev & ", count=" & $numbers.len
  
  # Context-aware resource with progress tracking
  mcpResourceWithContext("math://constants", "Mathematical Constants", "Important mathematical constants"):
    proc getConstants(ctx: McpRequestContext, uri: string): string =
      ctx.reportProgress("Loading mathematical constants", 0.5)
      
      let constants = %*{
        "pi": PI,
        "e": E,
        "phi": (1.0 + sqrt(5.0)) / 2.0,  # Golden ratio
        "sqrt2": sqrt(2.0),
        "ln2": ln(2.0)
      }
      
      ctx.reportProgress("Constants loaded", 1.0)
      return $constants
  
  # Resource template example (basic implementation)
  mcpResourceTemplate("/calculations/{id}", "Calculation Results", "Get results of previous calculations"):
    proc getCalculationResult(uri: string, params: Table[string, string]): string =
      let calcId = params.getOrDefault("id", "unknown")
      return "Result for calculation " & calcId & ": (cached result would be here)"
  
  # Enhanced prompt with context
  mcpPromptWithContext("math_tutor", "Math Tutoring Prompt", @[
    McpPromptArgument(name: "topic", description: some("Math topic to explain"), required: some(true)),
    McpPromptArgument(name: "level", description: some("Difficulty level"), required: some(false))
  ]):
    proc generateTutorPrompt(ctx: McpRequestContext, name: string, args: Table[string, JsonNode]): seq[McpPromptMessage] =
      let topic = args.getOrDefault("topic", %"algebra").getStr()
      let level = args.getOrDefault("level", %"beginner").getStr()
      
      ctx.logMessage("info", "Generating math tutor prompt for topic: " & topic & ", level: " & level)
      
      let systemMsg = McpPromptMessage(
        role: System,
        content: createTextContent("You are a helpful math tutor. Explain " & topic & " at a " & level & " level.")
      )
      
      let userMsg = McpPromptMessage(
        role: User,
        content: createTextContent("Please explain " & topic & " with examples.")
      )
      
      return @[systemMsg, userMsg]

# Main execution
when isMainModule:
  echo "Starting Enhanced Calculator MCP Server"
  echo "Features:"
  echo "- Context-aware tools with progress tracking"
  echo "- Structured error handling"
  echo "- Middleware for logging"
  echo "- Request timeout and cancellation"
  echo "- Advanced type support"
  echo ""
  
  try:
    runServer(StdioTransport())
  except KeyboardInterrupt:
    echo "Server stopped by user"
  except Exception as e:
    echo "Server error: " & e.msg