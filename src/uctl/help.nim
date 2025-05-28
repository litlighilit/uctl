import std/[os, strformat]
import ./util

template pri(s) = stdout.write s
proc priHelp* =
  pri fmt"""
usage:
  {getAppFileName()} <subcmd>[ <value>]

note:
  Once value is given, this has to be run as root (require write access to file under {SysClass})

subcmd can be one of available list or just prefix (if not ambiguous): """
  loopAvailCmdsByIt:
    pri it
    pri ' '
  pri '\n'
