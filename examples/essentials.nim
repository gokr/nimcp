import ../src/nimcp, ../src/nimcp/stdio_transport

let server = mcpServer("essentials-server", "1.0.0"):
  
  mcpTool:
    proc add(a: float, b: float): string =
      ## Add two numbers
      ## - a: First number
      ## - b: Second number  
      return $(a + b)
  
  mcpTool:
    proc echo(message: string): string =
      ## Echo a message back
      ## - message: The message to echo
      return message

when isMainModule:
  let transport = newStdioTransport()
  transport.serve(server)