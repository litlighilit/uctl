
import ./uctl/[util, help]
import std/cmdline
from std/strutils import parseFloat, startsWith, endsWith, formatFloat, FloatFormatMode
from std/parseutils import parseFloat

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

proc query(subCmd: string): float =
  let res = exec(subCmd)
  res.chkErr
  res.res

proc parseMayPercent(sval: string): float =
  if sval.endsWith '%':
    let n = parseFloat(sval.toOpenArray(0, sval.len-2), result)
    if n == 0:
      #raise newException(ValueError,
      quit(
        "bad argument, expect a float (may suffixed with `%`), but got " & sval
      )
    result / 100
  else:
    parseFloat sval

when isMainModule:
  let argn = paramCount()
  if argn == 0:
    exitWithHelp()
  let subCmd = paramStr(1)
  if subCmd in ["-h", "--help", "-?"]:
    exitWithHelp()
  if argn == 2:
    var sval = paramStr(2)
    let rel = sval[0] in "+-"
    var val = sval.parseMayPercent
    if rel:
      val += subCmd.query
    let res = exec(subCmd, val)
    res.chkErr
  else:  # argn == 1
    echo (subCmd.query * 100).formatFloat(ffDecimal, 1) & "%"
