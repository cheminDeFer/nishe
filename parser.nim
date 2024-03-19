# cmdline = and_or terminator
# and_or = pipeline { ( "&&" | "||" pipeline) }
# pipeline = command { "|" command }
# command = simple command |
# redirection = (">"|"2>"|"<")  filename
# terminator = ";" | "&" | "\n"
import token
import std/strutils
import std/strformat
type Parser* = ref object
  index: int # TODO: learn how to hide implementation details
  tokens*: seq[Token]

# proc makeParser*(tokens:seq[Token]): Parser =
#   result.tokens = tokens
#   result.index = 0
#   return result


type RedirectionKind* = enum
  rdNo
  rdFrom
  rdTo
  rdErrTo

type Redirection* = object
  case   kind* :RedirectionKind
  of rdNo:
    dont:char
  else:
    filename*: string

type AstKind = enum
  astcmdline
  astdandor
  astpipeline
  astcommand
type Ast* = ref object
  inBackGround: bool
  case kind*: AstKind
  of astcmdline:
    lists* : seq[Ast]
  of astdandor:
    op*: TokKind
    lhs*: Ast
    rhs*: Ast
  of astpipeline:
    lhsp*: Ast
    rhsp*:  Ast
  of astcommand:
    words*: seq[string]
    redirection*: Redirection




proc consumeToken(self:Parser): Token =
  result = self.tokens[self.index]
  self.index += 1
  return result

proc peekToken(self: Parser): Token =
  return self.tokens[self.index]
proc matchToken(self:Parser, expected: Token): bool =
  if self.peekToken.kind == expected.kind:
    self.index += 1
    return true
  else:
    return false

proc parsePipeLine(self: Parser): Ast
proc parseCommand(self: Parser): Ast
proc parseRedirection(self: Parser): Redirection
proc parseAndOr(self: Parser): Ast
proc parseCmdLine*(self:Parser): Ast =
  result = Ast(kind:astcmdline)
  while  self.peekToken.kind != tkeoi:
    var t: Token  = self.peekToken
    if t.kind == tksemicolon:
      discard self.consumeToken
      continue
    elif t.kind == tkand:
      discard self.consumeToken
      result.inBackGround = true
      continue
    result.lists.add(self.parseAndOr)
  return result


proc parseAndOr(self: Parser): Ast  =
  result = self.parsePipeLine
  while true:
    case (self.peekToken.kind):
    of tkdand:
      discard self.consumeToken
      return Ast(kind:astdandor,lhs: result, rhs: self.parsePipeLine, op:tkdand)
    of tkdor:
      discard self.consumeToken
      return Ast(kind:astdandor,lhs: result, rhs: self.parsePipeLine, op:tkdand)
    else:
      return result
proc parsePipeLine(self: Parser): Ast =
  result = self.parseCommand
  while true:
    case self.peekToken.kind
    of tkpipe:
      discard self.consumeToken
      return Ast(kind:astpipeline, lhsp:result,rhsp: self.parseCommand)
    else:
      return result

proc parseCommand(self:Parser): Ast =
  result = Ast(kind:astcommand)
  while true:
    var t = self.peekToken
    if t.kind == tkword or t.kind == tksinglequotedstr:
      result.words.add(self.consumeToken.str_val)
    elif t.kind == tkspace:
      discard self.consumeToken
    elif t.kind in @[ tkredirectfrom, tkredirectstderrto, tkredirectto]:
      result.redirection = self.parseRedirection
      return result
    else:
      break

  return result
proc parseRedirection(self: Parser): Redirection=
  if self.peekToken.kind == tkredirectfrom:
    discard self.consumeToken
    while self.peekToken.kind == tkspace:
      discard self.consumeToken
    if self.peekToken.kind != tkword and self.peekToken.kind != tksinglequotedstr :
      raise newException(ValueError, "nishe: expected word or singlequotedstr got $1" % $self.peekToken)
    else:
      result = Redirection(kind: rdFrom, filename:self.consumeToken.str_val)
  elif self.peekToken.kind == tkredirectto:
    discard self.consumeToken
    while self.peekToken.kind == tkspace:
      discard self.consumeToken
    if self.peekToken.kind != tkword and self.peekToken.kind != tksinglequotedstr :
      raise newException(ValueError, "nishe: expected word or singlequotedstr got $1" % $self.peekToken)
    else:
      result = Redirection(kind: rdTo, filename:self.consumeToken.str_val)
  elif self.peekToken.kind == tkredirectstderrto:
    discard self.consumeToken
    while self.peekToken.kind == tkspace:
      discard self.consumeToken
    if self.peekToken.kind != tkword and self.peekToken.kind != tksinglequotedstr :
      raise newException(ValueError, "nishe: expected word or singlequotedstr got $1" % $self.peekToken)
    else:
      result = Redirection(kind: rdErrTo, filename:self.consumeToken.str_val)
  else:
    raise



proc `$`*(a: Ast): string =
  case a.kind
  of astcmdline:
    result = "Ast: (\n" & $a.lists & ")\n"
  of astdandor:
    var v:string
    if a.op == tkdand:
      v = " && "
    elif a.op == tkdor:
      v = " || "
    else:
      assert false, "unreachable"
    result = "(" & $a.lhs & v & $a.rhs & ")"
  of astcommand:
    result = "cmd: " & $a.words & "\n"
  of astpipeline:
    result = $a.lhs & "|" & $a.rhs
  return result





when isMainModule:
  import std/sugar
  var source: string = "echo hi; true && echo always > /dev/null"
  dump source
  var toks: seq[Token] = tokenise(source)
  # for t in toks:
  #   echo t
  var p : Parser = Parser(tokens:toks, index:0)
  var ast : Ast = p.parseCmdLine
  echo ast






