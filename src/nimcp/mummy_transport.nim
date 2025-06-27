## Mummy HTTP transport for MCP servers
## Integrates fully with existing server.nim mechanisms

import mummy, mummy/routers, json, strutils, strformat, options, tables
import server, types, protocol

type
  TokenValidator* = proc(token: string): bool {.gcsafe.}
  
  AuthConfig* = object
    enabled*: bool
    validator*: TokenValidator
    requireHttps*: bool
    customErrorResponses*: Table[int, string]
  
  MummyTransport* = ref object
    server: McpServer
    router: Router
    httpServer: Server
    port: int
    host: string
    authConfig*: AuthConfig

proc newAuthConfig*(): AuthConfig =
  ## Create a default authentication configuration (disabled)
  AuthConfig(
    enabled: false,
    validator: nil,
    requireHttps: false,
    customErrorResponses: initTable[int, string]()
  )

proc newAuthConfig*(validator: TokenValidator, requireHttps: bool = false): AuthConfig =
  ## Create an enabled authentication configuration with custom validator
  AuthConfig(
    enabled: true,
    validator: validator,
    requireHttps: requireHttps,
    customErrorResponses: initTable[int, string]()
  )

proc newMummyTransport*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()): MummyTransport =
  MummyTransport(
    server: server,
    router: Router(),
    port: port,
    host: host,
    authConfig: authConfig
  )

proc extractBearerToken(request: Request): Option[string] =
  ## Extract Bearer token from Authorization header
  if "Authorization" in request.headers:
    let authHeader = request.headers["Authorization"]
    if authHeader.startsWith("Bearer "):
      return some(authHeader[7..^1].strip())
  return none(string)

proc validateAuthentication(transport: MummyTransport, request: Request): tuple[valid: bool, errorCode: int, errorMsg: string] =
  ## Validate authentication according to MCP specification
  if not transport.authConfig.enabled:
    return (true, 0, "")
  
  # Check HTTPS requirement
  if transport.authConfig.requireHttps:
    let proto = if "X-Forwarded-Proto" in request.headers: request.headers["X-Forwarded-Proto"] else: "http"
    if not proto.startsWith("https"):
      return (false, 400, "HTTPS required for authentication")
  
  # Extract Bearer token
  let tokenOpt = extractBearerToken(request)
  if tokenOpt.isNone:
    return (false, 401, "Authorization required: Bearer token missing")
  
  let token = tokenOpt.get()
  if token.len == 0:
    return (false, 400, "Malformed authorization: empty token")
  
  # Validate token using configured validator
  if transport.authConfig.validator == nil:
    return (false, 500, "Internal error: no token validator configured")
  
  try:
    if not transport.authConfig.validator(token):
      return (false, 401, "Authorization required: token invalid")
  except:
    return (false, 500, "Internal error: token validation failed")
  
  return (true, 0, "")

proc handleMcpRequest(transport: MummyTransport, request: Request) {.gcsafe.} =
  var headers: HttpHeaders
  headers["Access-Control-Allow-Origin"] = "*"
  headers["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
  headers["Access-Control-Allow-Headers"] = "Content-Type, Accept, Origin, Authorization"
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

proc serve*(transport: MummyTransport) =
  ## Start the HTTP server and serve MCP requests
  transport.setupRoutes()
  transport.httpServer = newServer(transport.router)
  
  echo fmt"Starting MCP HTTP server at http://{transport.host}:{transport.port}"
  echo "Press Ctrl+C to stop the server"
  
  transport.httpServer.serve(Port(transport.port), transport.host)

proc runHttp*(server: McpServer, port: int = 8080, host: string = "127.0.0.1", authConfig: AuthConfig = newAuthConfig()) =
  ## Convenience function to run an MCP server over HTTP
  let transport = newMummyTransport(server, port, host, authConfig)
  transport.serve()