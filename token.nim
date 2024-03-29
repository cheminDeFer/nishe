import std/strformat
import std/strutils
type
  TokKind* = enum
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
    tkspace
    tkword
    tklookup
    tkeoi


type Token* =  object
  line: int
  offset: int
  case kind*: TokKind
  of tksinglequotedstr, tkword, tklookup:
    strVal*: string
  else:
    discard


proc `$`(t:Token) : string =
    #echo "LOG: $ for token called"
    if t.kind == tksemicolon:
      return "Token: ';' at offset $1" % $t.offset
    elif t.kind == tkand:
      return "Token: '&' at offset $1" % $t.offset
    elif t.kind == tkdand:
      return "Token: '&&' at offset $1" % $t.offset
    elif t.kind == tkpipe:
      return "Token: '|' at offset $1" % $t.offset
    elif t.kind == tkdor:
      return "Token: '|' at offset $1" % $t.offset
    elif t.kind == tktilde:
      return "Token: '~' at offset $1" % $t.offset
    elif t.kind == tkredirectto:
      return "Token: '>' at offset $1" % $t.offset
    elif t.kind == tkredirectfrom:
      return "Token: '<' at offset $1" % $t.offset
    elif t.kind == tkredirectstderrto:
      return "Token: '2>' at offset $1" % $t.offset
    elif t.kind == tksinglequotedstr:
      return "Token: ''...'' at offset $1" % $t.offset
    elif t.kind == tkspace:
      return "Token: ' ' at offset $1" % $t.offset
    elif t.kind == tkword:
      return "Token: 'word' at offset $1" % $t.offset
    elif t.kind == tklookup:
      return "Token: 'tklookup' at offset $1" % $t.offset
    elif t.kind == tkeoi:
      return "Token: 'EOI' at offset $1" % $t.offset


proc isAtEnd(source: string, index:  int): bool =
  return index >= source.len


proc peek(source: string, index: int): char =
  if (isAtEnd(source, index)):
    return '\0'
  else:
    return source[index]

proc match(source: string, index: var int, expected: char) : bool =
  if peek(source, index)  == expected:
    index += 1
    return true
  else:
    return false


proc quotedString(source: string, index: var int, start: var int): Token =
  while (peek(source, index) != '\'') and not(isAtEnd(source, index)):
    index += 1
  if isAtEnd(source, index):
    raise newException(ValueError,fmt"Unmatched quotes in {start=}")
  result = Token(kind: tksinglequotedstr, str_val: source[start+1 .. index-1], offset:start+1)
  index += 1


proc isCharSpecial(c: char): bool =
  return c in [';','&','\'', '|', ' ', '$']


proc word(source: string, index: var int, start: var int): Token =
  while not( isCharSpecial peek(source, index)  ) and not(isAtEnd(source, index)):
    index += 1
  result = Token(kind: tkword, str_val: source[start .. index-1])

proc scanTok(source : string,  index: var int,  line: var int, start: var int) : Token =
  let c = source[index]
  index += 1
  case c
  of '&':
    if match(source, index, '&'):
      return Token(kind: tkdand,  offset:index)
      
    return Token(kind: tkand,  offset: index)
  of '|':
    if match(source, index, '|'):
      return Token(kind: tkdor,  offset:index)
    return Token(kind: tkpipe,  offset: index)
  of '~':
   return Token(kind: tktilde,  offset: index)

  of ';':
   return Token(kind: tksemicolon,  offset: index)
  of '<':
   return Token(kind: tkredirectfrom,  offset: index)
  of '2':
    if match(source, index, '>'):
      return Token(kind: tkredirectstderrto,  offset:index)
  of '>':
   return Token(kind: tkredirectto,  offset: index)
  of '\'':
    return quotedString(source, index, start )
  of ' ':
    return Token(kind:tkspace,  offset:index)
  of '$':
    if peek(source, index).isCharSpecial:
      raise newException(ValueError, "Error: expected word after $$ got $1" %  $peek(source, index))
    start += 1
    let tmp = word(source, index, start)
    return Token(kind:tklookup,strVal: tmp.strVal, offset:index)

  else:
    return word(source, index, start)

proc tokenise*(source:string) :seq[Token] =
  var line: int = 0
  var index: int = 0
  var start: int = 0
  while not (index >= source.len):
    start = index
    var tmp: Token = scanTok(source, (index), (line), start)
    result.add(tmp)
  result.add(Token(kind:tkeoi,offset: (index)))


  return result

when isMainModule:
  for t in tokenise("this is an list > filename && 'word; this&' "):
      echo t
