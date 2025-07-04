## Pluggable Logging Architecture for NimCP
## Provides a flexible logging system with Chronicles as the default backend

import json, tables, options, times, strutils

type
  LogLevel* = enum
    ## Log severity levels
    llTrace = "trace"
    llDebug = "debug"
    llInfo = "info"
    llWarn = "warn"
    llError = "error"
    llFatal = "fatal"

  LogMessage* = object
    ## Structured log message
    level*: LogLevel
    message*: string
    timestamp*: DateTime
    component*: Option[string]
    requestId*: Option[string]
    context*: Table[string, JsonNode]

  LogHandler* = proc(msg: LogMessage) {.gcsafe, closure.}
    ## Custom log handler function type

  Logger* = ref object
    ## Pluggable logger with configurable backends
    handlers*: seq[LogHandler]
    minLevel*: LogLevel
    enabled*: bool
    component*: Option[string]

# Global logger instance
var globalLogger*: Logger

proc newLogMessage*(level: LogLevel, message: string, 
                   component: Option[string] = none(string),
                   requestId: Option[string] = none(string),
                   context: Table[string, JsonNode] = initTable[string, JsonNode]()): LogMessage =
  ## Create a new log message
  LogMessage(
    level: level,
    message: message,
    timestamp: now(),
    component: component,
    requestId: requestId,
    context: context
  )

proc newLogger*(minLevel: LogLevel = llInfo): Logger =
  ## Create a new logger instance
  Logger(
    handlers: @[],
    minLevel: minLevel,
    enabled: true,
    component: none(string)
  )

proc addHandler*(logger: Logger, handler: LogHandler) =
  ## Add a log handler to the logger
  logger.handlers.add(handler)

proc removeHandler*(logger: Logger, handler: LogHandler) =
  ## Remove a log handler from the logger (simple implementation)
  for i in countdown(logger.handlers.len - 1, 0):
    # Note: This is a simple implementation that removes the first matching handler
    # For a more sophisticated approach, you'd need to track handlers by ID
    logger.handlers.del(i)
    break

proc setMinLevel*(logger: Logger, level: LogLevel) =
  ## Set minimum log level
  logger.minLevel = level

proc setComponent*(logger: Logger, component: string) =
  ## Set component name for all logs from this logger
  logger.component = some(component)

proc enable*(logger: Logger) =
  ## Enable logging
  logger.enabled = true

proc disable*(logger: Logger) =
  ## Disable logging
  logger.enabled = false

proc shouldLog*(logger: Logger, level: LogLevel): bool =
  ## Check if a message should be logged based on level
  if not logger.enabled:
    return false
  return ord(level) >= ord(logger.minLevel)

