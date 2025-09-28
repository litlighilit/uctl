
import ./uctl/[util, help]
import std/cmdline

proc exitWithHelp() =
  priHelp()
  quit()

proc chkErr(res: CmdExecRes) =
  case res.status
  of csUnavail, csUnknown, csNeverSet, csPerm:
    quit $res.status
  of csAmbig:
    quit $res.status & ". Available matches: " & $res.matches
  of csSucc:
    discard

when isMainModule:
  let argn = paramCount()
  if argn == 0:
    exitWithHelp()
  let subCmd = paramStr(1)
  proc query(): string =
    let res = exec(subCmd)
    res.chkErr
    res.res
  if subCmd in ["-h", "--help", "-?"]:
    exitWithHelp()
  if argn == 2:
    let sval = paramStr(2)
    let res = exec(subCmd, sval)
    res.chkErr
  else:  # argn == 1
    echo query()
