#{".strictDefs"}
import std/strformat

import token
import parser

when isMainModule:
  import std/sugar
  var source: string = "echo hi; true && echo always > /dev/null"
  dump source
  var toks: seq[Token] = tokenise(source)
  # for t in toks:
  #   echo t
  var p : Parser = Parser(tokens:toks)
  var ast : Ast = p.parseCmdLine()
  echo ast
