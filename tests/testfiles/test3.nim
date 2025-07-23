import os, strutils

const VERSION = "1.0.0"

type
  User = object
    name: string
    age: int

proc createUser(name: string, age: int): User =
  result = User(name: name, age: age) 