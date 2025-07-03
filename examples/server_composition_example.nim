## Example demonstrating Server Composition and Mounting in NimCP
## Shows how to compose multiple MCP servers together

import ../src/nimcp, json, options, tables, sequtils
import ../src/nimcp/composed_server

# Calculator service
proc addTool(args: JsonNode): McpToolResult =
  let a = args["a"].getFloat()
  let b = args["b"].getFloat()
  return McpToolResult(
    content: @[McpContent(
      `type`: "text",
      kind: TextContent,
      text: "Result: " & $(a + b)
    )]
  )

proc multiplyTool(args: JsonNode): McpToolResult =
  let x = args["x"].getFloat()
  let y = args["y"].getFloat()
  return McpToolResult(
    content: @[McpContent(
      `type`: "text", 
      kind: TextContent,
      text: "Result: " & $(x * y)
    )]
  )

# File service
proc readFileTool(args: JsonNode): McpToolResult =
  let filename = args["filename"].getStr()
  return McpToolResult(
    content: @[McpContent(
      `type`: "text",
      kind: TextContent,
      text: "Content of " & filename & ": (simulated file content)"
    )]
  )

proc listFilesTool(args: JsonNode): McpToolResult =
  let directory = args.getOrDefault("directory").getStr(".")
  return McpToolResult(
    content: @[McpContent(
      `type`: "text",
      kind: TextContent,
      text: "Files in " & directory & ": file1.txt, file2.txt, config.json"
    )]
  )

# User service
proc getUserTool(args: JsonNode): McpToolResult =
  let userId = args["id"].getStr()
  return McpToolResult(
    content: @[McpContent(
      `type`: "text",
      kind: TextContent,
      text: """{"id": """ & userId & """, "name": "User """ & userId & """, "active": true}"""
    )]
  )

when isMainModule:
  echo "=== Server Composition Example ==="
  
  # Create individual service servers
  let calculatorServer = newMcpServer("calculator-service", "1.0.0")
  let fileServer = newMcpServer("file-service", "1.0.0")  
  let userServer = newMcpServer("user-service", "1.0.0")
  
  # Register tools in calculator service
  calculatorServer.registerTool(
    McpTool(
      name: "add",
      description: some("Add two numbers"),
      inputSchema: parseJson("""{"type": "object", "properties": {"a": {"type": "number"}, "b": {"type": "number"}}, "required": ["a", "b"]}""")
    ),
    addTool
  )
  
  calculatorServer.registerTool(
    McpTool(
      name: "multiply", 
      description: some("Multiply two numbers"),
      inputSchema: parseJson("""{"type": "object", "properties": {"x": {"type": "number"}, "y": {"type": "number"}}, "required": ["x", "y"]}""")
    ),
    multiplyTool
  )
  
  # Register tools in file service
  fileServer.registerTool(
    McpTool(
      name: "read_file",
      description: some("Read a file"),
      inputSchema: parseJson("""{"type": "object", "properties": {"filename": {"type": "string"}}, "required": ["filename"]}""")
    ),
    readFileTool
  )
  
  fileServer.registerTool(
    McpTool(
      name: "list_files",
      description: some("List files in directory"),
      inputSchema: parseJson("""{"type": "object", "properties": {"directory": {"type": "string"}}}""")
    ),
    listFilesTool
  )
  
  # Register tools in user service
  userServer.registerTool(
    McpTool(
      name: "get_user",
      description: some("Get user by ID"),
      inputSchema: parseJson("""{"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}""")
    ),
    getUserTool
  )
  
  # Create composed server
  let apiGateway = newComposedServer("api-gateway", "1.0.0")
  
  # Mount services with different prefixes
  apiGateway.mountServerAt("/calc", calculatorServer, some("calc_"))
  apiGateway.mountServerAt("/files", fileServer, some("file_"))
  apiGateway.mountServerAt("/users", userServer, some("user_"))
  
  echo "✓ Created composed server with mounted services:"
  echo "  - Calculator service at /calc with prefix 'calc_'"
  echo "  - File service at /files with prefix 'file_'"
  echo "  - User service at /users with prefix 'user_'"
  echo ""
  
  # Demonstrate tool routing
  echo "Tool routing demonstration:"
  
  # Find mount points for prefixed tools
  let calcMount = apiGateway.findMountPointForTool("calc_add")
  if calcMount.isSome:
    let mount = calcMount.get()
    echo "✓ Found mount point for 'calc_add': " & mount.path & " (prefix: " & mount.prefix.get("none") & ")"
  
  let fileMount = apiGateway.findMountPointForTool("file_read_file")
  if fileMount.isSome:
    let mount = fileMount.get()
    echo "✓ Found mount point for 'file_read_file': " & mount.path & " (prefix: " & mount.prefix.get("none") & ")"
  
  let userMount = apiGateway.findMountPointForTool("user_get_user")
  if userMount.isSome:
    let mount = userMount.get()
    echo "✓ Found mount point for 'user_get_user': " & mount.path & " (prefix: " & mount.prefix.get("none") & ")"
  
  echo ""
  
  # Show mount point information
  echo "Mount points information:"
  let mountInfo = apiGateway.getMountedServerInfo()
  for path, info in mountInfo.pairs:
    echo "  " & path & ":"
    echo "    Server: " & info["serverName"].getStr() & " v" & info["serverVersion"].getStr()
    echo "    Tools: " & $info["toolCount"].getInt()
    if info.hasKey("prefix"):
      echo "    Prefix: " & info["prefix"].getStr()
  
  echo ""
  
  # Demonstrate prefix stripping
  echo "Prefix handling:"
  echo "- stripPrefix('calc_add', some('calc_')) = '" & stripPrefix("calc_add", some("calc_")) & "'"
  echo "- addPrefix('add', some('calc_')) = '" & addPrefix("add", some("calc_")) & "'"
  echo "- stripPrefix('no_prefix', none(string)) = '" & stripPrefix("no_prefix", none(string)) & "'"
  
  echo ""
  
  # Show unmounting
  echo "Unmounting demonstration:"
  let unmounted = apiGateway.unmountServer("/files")
  echo "✓ Unmounted /files service: " & $unmounted
  
  echo "Remaining mount points: " & $apiGateway.listMountPoints().mapIt(it.path)
  
  echo ""
  echo "🎯 Server Composition example completed!"
  echo "This demonstrates mounting multiple servers with routing and prefixes."