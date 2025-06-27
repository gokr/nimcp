## Advanced JSON schema generation and validation for NimCP
## Provides enhanced type support including objects, unions, enums, and optional types

import json, tables, options, macros, typetraits, strutils, sequtils, math
import types

# Enhanced schema generation
type
  SchemaBuilder* = object
    ## Builder for creating complex JSON schemas
    properties: Table[string, JsonNode]
    required: seq[string]
    anyOf: seq[JsonNode]
    enumValues: seq[string]
    schemaType: string
    description: string
    
  SchemaError* = object of CatchableError
    ## Error in schema generation or validation

# Schema builder functions
proc newSchemaBuilder*(schemaType: string = "object"): SchemaBuilder =
  ## Create a new schema builder
  SchemaBuilder(
    properties: initTable[string, JsonNode](),
    required: @[],
    anyOf: @[],
    enumValues: @[],
    schemaType: schemaType
  )

proc addProperty*(builder: var SchemaBuilder, name: string, schema: JsonNode, required: bool = true) =
  ## Add a property to the schema
  builder.properties[name] = schema
  if required:
    builder.required.add(name)

proc addUnionType*(builder: var SchemaBuilder, schema: JsonNode) =
  ## Add a type to a union schema
  builder.anyOf.add(schema)

proc addEnumValue*(builder: var SchemaBuilder, value: string) =
  ## Add an enum value
  builder.enumValues.add(value)

proc setDescription*(builder: var SchemaBuilder, description: string) =
  ## Set schema description
  builder.description = description

proc build*(builder: SchemaBuilder): JsonNode =
  ## Build the final JSON schema
  result = newJObject()
  
  if builder.anyOf.len > 0:
    result["anyOf"] = %builder.anyOf
  elif builder.enumValues.len > 0:
    result["type"] = %"string"
    result["enum"] = %builder.enumValues
  else:
    result["type"] = %builder.schemaType
    
    if builder.schemaType == "object" and builder.properties.len > 0:
      result["properties"] = %builder.properties
      if builder.required.len > 0:
        result["required"] = %builder.required
  
  if builder.description.len > 0:
    result["description"] = %builder.description

# Advanced type to schema conversion
proc nimTypeToAdvancedSchema*(typeExpr: NimNode): JsonNode =
  ## Enhanced type to schema conversion supporting complex types
  case typeExpr.kind:
  of nnkIdent:
    case $typeExpr:
    of "int", "int8", "int16", "int32", "int64":
      return %*{"type": "integer"}
    of "uint", "uint8", "uint16", "uint32", "uint64":
      return %*{"type": "integer", "minimum": 0}
    of "float", "float32", "float64":
      return %*{"type": "number"}
    of "string":
      return %*{"type": "string"}
    of "bool":
      return %*{"type": "boolean"}
    else:
      # Assume custom type - would need runtime type info
      return %*{"type": "object", "description": "Custom type: " & $typeExpr}
      
  of nnkBracketExpr:
    if typeExpr[0].kind == nnkIdent:
      case $typeExpr[0]:
      of "seq":
        return %*{
          "type": "array",
          "items": nimTypeToAdvancedSchema(typeExpr[1])
        }
      of "Option":
        let innerSchema = nimTypeToAdvancedSchema(typeExpr[1])
        return %*{
          "anyOf": [innerSchema, {"type": "null"}]
        }
      of "set":
        return %*{
          "type": "array",
          "uniqueItems": true,
          "items": nimTypeToAdvancedSchema(typeExpr[1])
        }
      of "Table":
        return %*{
          "type": "object",
          "additionalProperties": nimTypeToAdvancedSchema(typeExpr[2])
        }
      else:
        return %*{"type": "object", "description": "Generic type: " & $typeExpr[0]}
        
  of nnkTupleConstr, nnkTupleTy:
    # Tuple - represent as array with fixed length
    var itemSchemas = newJArray()
    for i in 0..<typeExpr.len:
      itemSchemas.add(nimTypeToAdvancedSchema(typeExpr[i]))
    return %*{
      "type": "array",
      "items": itemSchemas,
      "minItems": typeExpr.len,
      "maxItems": typeExpr.len
    }
    
  of nnkObjectTy:
    # Object type - would need field introspection
    return %*{"type": "object", "description": "Object type"}
    
  of nnkEnumTy:
    # Enum type
    var enumValues = newJArray()
    for i in 1..<typeExpr.len:  # Skip first item which is the enum type
      enumValues.add(%($typeExpr[i]))
    return %*{
      "type": "string",
      "enum": enumValues
    }
    
  else:
    return %*{"type": "string", "description": "Fallback for: " & $typeExpr.kind}

