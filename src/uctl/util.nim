
static:assert defined(linux), "This module is only for Linux platform"
import std/options
import std/os
import std/paths
from std/strutils import stripLineEnd, parseInt, parseFloat
import std/critbits
import std/macros

const SysClass* = Path"/sys/class/"
when (NimMajor, NimMinor, NimPatch) > (2, 1, 1):
  export paths.`$`
else:
  proc `$`*(p: Path): string {.inline.} = string(p)

type
  Accessor = ref object of RootObj
    writable: bool

  PathAccessor = ref object of Accessor
    root: Path
    nameCur, nameFull: string  ## subpath based on `root`
  PathFbAccessor = ref object of PathAccessor
    nameCurPercentFallback: string
  

template notImpl = doAssert false, "not implemented"
template emptyn: NimNode = newEmptyNode()
macro parNotImpl(def) =
  result = newStmtList()
  var
    parParams = def.params.copyNimTree
    parPragmas = def.pragma.copyNimTree
  parParams[1][1] = bindSym"Accessor"
  let parName = def[0]
  var parImpl = def.kind.newTree(
    parName, emptyn, emptyn,
    parParams, parPragmas, emptyn, bindSym"notImpl")
  parImpl.addPragma ident"base"
  result.add parImpl
  result.add def

template read[T](t: typedesc[T]; path: string): T =
  var s = readFile(path)
  s.stripLineEnd
  `parse t` s

using self: PathAccessor

template path[T: PathAccessor](self: T, attr: untyped): Path = self.root/Path(self.`name attr`)
template genGet(attr; T=int, Self=PathAccessor){.dirty.} =
  proc attr*(self: Self): T = read(T, $self.path(attr))

genGet cur
genGet full
genGet curPercentFallback, float, PathFbAccessor

const NeverWriteErrMsg = "the value cannot be set"
type
  PermissionError* = object of OSError

const PermErrMsg* = "No enough permission. you may need to rerun via `sudo` or root"
proc `cur=`*(self; val: int) =
  assert self.writable, NeverWriteErrMsg
  var f: File
  try:
    f = open($self.path(cur), fmWrite)
  except IOError:
    raise newException(PermissionError, PermErrMsg)
  f.write val
  f.close()

method `%=`*(self; per: float){.parNotImpl.} =
  ## set by percent,
  ## 
  ## Does nothing with `mod` !
  let v = int(per * float self.full)
  self.cur = v

method `%`*(self): float{.parNotImpl.} = self.cur / self.full
method `%`*(self: PathFbAccessor): float =
  ## get percent
  try:
    procCall(%PathAccessor(self))
  except IOError:
    self.curPercentFallback / 100

using patterns: openArray[string]

proc sysClassPath(subdir: string, patterns): Option[Path] =
  let resPatPre = ($SysClass / subdir)
  var res: seq[string]
  for pat in patterns:
    let resPat = resPatPre / pat
    for i in resPat.walkPattern:
      res.add i
  case res.len
  of 0:
    return
  of 1:
    result = some(Path(res[0]))
  else:
    assert false, "multiply target dir in " & $SysClass & " found: " & $res

proc newPathAccessor(root: Path, nameCur, nameFull: string): Accessor =
  PathAccessor(root: root, nameCur: nameCur, nameFull: nameFull, writable: true)
proc newPathAccessor(root: Path, nameCur, nameFull, nameCurPercentFallback: string): Accessor =
  assert nameCurPercentFallback != ""
  PathFbAccessor(root: root, nameCur: nameCur, nameFull: nameFull, nameCurPercentFallback: nameCurPercentFallback)

macro genAccPair(args: untyped, prcBody: untyped) =
  let untyp = ident"untyped"
  var params = @[untyp]
  let arg1 = ident"fullnameId"
  params.add newIdentDefs(arg1, untyp)
  for def in args:
    params.add:
      case def.kind
      of nnkExprColonExpr: newIdentDefs(def[0], def[1])
      of nnkIdent: newIdentDefs(def, untyp)
      else: raise newException(ValueError, "expect ident or ident: type, but got " & $def.kind)
  let body = nnkTupleConstr.newTree(
    newCall(bindSym"astToStr", arg1),
    newProc(params=[bindSym"Accessor"], body=prcBody)
  )
  result = newProc(ident"accPair", params, body, procType=nnkTemplateDef)
  result.addPragma ident"dirty"
  # template accPair(fullnameId; *<args>){.dirty.} = (astToStr(fullnameId), proc (): Accessor = <prcBody>)

template genSysClassPathGetter(root; subdir, patterns) =
  let opt = sysClassPath(subdir, patterns)
  if opt.isNone:
    return  # this exit the callee function
  let root = opt.unsafeGet

genAccPair (subdir: string, patterns: openArray[string], nameCur, nameFull, fallback: string):
  genSysClassPathGetter(root, subdir, patterns)
  newPathAccessor(root, nameCur, nameFull, fallback)

genAccPair (subdir: string, patterns: openArray[string], nameCur, nameFull: string):
  genSysClassPathGetter(root, subdir, patterns)
  newPathAccessor(root, nameCur, nameFull)

let
  Key2AccGetter = toCritBitTree [
    accPair(battery, "power_supply", ["BAT?", "battery"], "energy_now", "energy_full", fallback="capacity"),
    # BAT1 for most laptops; BAT0 for some; battery for Android (no perm if non-root; contains multi-subdir; has only `capacity`)
    accPair(brightness, "backlight", ["acpi_video", "*_backlight"],  "brightness", "max_brightness"),
    # acpi_video for ATI's; intel_backlight for intel's
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
    csNeverSet = NeverWriteErrMsg
    csPerm = PermErrMsg

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
  template retStatus(st: CmdStatus) =
    return CmdExecRes(status: st)
  case matches.len
  of 0:
    retStatus csUnknown
  of 1:
    let opt = matches[0]()
    if opt.isNil:
      retStatus csUnavail
    let acc = opt
    if val.isDefVal:
      result.res = %acc
    else:
      if not acc.writable:
        retStatus csNeverSet
      result.res = val
      try:
        acc %= val
      except PermissionError:
        retStatus csPerm
  else:
    return CmdExecRes(
      status: csAmbig,
      matches: matchesCmd
    )
