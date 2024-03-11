#{".strictDefs"}
import std/strformat
type
  TokKind = enum
    tksemicolon
    tkand
    tkdand
    tkpipe
    tkdor
    tktilde
    tkredirectto
    tkredirectfrom
    tkredirectstderrto
    tksinglequotedstr
    tkerror

type Token =  object
  line: int
  offset: int
  case kind: TokKind
  of tksinglequotedstr:
    str_val: string
  of tkerror:
    err_msg:string
  else:
    val: string# = "TODO: fixme with some null"



const t:Token = Token(kind : tkpipe, val:"0")

proc peek(source: string, index: int): char

proc match(source: string, index: var int, expected: char) : bool =
  if peek(source, index)  == expected:
    index += 1
    return true
  else:
    return false

proc isAtEnd(source: string, index:  int): bool =
  return index >= source.len

proc peek(source: string, index: int): char =
  if (isAtEnd(source, index)):
    return '\0'
  else:
    return source[index]

proc quotedString(source: string, index: var int, start: var int): Token =
  while (peek(source, index) != '\'') and not(isAtEnd(source, index)):
    index += 1
  if isAtEnd(source, index):
    result = Token(kind: tkerror, errmsg: fmt"Unmatched quotes in {start=}")
  echo fmt"{start=}, {index=}"
  result = Token(kind: tksinglequotedstr, str_val: source[start+1 .. index-1])
  index += 1
    
#this is an command ; print 'unqo | w' 
    
    
proc scanTok(source : string,  index: var int,  line: var int, start: var int) : Token =
  let c = source[index]
  index += 1
  case c
  of '&':
    if match(source, index, '&'):
      return Token(kind: tkdand, val:"", offset:index)
      
    return Token(kind: tkand, val: "", offset: index)
  of '|':
    if match(source, index, '|'):
      return Token(kind: tkdor, val:"", offset:index)
    return Token(kind: tkpipe, val: "", offset: index)
  of '~':
   return Token(kind: tktilde, val: "", offset: index)

  of ';':
   return Token(kind: tksemicolon, val: "", offset: index)
  of '<':
   return Token(kind: tkredirectfrom, val: "", offset: index)
  of '2':
    if match(source, index, '>'):
      return Token(kind: tkredirectstderrto, val:"", offset:index)
  of '>':
   return Token(kind: tkredirectto, val: "", offset: index)
  of '\'':
    return quotedString(source, index, start )
    
    

  else:
    var errmsg: string = fmt"Unknown char <{c}>"
    return Token(kind: tkerror, err_msg: errmsg , offset:index)

proc tokenise(source:string) :seq[Token] =
  var line: int = 0
  var index: int = 0
  var start: int = 0
  while not (index >= source.len):
    start = index
    var tmp: Token = scanTok(source, (index), (line), start)
    result.add(tmp)


  return result

var candidate: string =  readline(stdin)
var sourcey: string
echo "candid len=", candidate.len
if (candidate.len > 2):
  echo "gonna parse stding"
  sourcey = candidate
  echo "<", sourcey, ">"
else:
  echo "not gonna parse stding"
  sourcey = "&& (hello"
let toks:seq[Token] =  tokenise(sourcey)
for tok in toks:
  echo tok

#proc parser(tokens: seq[Token]) : ast? =
