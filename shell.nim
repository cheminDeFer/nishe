#{".strictDefs"}
import std/strformat
import token
var candidate: string =  readline(stdin)
var sourcey: string
echo "candid len=", candidate.len
if (candidate.len > 2):
  echo "gonna parse stding"
  sourcey = candidate
else:
  echo "not gonna parse stding"
  sourcey = "echo hi > filename ; printf '%s\\n' '&&' && ls"
echo "<", sourcey, ">"
let toks:seq[Token] =  tokenise(sourcey)
for tok in toks:
  echo tok

type Parser = ref object
  index: int
  tokens: seq[Token]

  
  
type RedirectionKind = enum
  rdFrom
  rdTo
  rdErrTo
  rdNo

type Redirection = object
  kind :RedirectionKind
  filename: string
type Word = object
  val: string  


       
       
proc consumeToken(self:Parser): Token =
  result = self.tokens[self.index]
  self.index += 1
  return result

proc peekToken(self: Parser): Token =
  return self.tokens[self.index]
  
proc matchToken(self:Parser, expected: Token): bool =
  if self.peekToken().kind == expected.kind:
    self.index += 1
    return true
  else:
    return false

proc parser(self:Parser): Tree =
  t: Token = consumeToken()
  self.parseList()
  if self.peekToken().kind not in @{tksemicolon, tkand}:
    raise newException(Myerror, "list should end with ';' '\n' '&'")
    

var parser: Parser = Parser(tokens: toks, index:0) 
echo parser.tokens