proc log*(logger: Logger, level: LogLevel, message: string,
          component: Option[string] = none(string),
          requestId: Option[string] = none(string),
          context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log a message with the specified level
  if not logger.shouldLog(level):
    return

  let effectiveComponent = if component.isSome: component else: logger.component
  let logMsg = newLogMessage(level, message, effectiveComponent, requestId, context)

  for handler in logger.handlers:
    try:
      handler(logMsg)
    except Exception:
      # Silently ignore handler failures to prevent logging loops
      discard

# Convenience logging functions
proc trace*(logger: Logger, message: string, component: Option[string] = none(string),
           requestId: Option[string] = none(string),
           context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log a trace message
  logger.log(llTrace, message, component, requestId, context)

proc debug*(logger: Logger, message: string, component: Option[string] = none(string),
           requestId: Option[string] = none(string),
           context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log a debug message
  logger.log(llDebug, message, component, requestId, context)

proc info*(logger: Logger, message: string, component: Option[string] = none(string),
          requestId: Option[string] = none(string),
          context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log an info message
  logger.log(llInfo, message, component, requestId, context)

proc warn*(logger: Logger, message: string, component: Option[string] = none(string),
          requestId: Option[string] = none(string),
          context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log a warning message
  logger.log(llWarn, message, component, requestId, context)

proc error*(logger: Logger, message: string, component: Option[string] = none(string),
           requestId: Option[string] = none(string),
           context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log an error message
  logger.log(llError, message, component, requestId, context)

proc fatal*(logger: Logger, message: string, component: Option[string] = none(string),
           requestId: Option[string] = none(string),
           context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log a fatal message
  logger.log(llFatal, message, component, requestId, context)

# Built-in log handlers

proc consoleHandler*(msg: LogMessage) =
  ## Simple console log handler (outputs to stdout)
  let timestamp = msg.timestamp.format("yyyy-MM-dd HH:mm:ss")
  let levelStr = ($msg.level).toUpper()
  var line = "[$#] [$#] $#" % [timestamp, levelStr, msg.message]
  
  if msg.component.isSome:
    line = "[$#] [$#] [$#] $#" % [timestamp, levelStr, msg.component.get(), msg.message]
  
  if msg.requestId.isSome:
    line.add(" [req:" & msg.requestId.get() & "]")
  
  echo line

proc stderrHandler*(msg: LogMessage) =
  ## Console log handler that outputs to stderr (for stdio transport)
  let timestamp = msg.timestamp.format("yyyy-MM-dd HH:mm:ss")
  let levelStr = ($msg.level).toUpper()
  var line = "[$#] [$#] $#" % [timestamp, levelStr, msg.message]
  
  if msg.component.isSome:
    line = "[$#] [$#] [$#] $#" % [timestamp, levelStr, msg.component.get(), msg.message]
  
  if msg.requestId.isSome:
    line.add(" [req:" & msg.requestId.get() & "]")
  
  stderr.writeLine(line)

proc jsonHandler*(msg: LogMessage) =
  ## JSON structured log handler
  var jsonMsg = newJObject()
  jsonMsg["timestamp"] = %msg.timestamp.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  jsonMsg["level"] = %($msg.level)
  jsonMsg["message"] = %msg.message
  
  if msg.component.isSome:
    jsonMsg["component"] = %msg.component.get()
  
  if msg.requestId.isSome:
    jsonMsg["requestId"] = %msg.requestId.get()
  
  if msg.context.len > 0:
    jsonMsg["context"] = %msg.context
  
  echo $jsonMsg

# Chronicles integration (when available)
when declared(chronicles):
  import chronicles
  
  proc chroniclesHandler*(msg: LogMessage) =
    ## Chronicles log handler
    var ctx = initTable[string, string]()
    
    if msg.component.isSome:
      ctx["component"] = msg.component.get()
    
    if msg.requestId.isSome:
      ctx["requestId"] = msg.requestId.get()
    
    # Convert context to string values for Chronicles
    for key, value in msg.context:
      ctx[key] = $value
    
    case msg.level:
    of llTrace:
      chronicles.trace(msg.message, ctx)
    of llDebug:
      chronicles.debug(msg.message, ctx)
    of llInfo:
      chronicles.info(msg.message, ctx)
    of llWarn:
      chronicles.warn(msg.message, ctx)
    of llError:
      chronicles.error(msg.message, ctx)
    of llFatal:
      chronicles.fatal(msg.message, ctx)

  proc setupChroniclesLogging*(logger: Logger) =
    ## Set up Chronicles as the default logging backend
    logger.addHandler(chroniclesHandler)

else:
  # Fallback when Chronicles is not available
  proc setupChroniclesLogging*(logger: Logger) =
    ## Fallback when Chronicles is not available - use console logging
    logger.addHandler(consoleHandler)

# File log handler
proc fileHandler*(filename: string): LogHandler =
  ## Create a file log handler
  result = proc(msg: LogMessage) =
    let timestamp = msg.timestamp.format("yyyy-MM-dd HH:mm:ss")
    let levelStr = ($msg.level).toUpper()
    var line = "[$#] [$#] $#" % [timestamp, levelStr, msg.message]
    
    if msg.component.isSome:
      line = "[$#] [$#] [$#] $#" % [timestamp, levelStr, msg.component.get(), msg.message]
    
    if msg.requestId.isSome:
      line.add(" [req:" & msg.requestId.get() & "]")
    
    try:
      let file = open(filename, fmAppend)
      file.writeLine(line)
      file.close()
    except IOError:
      # Silently ignore file write errors
      discard

# Global logging convenience functions
proc getGlobalLogger*(): Logger =
  ## Get the global logger instance
  if globalLogger == nil:
    globalLogger = newLogger()
    # Set up default logging with Chronicles if available, otherwise console
    globalLogger.setupChroniclesLogging()
  return globalLogger

proc setGlobalLogger*(logger: Logger) =
  ## Set the global logger instance
  globalLogger = logger

# Global convenience functions
proc trace*(message: string, component: Option[string] = none(string),
           requestId: Option[string] = none(string),
           context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log a trace message using the global logger
  getGlobalLogger().trace(message, component, requestId, context)

proc debug*(message: string, component: Option[string] = none(string),
           requestId: Option[string] = none(string),
           context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log a debug message using the global logger
  getGlobalLogger().debug(message, component, requestId, context)

proc info*(message: string, component: Option[string] = none(string),
          requestId: Option[string] = none(string),
          context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log an info message using the global logger
  getGlobalLogger().info(message, component, requestId, context)

proc warn*(message: string, component: Option[string] = none(string),
          requestId: Option[string] = none(string),
          context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log a warning message using the global logger
  getGlobalLogger().warn(message, component, requestId, context)

proc error*(message: string, component: Option[string] = none(string),
           requestId: Option[string] = none(string),
           context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log an error message using the global logger
  getGlobalLogger().error(message, component, requestId, context)

proc fatal*(message: string, component: Option[string] = none(string),
           requestId: Option[string] = none(string),
           context: Table[string, JsonNode] = initTable[string, JsonNode]()) =
  ## Log a fatal message using the global logger
  getGlobalLogger().fatal(message, component, requestId, context)

# Logger configuration utilities
proc setupDefaultLogging*(level: LogLevel = llInfo, useChronicles: bool = true) =
  ## Set up default logging configuration
  let logger = newLogger(level)
  
  if useChronicles:
    logger.setupChroniclesLogging()
  else:
    logger.addHandler(consoleHandler)
  
  setGlobalLogger(logger)

proc setupFileLogging*(filename: string, level: LogLevel = llInfo) =
  ## Set up file-based logging
  let logger = newLogger(level)
  logger.addHandler(fileHandler(filename))
  setGlobalLogger(logger)

proc setupJSONLogging*(level: LogLevel = llInfo) =
  ## Set up JSON structured logging
  let logger = newLogger(level)
  logger.addHandler(jsonHandler)
  setGlobalLogger(logger)

proc setupStderrLogging*(level: LogLevel = llInfo) =
  ## Set up stderr console logging (for stdio transport)
  let logger = newLogger(level)
  logger.addHandler(stderrHandler)
  setGlobalLogger(logger)