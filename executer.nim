import std/osproc
import std/sugar
import std/strutils
import std/strformat
import std/paths
import std/tables
import std/strtabs
import std/streams
import system
import token
import parser
import std/dirs

proc execWithRedir(command: string, args: openArray[string] = [],
  env: StringTableRef = nil, options: set[ProcessOption] = {}, rd: Redirection) : int =
  let fname = rd.filename
  var line: string = newStringOfCap(120)
  var src: Stream
  var dst: Stream
  # first check redirection streams is valid
  if rd.kind == rdTo or rd.kind == rdErrTo:
    dst = newFileStream(fname, fmWrite)
    if isNil(dst):
      echo fmt"Error: occured while redirection to {fname} "
      return 1
  elif rd.kind == rdFrom:
    src = newFileStream(fname, fmRead)
    if isNil(src):
      echo fmt"Error: occured while redirection from {fname} "
      return 1

  let p = startProcess(command, args=args, env=env, options=options)
  # repetition of  this check is in order to avoid starting process with valid redirection
  if rd.kind == rdTo:
    src = outputStream(p)
  elif rd.kind == rdErrTo:
    src = errorStream(p)
  elif rd.kind == rdFrom:
    dst = inputStream(p)
  while true:
    if src.readLine(line):
      dst.write(line)
      dst.write("\n")
    elif  not running(p): break
  # dont know which stream to close
  if rd.kind == rdTo or rd.kind == rdErrTo:
    dst.close()
  elif rd.kind == rdFrom:
    src.close()
  let exitCode = waitForExit(p, timeout = -1)
  close(p)

  return exitCode

# https://www.reddit.com/r/nim/comments/17v22rq/obtaining_exit_code_standard_output_and_standard/
proc myExec(command: string, args: openArray[string] = [],
            env: StringTableRef = nil, options: set[ProcessOption] = {},
            timeout : int = -1
): (int, string, string) =
  ## wrapper around startProcess, returning exitcode, stdout, stderr.
  ##
  ## warning: assumes utf8 output. Prob want binary read, if not.

  var
    outputStr: string = ""
    errorStr: string = ""
    line: string = newStringOfCap(120)

  let p = startProcess(command, args=args, env=env, options=options)
  if not(poParentStreams in options):
    let (outSm, errorSm) = (outputStream(p), errorStream(p))

    while true:
        # FIXME: converts CR-LF to LF.
        if outSm.readLine(line):
            outputStr.add(line)
            outputStr.add("\n")
        elif  not running(p): break

    while true:
        # FIXME: converts CR-LF to LF.
        if errorSm.readLine(line):
          errorStr.add(line)
          errorStr.add("\n")
        elif not running(p): break

  let exitCode = waitForExit(p, timeout = timeout)
  close(p)

  return (exitCode, outputStr, errorStr)


proc builtinPwd(args: seq[string]) : int=
  echo getCurrentDir().string
  return 0

proc builtinCd(args: seq[string]) : int=
  # TODO too many args and not exist message
  try:
    setCurrentDir(args[0].Path)
    return 0
  except:
    return 1

const builtinsMap =  {"pwd": builtinPwd, "cd": builtinCd}.toTable

proc evalAst( ast: Ast ): int=
  case ast.kind
  of astcmdline:
    result = 0
    for a in ast.lists:
      let exitCode = evalAst(a) 
      if exitCode> 0:
        result = exitCode
  of astdandor:
    if ast.op == tkdand:
      if evalAst(ast.lhs) == 0:
        return evalAst(ast.rhs)
    else:
      if evalAst(ast.lhs) != 0:
        return evalAst(ast.rhs)
  of astpipeline:
    assert false, "TODO: pipeline eval in evalAst not implemented yet"
  of astcommand:
    var command:string = ast.words[0]
    var arg : seq[string]
    if ast.words.len == 1:
      arg = @[]
    else:
      arg = ast.words[1..ast.words.len-1]
    if builtinsMap.hasKey(command):
      return builtinsMap[command](arg)
    var options  = {poUsePath, poParentStreams}
    if ast.redirection.kind == rdTo or ast.redirection.kind == rdErrTo or ast.redirection.kind == rdFrom:
      options.excl(poParentStreams)
      try:
        return execWithRedir(command, args=arg, env=nil, options=options, rd=ast.redirection)
      except OsError as e:
        echo e.msg
        return 127
    else:
      discard

    try:
      let v= myExec(command, args=arg, #workingDir=".",
               env=nil,     options= options)
      return v[0]
    except OsError as e:
      echo "Error: executing $1" % command
      return 1






when isMainModule:
  import std/sugar
  # var source: string = "echo hi; true && echo always > /dev/null"
  var source: string
  var prompt: string = "% "
  while true:
    stdout.write(prompt)
    if not(stdin.readLine(source)):
      break

    var toks: seq[Token] = tokenise(source)
    # for t in toks:
    #   echo t
    var p : Parser = Parser(tokens:toks)
    var ast:Ast
    try:
      ast= p.parseCmdLine()
      # echo ast
      let i: int = evalAst(ast)
      if i > 0:
        prompt = fmt"% [{i}] "
      else:
        prompt = "% "
    except ValueError as e:
      echo e.msg

  quit(0)
