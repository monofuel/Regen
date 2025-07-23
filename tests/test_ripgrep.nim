import unittest, strutils
import ../src/fraggy

suite "Ripgrep Search Tests":
  var index: FraggyIndex
  
  setup:
    # Create an index of the test files
    index = newFraggyIndex(fraggy_folder, "tests/testfiles", @[".nim", ".txt"])
  
  test "Basic pattern search":
    let results = ripgrepSearch(index, "hello")
    check results.len > 0
    check results[0].lineContent.contains("hello")
    check results[0].lineNumber > 0
  
  test "Case sensitive search":
    let results1 = ripgrepSearch(index, "hello", caseSensitive = true)
    let results2 = ripgrepSearch(index, "HELLO", caseSensitive = true)
    check results1.len > 0
    check results2.len == 0  # Should not find uppercase HELLO
  
  test "Case insensitive search":
    let results1 = ripgrepSearch(index, "hello", caseSensitive = false)
    let results2 = ripgrepSearch(index, "HELLO", caseSensitive = false)
    check results1.len > 0
    check results2.len > 0  # Should find both hello and HELLO variants
  
  test "Regex pattern search":
    let results = ripgrepSearch(index, r"proc \w+\(")
    check results.len >= 2  # Should find function definitions
    for result in results:
      check result.lineContent.contains("proc ")
  
  test "Pattern not found":
    let results = ripgrepSearch(index, "nonexistentpattern")
    check results.len == 0
  
  test "Empty pattern":
    let results = ripgrepSearch(index, "")
    # Empty pattern should match all lines
    check results.len > 0
  
  test "Invalid regex pattern":
    let results = ripgrepSearch(index, "[invalid")
    check results.len == 0  # Should handle invalid regex gracefully
  
  test "Max results limit":
    let results = ripgrepSearch(index, ".", maxResults = 5)
    check results.len <= 5
  
  test "Match position tracking":
    let results = ripgrepSearch(index, "hello")
    check results.len > 0
    let firstMatch = results[0]
    check firstMatch.matchStart >= 0
    check firstMatch.matchEnd >= firstMatch.matchStart
    let matchText = firstMatch.lineContent[firstMatch.matchStart..firstMatch.matchEnd]
    check matchText == "hello"
  
  test "Search in single file":
    let results = ripgrepSearchInFile("tests/testfiles/test1.nim", "hello")
    check results.len > 0
    check results[0].lineContent.contains("hello")
    check results[0].lineNumber > 0
  
  test "Search in nonexistent file":
    let results = ripgrepSearchInFile("nonexistent.txt", "test")
    check results.len == 0
  
  test "Multiple matches in same line":
    let results = ripgrepSearchInFile("tests/testfiles/multitest.txt", "hello")
    check results.len == 1  # One line with multiple matches
    check results[0].lineContent.strip() == "hello world hello again"
  
  test "Line number accuracy":
    let results = ripgrepSearchInFile("tests/testfiles/linetest.txt", "target")
    check results.len == 1
    check results[0].lineNumber == 3
    check results[0].lineContent == "target line"

echo "Running ripgrep tests..." 