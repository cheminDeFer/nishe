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

let O_RDONLY {.header:"fcntl.h",importc, nodecl.}: cint
let O_WRONLY {.header:"fcntl.h",importc, nodecl.}: cint
let O_CREAT {.header:"fcntl.h",importc, nodecl.}: cint
let S_IRUSR {.header:"fcntl.h",importc, nodecl.}: cint
let S_IWUSR {.header:"fcntl.h",importc, nodecl.}: cint

proc builtinPwd(args: seq[string]) : int=
  echo getCurrentDir().string
  return 0

proc builtinCd(args: seq[string]) : int=
  # TODO too many args and not exist message
  var cdTarget: Path
  if args.len == 1:
    cdTarget = getHomeDir()
  else:
    cdTarget = args[1].Path
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
  # var argvWithNull :array[64, cstring]
  # var leak: int = 0
  # for i, a in enumerate(finalCommand.words):
  #   argvWithNull[i] = a.cstring
  #   leak = i + 1
  # argvWithNull[leak] = cast[cstring](0)

  # if input != 0:
  #   echo "dup2 called"
  #   discard dup2Wrapper(input,0)
  assert(finalCommand.kind == astcommand, fmt"{finalCommand.kind=}")
  assert(finalCommand.words.len > 0 , fmt"{finalCommand.words=}")
  return execWithRedirC(finalCommand,input, -1,-1)




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
    inputFd = openWrapper(ast.redirection.filename, O_RDONLY, 0)
    if inputFd < 0:
      echo fmt"Error: occured while redirection from {ast.redirection.filename} "
      return 1
  of rdErrTo:
    let mode = S_IWUSR or S_IRUSR
    let flags = O_WRONLY or O_CREAT
    errFd = openWrapper(ast.redirection.filename,flags , mode) # TODO learn bitor
    discard ftruncateWrapper(errFd.cint, cast[cint](0))
    if errFd < 0:
      echo fmt"Error: occured while redirection to {ast.redirection.filename} "
      return 1
  of rdTo:
    let flags = O_WRONLY or O_CREAT
    let mode = S_IWUSR or S_IRUSR 
    outPutFd = openWrapper(ast.redirection.filename,flags, mode)
    if outPutFd < 0:
      echo fmt"Error: occured while redirection to {ast.redirection.filename} "
      return 1
    discard ftruncateWrapper(outPutFd.cint, cast[cint](0))
  of rdNo:
    discard
  # echo fmt"LOG: {command=} {arg=} {inputFd=}, {outputFd=}, {errFd=}"
  return execWithRedirCHelper(command,arg,inputFd.cint,outPutFd.cint,errFd.cint)





# proc execWithRedir(ast: Ast, env: StringTableRef = nil, iStream: var Stream, oStream: var Stream ) : int  =
#   assert ast.kind == astcommand, "execWithRedir should be called with astcommandtype"
#   var command:string = ast.words[0]
#   var arg : seq[string]
#   if ast.words.len == 1:
#     arg = @[]
#   else:
#     arg = ast.words[1..ast.words.len-1]
#   if builtinsMap.hasKey(command):
#     return builtinsMap[command](arg)
#   var options  = {poUsePath, poParentStreams}
#   let rd = ast.redirection
#   if rd.kind == rdTo or rd.kind == rdErrTo or rd.kind == rdFrom:
#     options.excl(poParentStreams)
#   var line: string = newStringOfCap(120)
#   var src: Stream
#   var dst: Stream
#   if isNil(iStream):
#     if rd.kind == rdFrom:
#       let fname = rd.filename
#       src = newFileStream(fname, fmRead)
#       if isNil(src):
#         echo fmt"Error: occured while redirection from {fname} "
#         return 1
#   else:
  #   echo "parent returned with {wstatus=}"
#     src = iStream
#   if isNil(oStream):
#     if rd.kind == rdTo or rd.kind == rdErrTo:
#       let fname = rd.filename
#       dst = newFileStream(fname, fmWrite)
#       if isNil(dst):
#         echo fmt"Error: occured while redirection to {fname} "
#         return 1
#   else:
#     dst = oStream



#   # first check redirection streams is valid

#   let p = startProcess(command, args=arg, env=env, options=options)
#   if isNil(oStream):
#     if rd.kind == rdTo:
#       src = outputStream(p)
#     elif rd.kind == rdErrTo:
#       src = errorStream(p)
#     elif rd.kind == rdFrom:
#       dst = inputStream(p)
#   # repetition of  this check is in order to avoid starting process with valid redirection
#   if not (rd.kind == rdNo):
#     while true:
#       if src.readLine(line):
#         dst.write(line)
#         dst.write("\n")
#       elif  not running(p): break
#   # dont know which stream to close
#   if isNil(oStream) and rd.kind == rdTo or rd.kind == rdErrTo:
#     dst.close()
#   elif isNil(iStream) and rd.kind == rdFrom:
#     src.close()
#   let exitCode = waitForExit(p, timeout = -1)
#   close(p)

#   return exitCode

# https://www.reddit.com/r/nim/comments/17v22rq/obtaining_exit_code_standard_output_and_standard/
proc myExec(command: string, args: openArray[string] = [],
            env: StringTableRef = nil, options: set[ProcessOption] = {},
            timeout : int = -1
): (int, string, string) =
  ## wrapper around startProcess, returning exitcode, stdout, stderr.
  ##
  ## warning: assumes utf8 output. Prob want binary read, if not.
  assert false , "this is not gonna used from now on it served its inspirational purpose"
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
