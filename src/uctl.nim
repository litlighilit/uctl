
import ./uctl/[util, help, units]
import std/cmdline
from std/strutils import formatFloat, FloatFormatMode

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
  proc query(): float =
    let res = exec(subCmd)
    res.chkErr
    res.res
  if subCmd in ["-h", "--help", "-?"]:
    exitWithHelp()
  if argn == 2:
    var sval = paramStr(2)
    let val = parseUnit(sval, query)
    let res = exec(subCmd, val)
    res.chkErr
  else:  # argn == 1
    echo (query() * 100).formatFloat(ffDecimal, 1) & "%"
