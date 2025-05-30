
from std/parseutils import parseFloat

proc myParseFloat(sval: openArray[char]): float =
  let L = parseFloat(sval, result)
  if L != sval.len or L == 0:
    quit(
      "bad argument, expect a float (may suffixed with `%`), but got " & $sval
    )

template endsWith(s: openArray[char], c: char): bool =
  ## strutils.endsWith, but works with openArray[char]
  s.len != 0 and s[^1] == c

proc parseMayPercent(sval: openArray[char]): float =
  if sval.endsWith '%':
    myParseFloat(sval.toOpenArray(0, sval.len-2)) / 100
  else:
    myParseFloat(sval)


proc parseUnit*(sval: openArray[char], queryCur: proc(): float): float =
  let first = sval[0]
  template op(o): untyped = o(queryCur(), parseMayPercent(sval.toOpenArray(1, sval.len-1)))
  case first
  of 'x': op `*`
  of '/': op `/`
  of '+', '-':
    queryCur() + sval.parseMayPercent
  else:
    sval.parseMayPercent
