#            NimYAML - YAML implementation in Nim
#        (c) Copyright 2016 Felix Krause
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.

## =================
## Module yaml.hints
## =================
##
## The hints API enables you to guess the type of YAML scalars.

import macros
import private/internal

type
  TypeHint* = enum
    ## A type hint can be computed from scalar content and tells you what
    ## NimYAML thinks the scalar's type is. It is generated by
    ## `guessType <#guessType,string>`_ The first matching RegEx
    ## in the following table will be the type hint of a scalar string.
    ##
    ## You can use it to determine the type of YAML scalars that have a '?'
    ## non-specific tag, but using this feature is completely optional.
    ##
    ## ================== =========================
    ## Name               RegEx
    ## ================== =========================
    ## ``yTypeInteger``   ``0 | -? [1-9] [0-9]*``
    ## ``yTypeFloat``     ``-? [1-9] ( \. [0-9]* [1-9] )? ( e [-+] [1-9] [0-9]* )?``
    ## ``yTypeFloatInf``  ``-? \. (inf | Inf | INF)``
    ## ``yTypeFloatNaN``  ``-? \. (nan | NaN | NAN)``
    ## ``yTypeBoolTrue``  ``y|Y|yes|Yes|YES|true|True|TRUE|on|On|ON``
    ## ``yTypeBoolFalse`` ``n|N|no|No|NO|false|False|FALSE|off|Off|OFF``
    ## ``yTypeNull``      ``~ | null | Null | NULL``
    ## ``yTypeTimestamp`` see `here <http://yaml.org/type/timestamp.html>`_.
    ## ``yTypeUnknown``   ``*``
    ## ================== =========================
    yTypeInteger, yTypeFloat, yTypeFloatInf, yTypeFloatNaN, yTypeBoolTrue,
    yTypeBoolFalse, yTypeNull, yTypeUnknown, yTypeTimestamp

  YamlTypeHintState = enum
    ythInitial,
    ythF, ythFA, ythFAL, ythFALS, ythFALSE,
    ythN, ythNU, ythNUL, ythNULL,
          ythNO,
    ythO, ythON,
          ythOF, ythOFF,
    ythT, ythTR, ythTRU, ythTRUE,
    ythY, ythYE, ythYES,

    ythPoint, ythPointI, ythPointIN, ythPointINF,
              ythPointN, ythPointNA, ythPointNAN,

    ythLowerFA, ythLowerFAL, ythLowerFALS,
    ythLowerNU, ythLowerNUL,
    ythLowerOF,
    ythLowerTR, ythLowerTRU,
    ythLowerYE,

    ythPointLowerIN, ythPointLowerN, ythPointLowerNA,

    ythMinus, yth0, ythInt1, ythInt1Zero, ythInt2, ythInt2Zero, ythInt3,
    ythInt3Zero, ythInt4, ythInt4Zero, ythInt,
    ythDecimal, ythNumE, ythNumEPlusMinus, ythExponent,

    ythYearMinus, ythMonth1, ythMonth2, ythMonthMinus, ythMonthMinusNoYmd,
    ythDay1, ythDay1NoYmd, ythDay2, ythDay2NoYmd,
    ythAfterDayT, ythAfterDaySpace, ythHour1, ythHour2, ythHourColon,
    ythMinute1, ythMinute2, ythMinuteColon, ythSecond1, ythSecond2, ythFraction,
    ythAfterTimeSpace, ythAfterTimeZ, ythAfterTimePlusMinus, ythTzHour1,
    ythTzHour2, ythTzHourColon, ythTzMinute1, ythTzMinute2

