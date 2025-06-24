## NimCP - Easy Model Context Protocol (MCP) server implementation for Nim
## 
## This module provides a high-level, macro-based API for creating MCP servers
## that integrate seamlessly with LLM applications.

import nimcp/[types, protocol, server, mcpmacros]

export types, server, protocol
export mcpmacros.mcpServer, mcpmacros.mcpTool, mcpmacros.mcpResource, mcpmacros.mcpPrompt