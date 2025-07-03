## Common utilities for HTTP-based transports (Mummy, WebSocket, SSE)

import mummy, mummy/routers, json, options, tables, strutils
import server, types, protocol, auth, cors

type
  HttpServerBase* = ref object
    router*: Router
    httpServer*: Server
    port*: int
    host*: string
    authConfig*: AuthConfig
    allowedOrigins*: seq[string]

proc newHttpServerBase*(port: int, host: string, authConfig: AuthConfig, allowedOrigins: seq[string]): HttpServerBase =
  var defaultOrigins = if allowedOrigins.len == 0: @["http://localhost", "https://localhost", "http://127.0.0.1", "https://127.0.0.1"] else: allowedOrigins
  result = HttpServerBase(
    router: Router(),
    port: port,
    host: host,
    authConfig: authConfig,
    allowedOrigins: defaultOrigins
  )

proc validateOrigin*(base: HttpServerBase, request: Request): bool =
  if "Origin" notin request.headers: return true
  let origin = request.headers["Origin"]
  origin in base.allowedOrigins

proc validateAuthentication*(base: HttpServerBase, request: Request): tuple[valid: bool, errorCode: int, errorMsg: string] =
  validateRequest(base.authConfig, request)

proc handleCors*(request: Request) =
  let headers = corsHeadersFor("GET, POST, OPTIONS", "Content-Type, Accept, Origin, Authorization, Upgrade, Connection")
  request.respond(204, headers, "")

proc startServer*(base: HttpServerBase, wsHandler: WebSocketHandler = nil) =
  base.httpServer = newServer(base.router, wsHandler)
  echo &"Starting MCP server at http://{base.host}:{base.port}"
  if base.authConfig.enabled:
    echo "Authentication: Bearer token required"
  echo "Press Ctrl+C to stop the server"
  base.httpServer.serve(Port(base.port), base.host)

proc stopServer*(base: HttpServerBase) =
  if base.httpServer != nil:
    base.httpServer.close()
