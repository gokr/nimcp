## Mummy HTTP transport for MCP servers
## Integrates fully with existing server.nim mechanisms

import mummy, mummy/routers, json, strutils, strformat, options, tables
import server, types, protocol
import auth, cors  # Import shared modules

type
  MummyTransport* = ref object
    server: McpServer
    router: Router
    httpServer: Server
    port: int
    host: string
    authConfig*: AuthConfig

proc newMummyTransport*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()): MummyTransport =
  MummyTransport(
    server: server,
    router: Router(),
    port: port,
    host: host,
    authConfig: authConfig
  )
proc validateAuthentication(transport: MummyTransport, request: Request): tuple[valid: bool, errorCode: int, errorMsg: string] =
  ## Validate authentication using shared auth module
  validateRequest(transport.authConfig, request)
proc handleMcpRequest(transport: MummyTransport, request: Request) {.gcsafe.} =
  var headers = corsHeadersFor("POST, GET, OPTIONS")
  headers["Content-Type"] = "application/json"
  
  # Authentication validation (skip for OPTIONS requests)
  if request.httpMethod != "OPTIONS":
    let authResult = validateAuthentication(transport, request)
    if not authResult.valid:
      let errorMsg = if authResult.errorCode in transport.authConfig.customErrorResponses:
                      transport.authConfig.customErrorResponses[authResult.errorCode]
                    else:
                      authResult.errorMsg
      request.respond(authResult.errorCode, headers, errorMsg)
      return
  
  case request.httpMethod:
    of "OPTIONS":
      request.respond(204, headers, "")
      
    of "GET":
      # Return server info for GET requests
      let info = %*{
        "server": {
          "name": transport.server.serverInfo.name,
          "version": transport.server.serverInfo.version
        },
        "transport": "http",
        "capabilities": transport.server.capabilities
      }
      request.respond(200, headers, $info)
      
    of "POST":
      try:
        if request.body.len == 0:
          let errorResponse = createJsonRpcError(
            JsonRpcId(kind: jridString, str: ""), 
            InvalidRequest, 
            "Empty request body"
          )
          request.respond(400, headers, $(%errorResponse))
          return
        
        # Parse the JSON-RPC request using the existing protocol parser
        let jsonRpcRequest = parseJsonRpcMessage(request.body)
        
        # Use the existing server's request handler
        let response = transport.server.handleRequest(jsonRpcRequest)
        
        # Only send a response if it's not empty (i.e., not a notification)
        if response.id.kind != jridString or response.id.str != "":
          # Custom JSON serialization to exclude null fields (same as stdio transport)
          var responseJson = newJObject()
          responseJson["jsonrpc"] = %response.jsonrpc
          responseJson["id"] = %response.id
          if response.result.isSome():
            responseJson["result"] = response.result.get()
          if response.error.isSome():
            responseJson["error"] = %response.error.get()
          
          request.respond(200, headers, $responseJson)
        else:
          # For notifications, just return 204 No Content
          request.respond(204, headers, "")
          
      except JsonParsingError as e:
        let errorResponse = createParseError(details = e.msg)
        request.respond(400, headers, $(%errorResponse))
      except Exception as e:
        let errorResponse = createInternalError(JsonRpcId(kind: jridString, str: ""), e.msg)
        request.respond(500, headers, $(%errorResponse))
        
    else:
      request.respond(405, headers, "Method not allowed")

proc setupRoutes(transport: MummyTransport) =
  # Handle all MCP requests on the root path
  transport.router.get("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(request))
  transport.router.post("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(request))
  transport.router.options("/", proc(request: Request) {.gcsafe.} = transport.handleMcpRequest(request))

proc start*(transport: MummyTransport) =
  ## Start the HTTP server and serve MCP requests
  transport.setupRoutes()
  transport.httpServer = newServer(transport.router)
  
  echo fmt"Starting MCP HTTP server at http://{transport.host}:{transport.port}"
  echo "Press Ctrl+C to stop the server"
  
  transport.httpServer.serve(Port(transport.port), transport.host)

proc runHttp*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()) =
  ## Convenience function to run an MCP server over HTTP
  let transport = newMummyTransport(server, port, host, authConfig)
  transport.start()

# Clean API overloads that hide the casting  
proc setTransport*(server: McpServer, transport: MummyTransport) =
  ## Set HTTP transport with clean API (casting handled internally)
  server.setHttpTransport(cast[pointer](transport))

proc getTransport*(server: McpServer, transportType: typedesc[MummyTransport]): MummyTransport =
  ## Get HTTP transport with clean API (casting handled internally)
  let transportPtr = server.getHttpTransportPtr()
  if transportPtr != nil:
    return cast[MummyTransport](transportPtr)
  else:
    return nil