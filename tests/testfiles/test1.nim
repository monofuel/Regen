proc hello(name: string) =
  echo "Hello, " & name
  
proc goodbye(name: string) =
  echo "Goodbye, " & name

when isMainModule:
  hello("World")
  goodbye("World") 