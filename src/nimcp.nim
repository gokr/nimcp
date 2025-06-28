## NimCP - Easy Model Context Protocol (MCP) server implementation for Nim
## 
## This module provides a high-level, macro-based API for creating MCP servers
## that integrate seamlessly with LLM applications.

import nimcp/[types, protocol, server, mcpmacros, mummy_transport, websocket_transport, sse_transport, context, schema, resource_templates, logging]

export types, server, protocol, mummy_transport, websocket_transport, sse_transport, context, schema, resource_templates, logging
export mcpmacros.mcpServer, mcpmacros.mcpTool, mcpmacros.mcpResource, mcpmacros.mcpPrompt, mcpmacros.currentMcpServer
export mcpmacros.mcpToolWithContext