# Validation functions
proc validateJsonAgainstSchema*(json: JsonNode, schema: JsonNode): tuple[valid: bool, errors: seq[string]] =
  ## Validate JSON data against a schema
  var errors: seq[string] = @[]
  
  proc validateValue(value: JsonNode, valueSchema: JsonNode, path: string = ""): bool =
    if valueSchema.hasKey("anyOf"):
      # Union type - must match at least one schema
      for unionSchema in valueSchema["anyOf"]:
        if validateValue(value, unionSchema, path):
          return true
      errors.add("Value at " & path & " doesn't match any union type")
      return false
    
    if valueSchema.hasKey("enum"):
      # Enum validation
      if value.kind != JString:
        errors.add("Value at " & path & " must be a string for enum type")
        return false
      let enumValues = valueSchema["enum"].getElems().mapIt(it.getStr())
      if value.getStr() notin enumValues:
        errors.add("Value at " & path & " must be one of: " & enumValues.join(", "))
        return false
      return true
    
    if not valueSchema.hasKey("type"):
      return true  # No type constraint
    
    let expectedType = valueSchema["type"].getStr()
    case expectedType:
    of "string":
      if value.kind != JString:
        errors.add("Value at " & path & " must be a string")
        return false
    of "integer":
      if value.kind != JInt:
        errors.add("Value at " & path & " must be an integer")
        return false
    of "number":
      if value.kind notin {JInt, JFloat}:
        errors.add("Value at " & path & " must be a number")
        return false
    of "boolean":
      if value.kind != JBool:
        errors.add("Value at " & path & " must be a boolean")
        return false
    of "array":
      if value.kind != JArray:
        errors.add("Value at " & path & " must be an array")
        return false
      if valueSchema.hasKey("items"):
        let itemSchema = valueSchema["items"]
        for i, item in value.getElems():
          if not validateValue(item, itemSchema, path & "[" & $i & "]"):
            return false
    of "object":
      if value.kind != JObject:
        errors.add("Value at " & path & " must be an object")
        return false
      
      # Check required properties
      if valueSchema.hasKey("required"):
        for requiredProp in valueSchema["required"]:
          let propName = requiredProp.getStr()
          if not value.hasKey(propName):
            errors.add("Missing required property: " & propName & " at " & path)
            return false
      
      # Validate properties
      if valueSchema.hasKey("properties"):
        let properties = valueSchema["properties"]
        for key, val in value:
          if properties.hasKey(key):
            if not validateValue(val, properties[key], path & "." & key):
              return false
    
    return true
  
  let isValid = validateValue(json, schema)
  return (isValid, errors)

# Object schema generation macro
macro generateObjectSchema*(typeDef: typedesc): untyped =
  ## Generate JSON schema for a custom object type
  let typeImpl = typeDef.getTypeImpl()
  
  result = quote do:
    proc getSchema*(T: typedesc[`typeDef`]): JsonNode =
      var builder = newSchemaBuilder("object")
      # Would need field introspection here
      return builder.build()

# Union type support
template Union*[T: tuple](types: T): typedesc =
  ## Define a union type (compile-time only)
  T

# Enum helpers
proc createEnumSchema*(values: openArray[string], description: string = ""): JsonNode =
  ## Create an enum schema
  var builder = newSchemaBuilder("string")
  for value in values:
    builder.addEnumValue(value)
  if description.len > 0:
    builder.setDescription(description)
  return builder.build()

# Optional type helpers
proc createOptionalSchema*(innerSchema: JsonNode): JsonNode =
  ## Create a schema for an optional type
  return %*{
    "anyOf": [innerSchema, {"type": "null"}]
  }

# Array validation helpers
proc createArraySchema*(itemSchema: JsonNode, minItems: int = 0, maxItems: int = -1): JsonNode =
  ## Create an array schema with constraints
  result = %*{
    "type": "array",
    "items": itemSchema
  }
  if minItems > 0:
    result["minItems"] = %minItems
  if maxItems >= 0:
    result["maxItems"] = %maxItems

# String validation helpers
proc createStringSchema*(minLength: int = 0, maxLength: int = -1, pattern: string = ""): JsonNode =
  ## Create a string schema with constraints
  result = %*{"type": "string"}
  if minLength > 0:
    result["minLength"] = %minLength
  if maxLength >= 0:
    result["maxLength"] = %maxLength
  if pattern.len > 0:
    result["pattern"] = %pattern

# Number validation helpers
proc createNumberSchema*(minimum: float = NaN, maximum: float = NaN): JsonNode =
  ## Create a number schema with constraints
  result = %*{"type": "number"}
  if not minimum.isNaN:
    result["minimum"] = %minimum
  if not maximum.isNaN:
    result["maximum"] = %maximum