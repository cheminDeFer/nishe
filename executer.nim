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


proc builtinPwd() : int=
  echo getCurrentDir().string
  return 0

const builtinsMap =  {"pwd": builtinPwd}.toTable

proc evalAst( ast: Ast ): int=
  case ast.kind
  of astcmdline:
    result = 0
    for a in ast.lists:
      if evalAst(a) > 0:
        result = 1
  of astdandor:
    if ast.op == tkdand:
      if evalAst(ast.lhs) == 0:
        return evalAst(ast.rhs)
    else:
      if evalAst(ast.lhs) != 0:
        return evalAst(ast.rhs)
    # assert false, "TODO: pipeline eval in evalAst not implemented yet"
  of astpipeline:
    assert false, "TODO: pipeline eval in evalAst not implemented yet"
  of astcommand:
    var command:string = ast.words[0]
    if builtinsMap.hasKey(command):
      return builtinsMap[command]()
    var options  = {poUsePath, poParentStreams}
    if ast.redirection.kind == rdNo:
      options.incl( poStdErrToStdOut)
    else:
      assert false, "redirection not implemented yet"

    if ast.words.len == 1:
      try:
        let arg: array[0,string] = []


        let v= myExec(command, args=arg, #workingDir=".",
                 env=nil,     options= options)
        return v[0]
      except OsError as e:
        echo "Error: executing $1" % command
        return 1
    else:
      let arg = ast.words[1..ast.words.len-1]
      try:
        let v= myExec(command, args=arg, #workingDir=".",
                 env=nil,     options= options)
        return v[0]
      except OsError as e:
        echo fmt"Error: executing {command=}, {arg=}"
        return 1






when isMainModule:
  import std/sugar
  # var source: string = "echo hi; true && echo always > /dev/null"
  var source: string
  var prompt: string = "> "
  while true:
    stdout.write(prompt)
    if not(stdin.readLine(source)):
      break

    var toks: seq[Token] = tokenise(source)
    # for t in toks:
    #   echo t
    var p : Parser = Parser(tokens:toks)
    var ast : Ast = p.parseCmdLine()
    # echo ast
    let i = evalAst(ast)
    if i > 0:
      prompt = fmt"> [{i}] "
    else:
      prompt = "> "
  quit(0)
