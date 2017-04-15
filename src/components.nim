## Components in Karax are built by the ``.component`` macro annotation.

import macros, jdict, dom, vdom, tables, strutils

var
  vcomponents* = newJDict[cstring, proc(args: seq[VNode]): VNode]()
  dcomponents* = newJDict[cstring, proc(args: seq[VNode]): Node]()

type
  ComponentKind* {.pure.} = enum
    None,
    Tag,
    VNode,
    Node

var
  allcomponents {.compileTime.} = initTable[string, ComponentKind]()

proc isComponent*(x: string): ComponentKind {.compileTime.} =
  allcomponents.getOrDefault(x)

proc addTags() {.compileTime.} =
  let x = (bindSym"VNodeKind").getTypeImpl
  expectKind(x, nnkEnumTy)
  for i in ord(VNodeKind.html)..ord(VNodeKind.high):
    # +1 because of empty node at the start of the enum AST:
    let tag = $x[i+1]
    allcomponents[tag] = ComponentKind.Tag

static:
  addTags()

proc unpack(symbolicType: NimNode; index: int): NimNode {.compileTime.} =
  #let t = symbolicType.getTypeImpl
  let t = repr(symbolicType)
  case t
  of "cstring":
    result = quote do:
      args[`index`].text
  of "int", "VKey":
    result = quote do:
      args[`index`].intValue
  of "bool":
    result = quote do:
      args[`index`].intValue != 0
  elif t.endsWith"Kind":
    result = quote do:
      `symbolicType`(args[`index`].intValue)
  else:
    # just pass it along, maybe there is some conversion for it:
    result = quote do:
      args[`index`]

proc newname*(n: NimNode): NimNode =
  if n.kind == nnkPostfix:
    n[1] = newname(n[1])
    result = n
  elif n.kind == nnkSym:
    result = ident($n.symbol)
  else:
    result = n

macro component*(prc: untyped): untyped =
  ## A component takes an proc body and registers it as a component to the
  ## virtual dom.
  var n = prc.copyNimNode
  for i in 0..6: n.add prc[i].copyNimTree
  expectKind(n, nnkProcDef)
  if n[0].kind == nnkEmpty:
    error("please pass a non anonymous proc")
  let name = n[0]
  let params = params(n)
  let rettype = repr params[0]
  var isvirtual = ComponentKind.None
  if rettype == "VNode":
    isvirtual = ComponentKind.VNode
  elif rettype == "Node":
    isvirtual = ComponentKind.Node
  else:
    error "component must return VNode or Node"
  let realName = if name.kind == nnkPostfix: name[1] else: name
  let nn = $realName
  n[0] = ident("inner" & nn)
  var unpackCall = newCall(n[0])
  var counter = 0
  for i in 1.. <params.len:
    let param = params[i]
    let L = param.len
    let typ = param[L-2]
    for j in 0 .. L-3:
      unpackCall.add unpack(typ, counter)
      inc counter

  template vwrapper(pname, unpackCall) {.dirty.} =
    proc pname(args: seq[VNode]): VNode =
      unpackCall

  template dwrapper(pname, unpackCall) {.dirty.} =
    proc pname(args: seq[VNode]): Node =
      unpackCall

  template vregister(key, val) =
    bind jdict.`[]=`
    `[]=`(vcomponents, cstring(key), val)

  template dregister(key, val) =
    bind jdict.`[]=`
    `[]=`(dcomponents, cstring(key), val)

  result = newTree(nnkStmtList, n)
  if isvirtual == ComponentKind.VNode:
    result.add getAst(vwrapper(newname name, unpackCall))
    result.add getAst(vregister(newLit(nn), realName))
  else:
    result.add getAst(dwrapper(newname name, unpackCall))
    result.add getAst(dregister(newLit(nn), realName))
  allcomponents[nn] = isvirtual
  when defined(debugKaraxDsl):
    echo repr result

when isMainModule:
  proc public*(x, y: int, b: bool; s: cstring): VNode {.component.} =
    discard
  proc private(x, y: int, b: bool; s: cstring): VNode {.component.} =
    discard
