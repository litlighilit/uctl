
import std/options
import std/os
import std/paths
from std/strutils import stripLineEnd, parseInt
import std/critbits

const SysClass = Path"/sys/class/"

type
  Accessor = object
    root: Path
    nameCur, nameFull: string  ## subpath based on `root`

  OptAcc = Option[Accessor]


proc readInt(path: string): int =
  var s = readFile(path)
  s.stripLineEnd
  s.parseInt

using self: Accessor
template genGet(attr){.dirty.} =
  proc `path attr`(self): Path = self.root/Path(self.`name attr`)
  proc attr*(self): int = readInt($self.`path attr`)

genGet cur
genGet full

proc `cur=`*(self; val: int) =
  var f = open($self.pathCur, fmWrite)
  f.write val
  f.close()

proc `%=`*(self; per: float) =
  ## set by percent,
  ## 
  ## Does nothing with `mod` !
  let v = int(per * float self.full)
  self.cur = v

proc `%`*(self): float =
  ## get percent
  self.cur / self.full

using pattern: string

proc sysClassPath(pattern): Option[Path] =
  let resPat = ($SysClass / pattern)
  var res: seq[string]
  for i in resPat.walkPattern:
    res.add i
  case res.len
  of 0:
    return
  of 1:
    result = some(Path(res[0]))
  else:
    assert false, "multiply target dir in /sys/class found: " & $res

proc newAccessor(root: Path, nameCur, nameFull: string): Accessor =
  Accessor(root: root, nameCur: nameCur, nameFull: nameFull)
template accPair(fullnameId; pattern: string, nameCur, nameFull): untyped{.dirty.} =
  (
    astToStr(fullnameId)
    ,
    proc (): OptAcc =
      let opt = sysClassPath(pattern)
      if opt.isNone:
        return
      let root = opt.unsafeGet
      some newAccessor(root, nameCur, nameFull)
  )


let
  Key2AccGetter = toCritBitTree [
    accPair(battery, "power_supply/BAT*",        "energy_now", "energy_full"),
    accPair(brightness, "backlight/*_backlight", "brightness", "max_brightness"),
  ]

template loopAvailCmdsByIt*(cb) =
  bind Key2AccGetter, keys
  for it{.inject.} in Key2AccGetter.keys: cb

type
  CmdStatus* = enum
    csSucc = "successful"
    csAmbig = "cmd is ambiguous"
    csUnavail = "cmd is unavailable on your platform"
    csUnknown = "unknown cmd is given"

  CmdExecRes* = object
    case status*: CmdStatus
    of csSucc:
      res*: float
    of csAmbig:
      matches*: seq[string]
    else:
      discard

const DefVal = NaN
proc isDefVal(f: float): bool = f != f

proc exec*(subcmd: string, val: float = DefVal): CmdExecRes =
  var matches: seq[typeof(Key2AccGetter[""])]
  var matchesCmd: seq[string]
  for (k, v) in Key2AccGetter.pairsWithPrefix subcmd:
    matches.add v
    matchesCmd.add k
  case matches.len
  of 0:
    return CmdExecRes(status: csUnknown)
  of 1:
    let opt = matches[0]()
    if opt.isNone:
      return CmdExecRes(status: csUnavail)
    let acc = opt.unsafeGet
    if val.isDefVal:
      result.res = %acc
    else:
      result.res = val
      acc %= val
  else:
    return CmdExecRes(
      status: csAmbig,
      matches: matchesCmd
    )
