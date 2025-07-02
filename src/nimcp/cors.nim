## This module provides helper procedures for generating Cross-Origin Resource
## Sharing (CORS) headers.
##
## CORS is a mechanism that uses additional HTTP headers to tell browsers to give
## a web application running at one origin, access to selected resources from a
## different origin. This is essential for MCP transports that are intended to be
## used by web-based clients, such as those using SSE or WebSockets from a
## browser.
##
## The procedures in this module simplify the creation of common CORS header
## configurations.

import mummy

proc defaultCorsHeaders*(): HttpHeaders =
  ## Returns default CORS headers for MCP transports
  result["Access-Control-Allow-Origin"] = "*"
  result["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
  result["Access-Control-Allow-Headers"] = "Content-Type, Accept, Origin, Authorization"

proc corsHeadersFor*(methods: string): HttpHeaders =
  ## Returns CORS headers with custom allowed methods
  result = defaultCorsHeaders()
  result["Access-Control-Allow-Methods"] = methods

proc corsHeadersFor*(methods: string, headers: string): HttpHeaders =
  ## Returns CORS headers with custom allowed methods and headers
  result = defaultCorsHeaders()
  result["Access-Control-Allow-Methods"] = methods
  result["Access-Control-Allow-Headers"] = headers