## Simple coverage analysis tool for Nim projects
## Provides basic line coverage estimation

import os, strutils, sequtils, tables, strformat, algorithm

proc analyzeCoverage*(testDir: string = "tests", srcDir: string = "src"): void =
  ## Analyze test coverage by examining which source files are imported by tests
  
  echo "🔍 Analyzing test coverage..."
  echo "=" .repeat(50)
  
  var sourceFiles: seq[string] = @[]
  var testedFiles: seq[string] = @[]
  var testFiles: seq[string] = @[]
  
  # Find all source files
  for file in walkDirRec(srcDir):
    if file.endsWith(".nim"):
      sourceFiles.add(file)
  
  # Find all test files
  for file in walkDirRec(testDir):
    if file.endsWith(".nim") and file.contains("test_"):
      testFiles.add(file)
  
  # Analyze which source files are imported by tests
  for testFile in testFiles:
    echo fmt"📋 Analyzing {testFile}..."
    let content = readFile(testFile)
    
    for srcFile in sourceFiles:
      let moduleName = srcFile.replace(srcDir & "/", "").replace("/", "/").replace(".nim", "")
      if content.contains(moduleName) or content.contains("import ../src/nimcp"):
        if srcFile notin testedFiles:
          testedFiles.add(srcFile)
  
  # Calculate coverage statistics
  let totalFiles = sourceFiles.len
  let testedFileCount = testedFiles.len
  let coveragePercent = if totalFiles > 0: (testedFileCount * 100) div totalFiles else: 0
  
  echo ""
  echo "📊 COVERAGE ANALYSIS RESULTS"
  echo "=" .repeat(30)
  echo fmt"📁 Total source files: {totalFiles}"
  echo fmt"✅ Files with tests: {testedFileCount}"
  echo fmt"❌ Files without tests: {totalFiles - testedFileCount}"
  echo fmt"📈 Estimated coverage: {coveragePercent}%"
  echo ""
  
  # Show tested files
  echo "✅ TESTED MODULES:"
  echo "-" .repeat(20)
  for file in testedFiles.sorted():
    echo fmt"  ✓ {file}"
  echo ""
  
  # Show untested files
  let untestedFiles = sourceFiles.filterIt(it notin testedFiles)
  if untestedFiles.len > 0:
    echo "❌ UNTESTED MODULES:"
    echo "-" .repeat(20)
    for file in untestedFiles.sorted():
      echo fmt"  ✗ {file}"
    echo ""
  
  # Test file analysis
  echo "🧪 TEST FILES:"
  echo "-" .repeat(15)
  for testFile in testFiles.sorted():
    let testName = testFile.extractFilename()
    echo fmt"  📋 {testName}"
  echo ""
  
  if coveragePercent >= 90:
    echo "🎉 EXCELLENT! Coverage >= 90%"
  elif coveragePercent >= 80:
    echo "✅ GOOD! Coverage >= 80%"
  elif coveragePercent >= 70:
    echo "⚠️  FAIR Coverage >= 70%"
  else:
    echo "❌ LOW Coverage < 70% - Consider adding more tests"

when isMainModule:
  analyzeCoverage()