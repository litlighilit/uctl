
import ./uctl/[util, help]
import std/cmdline
from std/strutils import parseFloat, endsWith, formatFloat, FloatFormatMode

proc exitWithHelp() =
  priHelp()
  quit()

proc chkErr(res: CmdExecRes) =
  case res.status
  of csUnavail, csUnknown, csNeverSet:
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
  if subCmd in ["-h", "--help", "-?"]:
    exitWithHelp()
  if argn == 2:
    var sval = paramStr(2)
    let val = if sval.endsWith '%':
      sval.setLen sval.len - 1
      sval.parseFloat / 100
    else:
      sval.parseFloat  
    let res = exec(subCmd, val)
    res.chkErr
  else:  # argn == 1
    let res = exec(subCmd)
    res.chkErr
    echo (res.res * 100).formatFloat(ffDecimal, 1) & "%"
