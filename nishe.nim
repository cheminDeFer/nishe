import std/osproc
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
import std/enumerate
import std/appdirs

var variablesMap: Table[string,string] =  {"oldpwd": "" }.toTable

proc builtinPwd(args: seq[string]) : int=
  # this makes this proc not "gcsafe" thus storeable in to builtinsMap w/o type error
  echo "LOG: oldpwd =$1 " % variablesMap["oldpwd"]
  echo getCurrentDir().string
  return 0

proc builtinCd(args: seq[string]) : int =
  # TODO too many args and not exist message
  variablesMap["oldpwd"] = getCurrentDir().string
  var cdTarget: Path
  if args.len == 1:
    cdTarget = getHomeDir()
  else:
    try:
      cdTarget = if args[1] == "-": variablesMap["oldpwd"].Path  else : args[1].Path
    except:
      return 1
  try:
    setCurrentDir(cdTarget)
    return 0
  except:
    return 1

const builtinsMap =  {"pwd": builtinPwd, "cd": builtinCd}.toTable

proc pipeWrapper(fd: array[2,cint]):int  {.header: "<unistd.h>", importc: "pipe".}
proc dup2Wrapper(oldfd:cint,newfd:cint ): int {.header: "<fcntl.h>", importc: "dup2".} 
proc execvpWrapper( file: cstring, argv: array[64,cstring]): int {.header: "<unistd.h>", importc: "execvp".}
proc openWrapper(filename: cstring, flags:cint, mode:cint): int {.header: "<fcntl.h>", importc: "open".} 
proc forkWrapper(): int {.header: "<fcntl.h>", importc: "fork".}
proc closeWrapper(fd:cint): int {.header: "<fcntl.h>", importc: "close".}
proc waitpidWrapper(pid: int, wstatus: ptr cint , options: cint):int  {.header: "<sys/wait.h>", importc: "waitpid".}
proc ftruncateWrapper(fd: cint, length: cint):int  {.header: "<unistd.h>", importc: "ftruncate".}

# proc execWithRedir(ast: Ast, env: StringTableRef = nil, iStream: Stream, oStream:Stream ) : int
proc execWithRedirC(ast:Ast, ci:cint, co:cint,ce:cint ): int
proc execWithRedirCHelper(command:string , argv: seq[string], inputFd: cint, outputFd: cint, errFd: cint) : int
proc execWithPipe(plist : seq[Ast],
env: StringTableRef = nil) : int =
  var input: cint = 0
  var fd : array[2,cint]
  for i,c in enumerate(plist):
    if i == plist.len - 1:
      break;
    discard pipeWrapper(fd)
    result = execWithRedirC(c, input, fd[1], 2.cint)
    discard closeWrapper(fd[1])
    input = fd[0]
  let finalCommand: Ast = plist[plist.len-1]
  assert(finalCommand.kind == astcommand, fmt"{finalCommand.kind=}")
  assert(finalCommand.words.len > 0 , fmt"{finalCommand.words=}")
  return execWithRedirC(finalCommand,input, -1,-1)

# proc execWithPipeNHelper(command:string, argv: seq[string], inFile: File,outFile: File, errFile: File) =
#   let p = startProcess(command,workingDir= ".",
#                   args=argv, env=nil,
#                   options= {poUsePath}) 
#   if  inFile != stdin:
#     p.inputStream.File = inFile
#   # if  outFile != stdout:
#   #   p.outFile = outFile
#   # if  errFile != stderr:
#   #   p.errFile = outFile
#   let exitCode = p.waitForExit
#   return exitCode


proc execWithPipeN(ast:Ast): int =
  discard





proc execWithRedirCHelper(command:string , argv: seq[string], inputFd: cint, outputFd: cint, errFd: cint) : int =
  # echo fmt"LOG: helper called with {command=} {argv=} {inputFd=}, {outputFd=}, {errFd=}"
  var sargv: array[64,cstring]
  var leak: int = 0
  for i, a in enumerate(argv):
    sargv[i] = a.cstring
    leak = i + 1
  sargv[leak] = (cast[cstring](0))
  let pid = forkWrapper()
  if pid == 0:
    if inputFd != 0:
      if dup2Wrapper(inputFd,0) < 0:
        echo "ERROR dup2"
      discard closeWrapper(inputFd)
    if outPutFd != 1:
      if dup2Wrapper(outPutFd,1) < 0:
        echo "ERROR dup2"
      discard closeWrapper(outPutFd)
    if errFd != 2:
      if dup2Wrapper(errFd,2) < 0:
        echo "ERROR dup2"
      discard closeWrapper(errFd)
    if execvpWrapper(command, sargv) < 0:
      quit(1)
  elif pid < 0:
    echo "Error fork"
  else:
    var wstatus: cint = 0
    if waitpidWrapper(pid, addr wstatus, 0.cint) < 0:
      echo "Error waitpid"
    # TODO: fix here for return codes of external apps
    return wstatus


proc execWithRedirC(ast:Ast, ci:cint, co:cint,ce:cint ): int=
  assert ast.kind == astcommand, "execWithRedir should be called with astcommandtype"
  var command:string = ast.words[0]
  var arg : seq[string] = ast.words
  if builtinsMap.hasKey(command):
     return builtinsMap[command](arg)
  var inputFd:int = 0
  var outPutFd: int = 1
  var errFd : int   = 2
  if ci != -1:
    inputFd = ci
  if co != -1:
    outPutFd = co
  if ce != -1:
    errFd = ce

  case ast.redirection.kind
  of rdFrom:
    var f : File
    if open(f, ast.redirection.filename, fmRead) == false:
      echo fmt"Error: occured while redirection to {ast.redirection.filename} "
      return 1
    inputFd = f.getOsFileHandle
  of rdErrTo:
    var f : File
    if open(f, ast.redirection.filename, fmWrite) == false:
      echo fmt"Error: occured while redirection to {ast.redirection.filename} "
      return 1
    errFd = f.getOsFileHandle
  of rdTo:
    var f : File
    if open(f, ast.redirection.filename, fmWrite) == false:
      echo fmt"Error: occured while redirection to {ast.redirection.filename} "
      return 1
    outPutFd = f.getOsFileHandle
    # discard ftruncateWrapper(outPutFd.cint, cast[cint](0))
  of rdNo:
    discard
  # echo fmt"LOG: {command=} {arg=} {inputFd=}, {outputFd=}, {errFd=}"
  return execWithRedirCHelper(command,arg,inputFd.cint,outPutFd.cint,errFd.cint)

proc evalAst( ast: Ast ): int=
  case ast.kind
  of astcmdline:
    result = 0
    for a in ast.lists:
      let exitCode = evalAst(a)
      if exitCode != 0:
        result = exitCode
  of astdandor:
    if ast.op == tkdand:
      if evalAst(ast.lhs) == 0:
        return evalAst(ast.rhs)
    else:
      if evalAst(ast.lhs) != 0:
        return evalAst(ast.rhs)
  of astpipeline:
    return execWithPipe(ast.plists, env= nil)
  of astcommand:
    try:
      return execWithRedirC(ast,-1,-1,-1)
    except OsError as e:
      echo e.msg
      return 127




when isMainModule:
  import std/sugar
  # var source: string = "echo hi; true && echo always > /dev/null"
  # from std/os import paramCount, paramStr
  var parseOnly: bool = false
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
      if parseOnly:
        echo ast
        continue
      let i: int = evalAst(ast)
      if i != 0:
        prompt = fmt"% [{i}] "
      else:
        prompt = "% "
    except ValueError as e:
      echo e.msg

  quit(0)