macro typeHintStateMachine(c: untyped, content: varargs[untyped]): typed =
  yAssert content.kind == nnkArgList
  result = newNimNode(nnkCaseStmt, content).add(copyNimNode(c))
  for branch in content.children:
    yAssert branch.kind == nnkOfBranch
    var
      charBranch = newNimNode(nnkOfBranch, branch)
      i = 0
      stateBranches = newNimNode(nnkCaseStmt, branch).add(
          newIdentNode("typeHintState"))
    while branch[i].kind != nnkStmtList:
      charBranch.add(copyNimTree(branch[i]))
      inc(i)
    for rule in branch[i].children:
      yAssert rule.kind == nnkInfix
      yAssert $rule[0].ident == "=>"
      var stateBranch = newNimNode(nnkOfBranch, rule)
      case rule[1].kind
      of nnkBracket:
        for item in rule[1].children: stateBranch.add(item)
      of nnkIdent: stateBranch.add(rule[1])
      else: internalError("Invalid rule kind: " & $rule[1].kind)
      if rule[2].kind == nnkNilLit:
        stateBranch.add(newStmtList(newNimNode(nnkDiscardStmt).add(
                        newEmptyNode())))
      else:
        stateBranch.add(newStmtList(newAssignment(
                        newIdentNode("typeHintState"), copyNimTree(rule[2]))))
      stateBranches.add(stateBranch)
    stateBranches.add(newNimNode(nnkElse).add(newStmtList(
        newNimNode(nnkReturnStmt).add(newIdentNode("yTypeUnknown")))))
    charBranch.add(newStmtList(stateBranches))
    result.add(charBranch)
  result.add(newNimNode(nnkElse).add(newStmtList(
             newNimNode(nnkReturnStmt).add(newIdentNode("yTypeUnknown")))))

template advanceTypeHint(ch: char) {.dirty.} =
  typeHintStateMachine ch:
  of '~': ythInitial => ythNULL
  of '.':
    [yth0, ythInt1Zero, ythInt1, ythInt2, ythInt3, ythInt4, ythInt] => ythDecimal
    [ythInitial, ythMinus] => ythPoint
    ythSecond2             => ythFraction
  of '+':
    ythNumE => ythNumEPlusMinus
    [ythFraction, ythSecond2] => ythAfterTimePlusMinus
  of '-':
    ythInitial                => ythMinus
    ythNumE                   => ythNumEPlusMinus
    [ythInt4, ythInt4Zero]    => ythYearMinus
    ythMonth1                 => ythMonthMinusNoYmd
    ythMonth2                 => ythMonthMinus
    [ythFraction, ythSecond2] => ythAfterTimePlusMinus
  of '_':
    [ythInt1, ythInt2, ythInt3, ythInt4] => ythInt
    [ythInt, ythDecimal] => nil
  of ':':
    [ythHour1, ythHour2]      => ythHourColon
    ythMinute2                => ythMinuteColon
    [ythTzHour1, ythTzHour2]  => ythTzHourColon
  of '0':
    ythInitial                  => ythInt1Zero
    ythMinus                    => yth0
    [ythNumE, ythNumEPlusMinus] => ythExponent
    ythInt1                     => ythInt2
    ythInt1Zero                 => ythInt2Zero
    ythInt2                     => ythInt3
    ythInt2Zero                 => ythInt3Zero
    ythInt3                     => ythInt4
    ythInt3Zero                 => ythInt4Zero
    ythInt4                     => ythInt
    ythYearMinus                => ythMonth1
    ythMonth1                   => ythMonth2
    ythMonthMinus               => ythDay1
    ythMonthMinusNoYmd          => ythDay1NoYmd
    ythDay1                     => ythDay2
    ythDay1NoYmd                => ythDay2NoYmd
    [ythAfterDaySpace, ythAfterDayT] => ythHour1
    ythHour1                    => ythHour2
    ythHourColon                => ythMinute1
    ythMinute1                  => ythMinute2
    ythMinuteColon              => ythSecond1
    ythSecond1                  => ythSecond2
    ythAfterTimePlusMinus       => ythTzHour1
    ythTzHour1                  => ythTzHour2
    ythTzHourColon              => ythTzMinute1
    ythTzMinute1                => ythTzMinute2
    [ythInt, ythDecimal, ythExponent, ythFraction] => nil
  of '1'..'9':
    ythInitial                        => ythInt1
    ythInt1                           => ythInt2
    ythInt1Zero                       => ythInt2Zero
    ythInt2                           => ythInt3
    ythInt2Zero                       => ythInt3Zero
    ythInt3                           => ythInt4
    ythInt3Zero                       => ythInt4Zero
    [ythInt4, ythMinus]               => ythInt
    [ythNumE, ythNumEPlusMinus]       => ythExponent
    ythYearMinus                      => ythMonth1
    ythMonth1                         => ythMonth2
    ythMonthMinus                     => ythDay1
    ythMonthMinusNoYmd                => ythDay1NoYmd
    ythDay1                           => ythDay2
    ythDay1NoYmd                      => ythDay2NoYmd
    [ythAfterDaySpace, ythAfterDayT]  => ythHour1
    ythHour1                          => ythHour2
    ythHourColon                      => ythMinute1
    ythMinute1                        => ythMinute2
    ythMinuteColon                    => ythSecond1
    ythSecond1                        => ythSecond2
    ythAfterTimePlusMinus             => ythTzHour1
    ythTzHour1                        => ythTzHour2
    ythTzHourColon                    => ythTzMinute1
    ythTzMinute1                      => ythTzMinute2
    [ythInt, ythDecimal, ythExponent, ythFraction] => nil
  of 'a':
    ythF           => ythLowerFA
    ythPointN      => ythPointNA
    ythPointLowerN => ythPointLowerNA
  of 'A':
    ythF      => ythFA
    ythPointN => ythPointNA
  of 'e':
    [yth0, ythInt, ythDecimal] => ythNumE
    ythLowerFALS => ythFALSE
    ythLowerTRU  => ythTRUE
    ythY         => ythLowerYE
  of 'E':
    [yth0, ythInt, ythDecimal] => ythNumE
    ythFALS => ythFALSE
    ythTRU  => ythTRUE
    ythY    => ythYE
  of 'f':
    ythInitial      => ythF
    ythO            => ythLowerOF
    ythLowerOF      => ythOFF
    ythPointLowerIN => ythPointINF
  of 'F':
    ythInitial => ythF
    ythO       => ythOF
    ythOF      => ythOFF
    ythPointIN => ythPointINF
  of 'i', 'I': ythPoint => ythPointI
  of 'l':
    ythLowerNU  => ythLowerNUL
    ythLowerNUL => ythNULL
    ythLowerFA  => ythLowerFAL
  of 'L':
    ythNU  => ythNUL
    ythNUL => ythNULL
    ythFA  => ythFAL
  of 'n':
    ythInitial      => ythN
    ythO            => ythON
    ythPoint        => ythPointLowerN
    ythPointI       => ythPointLowerIN
    ythPointLowerNA => ythPointNAN
  of 'N':
    ythInitial => ythN
    ythO       => ythON
    ythPoint   => ythPointN
    ythPointI  => ythPointIN
    ythPointNA => ythPointNAN
  of 'o', 'O':
    ythInitial => ythO
    ythN       => ythNO
  of 'r': ythT => ythLowerTR
  of 'R': ythT => ythTR
  of 's':
    ythLowerFAL => ythLowerFALS
    ythLowerYE  => ythYES
  of 'S':
    ythFAL => ythFALS
    ythYE  => ythYES
  of 't', 'T':
    ythInitial         => ythT
    [ythDay1, ythDay2, ythDay1NoYmd, ythDay2NoYmd] => ythAfterDayT
  of 'u':
    ythN       => ythLowerNU
    ythLowerTR => ythLowerTRU
  of 'U':
    ythN  => ythNU
    ythTR => ythTRU
  of 'y', 'Y': ythInitial => ythY
  of 'Z': [ythSecond2, ythFraction, ythAfterTimeSpace] => ythAfterTimeZ
  of ' ', '\t':
    [ythSecond2, ythFraction] => ythAfterTimeSpace
    [ythDay1, ythDay2, ythDay1NoYmd, ythDay2NoYmd] => ythAfterDaySpace
    [ythAfterTimeSpace, ythAfterDaySpace] => nil

proc guessType*(scalar: string): TypeHint {.raises: [].} =
  ## Parse scalar string according to the RegEx table documented at
  ## `TypeHint <#TypeHind>`_.
  var typeHintState: YamlTypeHintState = ythInitial
  for c in scalar: advanceTypeHint(c)
  case typeHintState
  of ythNULL, ythInitial: result = yTypeNull
  of ythTRUE, ythON, ythYES, ythY: result = yTypeBoolTrue
  of ythFALSE, ythOFF, ythNO, ythN: result = yTypeBoolFalse
  of ythInt1, ythInt2, ythInt3, ythInt4, ythInt, yth0, ythInt1Zero: result = yTypeInteger
  of ythDecimal, ythExponent: result = yTypeFloat
  of ythPointINF: result = yTypeFloatInf
  of ythPointNAN: result = yTypeFloatNaN
  of ythDay2, ythSecond2, ythFraction, ythAfterTimeZ, ythTzHour1, ythTzHour2,
     ythTzMinute1, ythTzMinute2: result = yTypeTimestamp
  else: result = yTypeUnknown
