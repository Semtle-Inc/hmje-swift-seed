// HMIR생성/문장.hmje — HMIR함수문장들

extension HMIRGenerator {

    // 정본: HMIR함수문장들
    func functionStatements(_ s: HState, _ body: J, _ rt: BStr) -> HState {
        var cur = s
        for pair in body.arrayValue {
            var node = objectSetAssign(jAt(pair, 1))
            if !astIsNull(astField(node, "access_imports")) { cur = accessContext(cur, node) }
            if astKind(node) == "ExprStmt" {
                let cand = astField(node, "expr")
                if astKind(cand) == "CallExpr" && astStrField(cand, "name") == "종료" {
                    node = jNode("Execute", ["name", "args", "is_try"], [.string("종료"), astField(cand, "args"), .bool(false)])
                }
            }
            let kind = astKind(node)
            let lineV = jAt(pair, 0)
            let lineS = astTagStr(lineV, "integer")
            cur = symAdd(cur, "@현재줄", lineS)
            switch kind {
            case "Return":
                cur = stmtReturn(cur, node, rt, lineS)
            case "Define":
                cur = stmtDefine(cur, node)
            case "BorrowDefine":
                cur = stmtBorrowDefine(cur, node)
            case "TakeDefine":
                cur = stmtTakeDefine(cur, node)
            case "DynamicArrayAppend":
                cur = stmtDynAppend(cur, node)
            case "Assign":
                cur = stmtAssign(cur, node)
            case "If":
                cur = ifLower(cur, node, rt)
            case "Continue", "Break":
                let isCont = kind == "Continue"
                let pre: BStr = isCont ? "@반복계속:" : "@반복끝:"
                let skip = isCont ? 14 : 11
                var target: BStr = ""
                var fi = cur.sym.len
                while fi > 0 && target.count == 0 {
                    fi -= 1
                    let sm = cur.sym.name(fi)
                    if sm.hasPrefix(pre) { target = hSub(sm, skip, sm.count - skip) }
                }
                if target.count == 0 { return fail(cur, isCont ? "반복 밖의 계속입니다" : "반복 밖의 멈춤입니다") }
                cur = scopeStringCleanup(cur, fi + 1)
                cur = preemptCleanup(cur, fi + 1)
                cur = addLine(cur, hcat(ind(cur), "이동 ", target))
            case "ForEach":
                cur = stmtForEach(cur, node, pair, lineS, rt)
            case "While":
                cur = stmtWhile(cur, node, rt)
            case "UnsafeBlock":
                cur = stmtUnsafe(cur, node, rt)
            case "Execute":
                cur = stmtExecute(cur, node)
            case "ExprStmt":
                cur = stmtExprStmt(cur, node)
            case "Forget":
                let n = astStrField(node, "name")
                cur = addLine(cur, hcat(ind(cur), "소유권잊음 ", n))
                let t = symType(cur, n)
                if t == "text" { cur = symAdd(cur, hcat("@해제text:", n), "bool") }
                if typeDisplay(t).hasSuffix("의 배열") { cur = symAdd(cur, hcat("@해제arr:", n), "bool") }
                var so = isOwnedType(cur, t)
                if t == "text" || typeDisplay(t).hasSuffix("의 배열") { so = false }
                if so { cur = symAdd(cur, hcat("@해제struct:", n), "bool") }
            case "ManualRelease":
                let n = astStrField(node, "name")
                let t = symType(cur, n)
                if t == "text" {
                    cur = stringLocalRelease(cur, n)
                    if symType(cur, hcat("@소유text:", n)).count > 0 {
                        cur = symAdd(cur, hcat("@해제:", n), "bool")
                    } else {
                        cur = symAdd(cur, hcat("@해제text:", n), "bool")
                    }
                } else if typeDisplay(t).hasSuffix("의 배열") {
                    cur = dynArrayLocalRelease(cur, n, t)
                    cur = symAdd(cur, hcat("@해제arr:", n), "bool")
                } else {
                    let rt2 = nextTemp(cur)
                    cur = addLine(rt2.st, hcat(ind(cur), rt2.val, ": ", typeDisplay(t), " = 읽기 ", n))
                    cur = ownedValueRelease(cur, rt2.val, t)
                    cur = addLine(cur, hcat(ind(cur), "소유권해제 ", n))
                    cur = symAdd(cur, hcat("@해제struct:", n), "bool")
                    if typeResolve(t).hasSuffix("문자열선택값") { cur = symAdd(cur, hcat("@해제선택text:", n), "bool") }
                }
            default:
                fatalError("미이식: HMIR함수문장들 \(kind.string)")
            }
            if !cur.ok { return cur }
        }
        return cur
    }

    // MARK: Return

    func stmtReturn(_ s: HState, _ node: J, _ rt: BStr, _ lineS: BStr) -> HState {
        var cur = s
        let re = astField(node, "expr")
        if astIsNull(re) {
            cur = activeEndCleanup(cur, rt)
            cur = scopeBorrowCleanup(cur, 0)
            cur = scopeStringCleanup(cur, 0)
            cur = preemptCleanup(cur, 0)
            return addLine(cur, hcat(ind(cur), "반환"))
        }
        let rk = astKind(re)
        var srcName: BStr = ""
        if rk == "NameExpr" { srcName = astStrField(re, "name") }
        var callArgs: J = .null
        var callParams: J = .null
        var callSrcNames: [BStr] = []
        if rk == "CallExpr" {
            callArgs = astField(re, "args")
            let cdef = callDefSelect(astStrField(re, "name"), callArgs, cur)
            if !astIsNull(cdef) {
                callParams = astField(cdef, "params")
                for i in 0..<jLen(callArgs) {
                    var a = jAt(callArgs, i)
                    if jIsArray(a) && jLen(a) == 2 { a = jAt(a, 1) }
                    var n: BStr = ""
                    if astKind(a) == "NameExpr" { n = astStrField(a, "name") }
                    callSrcNames.append(n)
                }
            }
        }
        var optStruct = typeResolve(rt)
        if optStruct.hasPrefix("struct:") { optStruct = hSub(optStruct, 7, optStruct.count - 7) }
        var rexp = HRes(st: cur, val: "", ty: "")
        var wrap = optStruct.hasSuffix("선택값")
        if rk == "OptionalNoneExpr" || rk == "StructInitExpr" { wrap = false }
        if exprStaticType(re, cur) == typeResolve(rt) { wrap = false }
        if rk == "NameExpr" {
            if symType(cur, srcName) == typeResolve(rt) { wrap = false }
            if typeDisplay(symType(cur, srcName)) == typeDisplay(rt) { wrap = false }
        }
        if wrap { rexp = optionalSomeLower(cur, re, rt) } else { rexp = lowerExpr(re, cur, rt) }
        cur = rexp.st
        if !cur.ok { return cur }
        if rk == "NameExpr" {
            let consumeMark = hcat("@소비:", srcName)
            var ownedRet = typeDisplay(rt).hasSuffix("의 배열")
            if typeResolve(rt) == "text" { ownedRet = true }
            if isOwnedType(cur, rt) { ownedRet = true }
            if symType(cur, consumeMark).count > 0 && ownedRet {
                cur = addLine(cur, hcat(ind(cur), "소유권이동 ", srcName, " -> ", rexp.val))
            }
            var arrKeep = typeDisplay(rt).hasSuffix("의 배열")
            if symType(cur, consumeMark).count > 0 { arrKeep = false }
            let arrRefFn = hcat(dynArrayFnHead(rt), "동적배열참조")
            if symType(cur, "@현재함수") == arrRefFn { arrKeep = false }
            if arrKeep {
                let k = dynArrayUnaryCall(cur, rexp.val, rt, "동적배열참조", true)
                rexp = HRes(st: k.st, val: k.val, ty: rt)
                cur = rexp.st
            }
            var structKeep = isOwnedType(cur, rt)
            if typeResolve(rt) == "text" { structKeep = false }
            if typeDisplay(rt).hasSuffix("의 배열") { structKeep = false }
            if symType(cur, consumeMark).count > 0 { structKeep = false }
            if wrap { structKeep = false }
            if structKeep {
                let k = ownedValueRetain(cur, rexp.val, rt)
                rexp = HRes(st: k.st, val: k.val, ty: rt)
                cur = rexp.st
            }
            let curFn = symType(cur, "@현재함수")
            var strKeep = typeResolve(rt) == "text"
            if symType(cur, consumeMark).count > 0 { strKeep = false }
            if curFn == "문자열참조" { strKeep = false }
            if strKeep {
                let t = nextTemp(cur)
                cur = addLine(t.st, hcat(ind(cur), t.val, ": 문자열 = 호출 @문자열참조[문자열](", rexp.val, ")"))
                rexp = HRes(st: cur, val: t.val, ty: "text")
            }
        }
        var borrowExpr = rk == "OptionalUnwrapExpr"
        if rk == "FieldAccessExpr" || rk == "IndexAccessExpr" { borrowExpr = true }
        if wrap { borrowExpr = false }
        if symType(cur, hcat("@임시소유:", rexp.val)).count > 0 { borrowExpr = false }
        if rk == "IndexAccessExpr" {
            let bt = exprStaticType(astField(re, "base"), cur)
            if dynArrayFnHead(bt).count > 0 { borrowExpr = false }
        }
        if borrowExpr {
            if typeResolve(rt) == "text" {
                let t = nextTemp(cur)
                cur = addLine(t.st, hcat(ind(cur), t.val, ": 문자열 = 호출 @문자열참조[문자열](", rexp.val, ")"))
                rexp = HRes(st: cur, val: t.val, ty: "text")
            } else if typeDisplay(rt).hasSuffix("의 배열") {
                rexp = dynArrayUnaryCall(cur, rexp.val, rt, "동적배열참조", true)
                cur = rexp.st
            } else if isOwnedType(cur, rt) {
                rexp = ownedValueRetain(cur, rexp.val, rt)
                cur = rexp.st
            }
        }
        if !astIsNull(callParams) {
            cur = callConsumeMoves(cur, callArgs, callParams, callSrcNames, true, true, "")
        }
        cur = returnConsumePreMove(cur, lineS)
        cur = returnCallConsumeMoves(cur, re, "")
        cur = activeEndCleanup(cur, rt)
        cur = scopeBorrowCleanup(cur, 0)
        var ri = cur.sym.len
        while ri > 0 {
            ri -= 1
            let sm = cur.sym.name(ri)
            if sm.hasPrefix("@소유:") {
                let n = hSub(sm, 8, sm.count - 8)
                if symType(cur, hcat("@해제arr:", n)).count == 0 { cur = dynArrayLocalRelease(cur, n, symType(cur, n)) }
            }
            if sm.hasPrefix("@지역text:") {
                let n = hSub(sm, 12, sm.count - 12)
                if symType(cur, hcat("@해제text:", n)).count == 0 { cur = stringValueRelease(cur, n) }
            }
            if sm.hasPrefix("@소유선택text:") {
                let n = hSub(sm, 18, sm.count - 18)
                if symType(cur, hcat("@해제선택text:", n)).count == 0 { cur = stringOptionalLocalRelease(cur, n, symType(cur, n)) }
            }
            if sm.hasPrefix("@소유struct:") {
                let n = hSub(sm, 14, sm.count - 14)
                if symType(cur, hcat("@해제struct:", n)).count == 0 {
                    let t = nextTemp(cur)
                    cur = addLine(t.st, hcat(ind(cur), t.val, ": ", typeDisplay(symType(cur, n)), " = 읽기 ", n))
                    cur = ownedValueRelease(cur, t.val, symType(cur, n))
                }
            }
        }
        cur = preemptCleanup(cur, 0)
        return addLine(cur, hcat(ind(cur), "반환 ", rexp.val, ": ", typeDisplay(rt)))
    }

    // MARK: Define

    func stmtDefine(_ s: HState, _ node: J) -> HState {
        var cur = s
        var lt = typeResolve(astStrField(node, "type_name"))
        let le = astField(node, "expr")
        let lk = astKind(le)
        if lk == "StructInitExpr" {
            let st = exprStaticType(le, cur)
            if st.count > 0 { lt = st }
        }
        var srcName: BStr = ""
        if lk == "NameExpr" { srcName = astStrField(le, "name") }
        var fieldBaseTemp = false
        if lk == "FieldAccessExpr" {
            let fb = astField(le, "base")
            let fk = astKind(fb)
            if fk == "CallExpr" || fk == "StructInitExpr" || fk == "IndexAccessExpr" { fieldBaseTemp = true }
        }
        var optName = lt
        if optName.hasPrefix("struct:") { optName = hSub(optName, 7, optName.count - 7) }
        var wrap = optName.hasSuffix("선택값")
        if wrap {
            let ovt = typeResolve(astStr(astObjField(structFields(optName), "값")))
            let actual = exprStaticType(le, cur)
            if actual.count > 0 && typeDisplay(actual) != typeDisplay(ovt) { wrap = false }
        }
        if lk == "OptionalNoneExpr" || lk == "StructInitExpr" || lk == "DynamicArrayPopExpr" { wrap = false }
        if exprStaticType(le, cur) == lt { wrap = false }
        var lx: HRes
        if wrap { lx = optionalSomeLower(cur, le, lt) } else { lx = lowerExpr(le, cur, lt) }
        cur = lx.st
        if !cur.ok { return cur }
        cur = returnCallConsumeMoves(cur, le, "")
        if lt.count == 0 { lt = lx.ty }
        var borrow = lk == "NameExpr"
        if lk == "OffsetMemoryReadExpr" { borrow = true }
        if lk == "FieldAccessExpr" {
            borrow = true
            if fieldBaseTemp { borrow = false }
        }
        if lk == "CastExpr" {
            if astKind(astField(le, "expr")) == "NameExpr" { borrow = true }
        }
        if lk == "OptionalUnwrapExpr" { borrow = true }
        if lk == "NameExpr" {
            if symType(cur, hcat("@소비:", srcName)).count > 0 { borrow = false }
            if srcName.hasPrefix("__필터_") {
                let k = dynArrayUnaryCall(cur, lx.val, lt, "동적배열참조", true)
                lx = HRes(st: k.st, val: k.val, ty: lt)
                cur = lx.st
                borrow = false
            }
        }
        if wrap { borrow = false }
        if symType(cur, hcat("@임시소유:", lx.val)).count > 0 { borrow = false }
        if lt == "text" && borrow {
            let t = nextTemp(cur)
            let ss = addLine(t.st, hcat(ind(cur), t.val, ": 문자열 = 호출 @문자열참조[문자열](", lx.val, ")"))
            lx = HRes(st: ss, val: t.val, ty: "text")
            cur = lx.st
        }
        if dynArrayFnHead(lt).count > 0 && borrow {
            let k = dynArrayUnaryCall(cur, lx.val, lt, "동적배열참조", true)
            lx = HRes(st: k.st, val: k.val, ty: lt)
            cur = lx.st
        }
        var structKeep = isOwnedType(cur, lt)
        if lt == "text" || typeDisplay(lt).hasSuffix("의 배열") { structKeep = false }
        if structKeep && borrow {
            let k = ownedValueRetain(cur, lx.val, lt)
            lx = HRes(st: k.st, val: k.val, ty: lt)
            cur = lx.st
        }
        let name = astStrField(node, "name")
        let kw: BStr = astBoolField(node, "mutable") ? "변수 " : "상수 "
        cur = addLine(cur, hcat(ind(cur), kw, name, ": ", typeDisplay(lt), " = ", lx.val))
        if lk == "NameExpr" {
            if symType(cur, hcat("@소비:", srcName)).count > 0 {
                cur = addLine(cur, hcat(ind(cur), "소유권이동 ", srcName, " -> ", name))
                let ot = symType(cur, srcName)
                if ot == "text" {
                    cur = symAdd(cur, hcat("@해제text:", srcName), "bool")
                } else if typeDisplay(ot).hasSuffix("의 배열") {
                    cur = symAdd(cur, hcat("@해제arr:", srcName), "bool")
                } else if ot.hasSuffix("문자열선택값") {
                    cur = symAdd(cur, hcat("@해제선택text:", srcName), "bool")
                } else if isOwnedType(cur, ot) {
                    cur = symAdd(cur, hcat("@해제struct:", srcName), "bool")
                }
            }
        }
        cur = symAdd(cur, name, lt)
        if lt == "address" && lk == "AddressOfExpr" {
            cur = symAdd(cur, hcat("@주소원본:", name), astStrField(le, "name"))
        }
        var inFn = symType(cur, "@현재함수").count > 0
        if symType(cur, "@위험구역").count > 0 { inFn = true }
        if inFn && dynArrayFnHead(lt).count > 0 && typeDisplay(lt).hasSuffix("의 배열") {
            cur = symAdd(cur, hcat("@소유:", name), "bool")
        }
        if inFn && lt == "text" { cur = symAdd(cur, hcat("@지역text:", name), "bool") }
        if inFn && lt.hasSuffix("문자열선택값") { cur = symAdd(cur, hcat("@소유선택text:", name), "bool") }
        var so = isOwnedType(cur, lt)
        if lt == "text" || typeDisplay(lt).hasSuffix("의 배열") { so = false }
        if lt.hasSuffix("문자열선택값") { so = false }
        if inFn && so { cur = symAdd(cur, hcat("@소유struct:", name), "bool") }
        return cur
    }

    // MARK: BorrowDefine / TakeDefine

    func stmtBorrowDefine(_ s: HState, _ node: J) -> HState {
        var cur = s
        let bt = typeResolve(astStrField(node, "type_name"))
        let ba = lowerExpr(astField(node, "address"), cur, "address")
        cur = ba.st
        if !cur.ok { return cur }
        let t = nextTemp(cur)
        cur = addLine(t.st, hcat(ind(cur), t.val, ": ", typeDisplay(bt), " = 오프셋읽기 ", ba.val, ", ", typeDisplay(bt)))
        let bn = astStrField(node, "name")
        cur = addLine(cur, hcat(ind(cur), "변수 ", bn, ": ", typeDisplay(bt), " = ", t.val))
        var src: BStr = "?"
        let ae = astField(node, "address")
        if astKind(ae) == "NameExpr" {
            let alias = symType(cur, hcat("@주소원본:", astStrField(ae, "name")))
            if alias.count > 0 { src = alias }
        }
        cur = addLine(cur, hcat(ind(cur), "빌림시작 ", bn, " <- ", src))
        cur = symAdd(cur, bn, bt)
        cur = symAdd(cur, hcat("@빌림:", bn), "bool")
        return cur
    }

    func stmtTakeDefine(_ s: HState, _ node: J) -> HState {
        var cur = s
        let tt = typeResolve(astStrField(node, "type_name"))
        let ta = lowerExpr(astField(node, "address"), cur, "address")
        cur = ta.st
        if !cur.ok { return cur }
        let t = nextTemp(cur)
        cur = addLine(t.st, hcat(ind(cur), t.val, ": ", typeDisplay(tt), " = 오프셋읽기 ", ta.val, ", ", typeDisplay(tt)))
        let tn = astStrField(node, "name")
        cur = addLine(cur, hcat(ind(cur), "변수 ", tn, ": ", typeDisplay(tt), " = ", t.val))
        cur = symAdd(cur, tn, tt)
        if tt == "text" { cur = symAdd(cur, hcat("@소유text:", tn), "bool") }
        return cur
    }

    // MARK: DynamicArrayAppend

    func stmtDynAppend(_ s: HState, _ node: J) -> HState {
        var cur = s
        let an = astStrField(node, "name")
        let at = symType(cur, an)
        var head = dynArrayFnHead(at)
        if typeDisplay(at) == "문자열의 배열" { head = "문자열배열" }
        let fnName = hcat(head, "동적배열추가")
        let def = firstFunctionDef(fnName)
        let vt = typeResolve(astStrField(jAt(astField(def, "params"), 1), "type_name"))
        let ar = nextTemp(cur)
        let rs = addLine(ar.st, hcat(ind(cur), ar.val, ": ", typeDisplay(at), " = 읽기 ", an))
        let ve = astField(node, "expr")
        let v = lowerExpr(ve, rs, vt)
        if !v.st.ok { return v.st }
        let res = nextTemp(v.st)
        cur = addLine(res.st, hcat(ind(v.st), res.val, ": ", typeDisplay(at), " = 호출 @", fnName, "[", typeDisplay(at), ", ", typeDisplay(vt), "](", ar.val, ", ", v.val, ")"))
        let vk = astKind(ve)
        var strTemp = vk == "CallExpr"
        if vk == "IndexAccessExpr" {
            let bt = exprStaticType(astField(ve, "base"), cur)
            if dynArrayFnHead(bt).count > 0 { strTemp = true }
        }
        if symType(cur, hcat("@임시소유:", v.val)).count > 0 { strTemp = true }
        if vt == "text" && strTemp {
            cur = addLine(cur, hcat(ind(cur), "호출 @문자열해제[문자열](", v.val, ")"))
        }
        var structTemp = vk == "StructInitExpr"
        if strTemp { structTemp = true }
        if vk == "CallExpr" || vk == "StructValueExpr" || vk == "StructUpdateExpr" { structTemp = true }
        if structTemp && vt != "text" {
            if isOwnedType(cur, vt) { cur = ownedValueRelease(cur, v.val, vt) }
        }
        return addLine(cur, hcat(ind(cur), "쓰기 ", an, " = ", res.val))
    }

    // MARK: Assign

    func stmtAssign(_ s: HState, _ node: J) -> HState {
        var cur = s
        let target = astField(node, "target")
        let tk = astKind(target)
        if tk == "NameTarget" {
            let tn = astStrField(target, "name")
            let tt = symType(cur, tn)
            var inFn = symType(cur, "@현재함수").count > 0
            if symType(cur, "@위험구역").count > 0 { inFn = true }
            let ae = astField(node, "expr")
            let ak = astKind(ae)
            var av = lowerExpr(ae, cur, tt)
            cur = av.st
            if !cur.ok { return cur }
            cur = returnCallConsumeMoves(cur, ae, tn)
            var borrow = ak == "NameExpr"
            if ak == "FieldAccessExpr" { borrow = true }
            if ak == "OptionalUnwrapExpr" { borrow = true }
            if symType(cur, hcat("@임시소유:", av.val)).count > 0 { borrow = false }
            if tt == "text" && borrow {
                let t = nextTemp(cur)
                cur = addLine(t.st, hcat(ind(cur), t.val, ": 문자열 = 호출 @문자열참조[문자열](", av.val, ")"))
                av = HRes(st: cur, val: t.val, ty: tt)
            }
            if typeDisplay(tt).hasSuffix("의 배열") && borrow {
                let k = dynArrayUnaryCall(cur, av.val, tt, "동적배열참조", true)
                av = HRes(st: k.st, val: k.val, ty: tt)
                cur = av.st
            }
            var structKeep = isOwnedType(cur, tt)
            if tt == "text" || typeDisplay(tt).hasSuffix("의 배열") { structKeep = false }
            if ak == "OptionalUnwrapExpr" && tt != "text" && !typeDisplay(tt).hasSuffix("의 배열") { structKeep = true }
            if structKeep && borrow {
                let k = ownedValueRetain(cur, av.val, tt)
                av = HRes(st: k.st, val: k.val, ty: tt)
                cur = av.st
            }
            if inFn && tt == "text" && symType(cur, hcat("@해제text:", tn)).count == 0 && symType(cur, hcat("@해제:", tn)).count == 0 && !callConsumesTarget(ae, tn) {
                cur = stringValueRelease(cur, tn)
            }
            if inFn && typeDisplay(tt).hasSuffix("의 배열") && symType(cur, hcat("@해제arr:", tn)).count == 0 && !callConsumesTarget(ae, tn) {
                cur = dynArrayLocalRelease(cur, tn, tt)
            }
            var structRel = isOwnedType(cur, tt)
            if !inFn { structRel = false }
            if tt == "text" || typeDisplay(tt).hasSuffix("의 배열") { structRel = false }
            if callConsumesTarget(ae, tn) { structRel = false }
            if symType(cur, hcat("@해제struct:", tn)).count > 0 { structRel = false }
            if structRel {
                let t = nextTemp(cur)
                cur = addLine(t.st, hcat(ind(cur), t.val, ": ", typeDisplay(tt), " = 읽기 ", tn))
                cur = ownedValueRelease(cur, t.val, tt)
            }
            cur = addLine(cur, hcat(ind(cur), "쓰기 ", tn, " = ", av.val))
            if tt == "text" {
                if symType(cur, hcat("@소유text:", tn)).count > 0 {
                    cur = symAdd(cur, hcat("@해제:", tn), "")
                } else {
                    cur = symAdd(cur, hcat("@해제text:", tn), "")
                }
            }
            if typeDisplay(tt).hasSuffix("의 배열") { cur = symAdd(cur, hcat("@해제arr:", tn), "") }
            if structRel || symType(cur, hcat("@해제struct:", tn)).count > 0 {
                cur = symAdd(cur, hcat("@해제struct:", tn), "")
            }
            return cur
        }
        if tk == "FieldTarget" {
            let fb = astField(target, "base")
            let fname = astStrField(target, "field")
            if fname == "이름" || fname == "형식" {
                let wb = targetReadExpr(fb)
                let wt = typeDisplay(exprStaticType(wb, cur))
                if wt == "객체" {
                    if astIsNull(astObjField(structFields("객체"), fname)) {
                        fatalError("미이식: 객체 메타데이터 쓰기")
                    }
                }
            }
            if astKind(fb) == "NameTarget" && fname == "길이" {
                let an = astStrField(fb, "name")
                let at = symType(cur, an)
                if at.hasSuffix("동적배열형") {
                    let rn = jNode("NameExpr", ["name"], [.string(an)])
                    let ar = lowerExpr(rn, cur, at)
                    let nl = lowerExpr(astField(node, "expr"), ar.st, "u64")
                    cur = nl.st
                    if !cur.ok { return cur }
                    var raw = at
                    if raw.hasPrefix("struct:") { raw = hSub(raw, 7, raw.count - 7) }
                    let fh = hSub(raw, 0, raw.count - 15)
                    let lf = hcat(fh, "동적배열길이조정")
                    let t = nextTemp(cur)
                    cur = addLine(t.st, hcat(ind(cur), t.val, ": ", typeDisplay(at), " = 호출 @", lf, "[", typeDisplay(at), ", 큰자연수](", ar.val, ", ", nl.val, ")"))
                    return addLine(cur, hcat(ind(cur), "쓰기 ", an, " = ", t.val))
                }
            }
            let path = fieldTargetPath(fb)
            if path.count > 0 {
                let baseName = path
                var bt = fieldTargetType(fb, cur)
                if bt.hasPrefix("overlay:") && astKind(fb) == "NameTarget" {
                    let ovs = hSub(bt, 8, bt.count - 8)
                    let ofl = structFields(ovs)
                    var oft: BStr = ""
                    var off: UInt64 = 0
                    var found = false
                    let ok = ofl.objectKeys, ov = ofl.objectValues
                    var oi = 0
                    while oi < ok.count && !found {
                        if ok[oi] == fname {
                            oft = typeResolve(astStr(ov[oi]))
                            found = true
                        } else {
                            off = off &+ packedTypeSize(astStr(ov[oi]))
                        }
                        oi += 1
                    }
                    if !found { return fail(cur, hcat("필드 타입을 찾을 수 없습니다: ", fname)) }
                    let bn = jNode("NameExpr", ["name", "compiler_generated"], [.string(baseName), .bool(false)])
                    let ob = lowerExpr(bn, cur, "")
                    cur = ob.st
                    if !cur.ok { return cur }
                    let ot = nextTemp(cur)
                    cur = addLine(ot.st, hcat(ind(cur), ot.val, ": 큰자연수 = 상수값 ", hDecU(off)))
                    let oa = nextTemp(cur)
                    cur = addLine(oa.st, hcat(ind(cur), oa.val, ": 주소 = ", binaryOpDisplay("+"), " ", ob.val, ", ", ot.val))
                    let ovv = lowerExpr(astField(node, "expr"), cur, oft)
                    cur = ovv.st
                    if !cur.ok { return cur }
                    var wv = ovv.val
                    let endian = symType(cur, hcat("@구조체엔디안:", ovs))
                    if packedTypeSize(oft) > 1 && endian == "big" {
                        let r = nextTemp(cur)
                        cur = addLine(r.st, hcat(ind(cur), r.val, ": ", typeDisplay(oft), " = 바이트뒤집기 ", wv))
                        wv = r.val
                    }
                    return addLine(cur, hcat(ind(cur), "포인터쓰기 오프셋 ", oa.val, ", ", typeDisplay(oft), ", ", wv))
                }
                if bt.hasPrefix("struct:") { bt = hSub(bt, 7, bt.count - 7) }
                let sf = structFields(bt)
                let ft = typeResolve(astStr(astObjField(sf, fname)))
                if ft.count == 0 {
                    var e = hcat("필드 타입을 찾을 수 없습니다: ", fname, " (바탕 타입 ", bt, ")")
                    let ln = symType(cur, "@현재줄")
                    if ln.count > 0 { e = hcat(e, " (줄 ", ln, ")") }
                    return fail(cur, e)
                }
                let fe = astField(node, "expr")
                let fk = astKind(fe)
                var fv = lowerExpr(fe, cur, ft)
                cur = fv.st
                if !cur.ok { return cur }
                var borrow = fk == "NameExpr"
                if fk == "FieldAccessExpr" || fk == "OptionalUnwrapExpr" { borrow = true }
                if borrow && ft == "text" {
                    let t = nextTemp(cur)
                    cur = addLine(t.st, hcat(ind(cur), t.val, ": 문자열 = 호출 @문자열참조[문자열](", fv.val, ")"))
                    fv = HRes(st: cur, val: t.val, ty: ft)
                }
                if borrow && typeDisplay(ft).hasSuffix("의 배열") {
                    let k = dynArrayUnaryCall(cur, fv.val, ft, "동적배열참조", true)
                    fv = HRes(st: k.st, val: k.val, ty: ft)
                    cur = fv.st
                }
                var sk = isOwnedType(cur, ft)
                if ft == "text" || typeDisplay(ft).hasSuffix("의 배열") { sk = false }
                if borrow && sk {
                    let k = ownedValueRetain(cur, fv.val, ft)
                    fv = HRes(st: k.st, val: k.val, ty: ft)
                    cur = fv.st
                }
                if symType(cur, "@현재함수").count > 0 && isOwnedType(cur, ft) {
                    let t = nextTemp(cur)
                    cur = addLine(t.st, hcat(ind(cur), t.val, ": ", typeDisplay(ft), " = 읽기 ", baseName, ".", fname))
                    cur = ownedValueRelease(cur, t.val, ft)
                }
                return addLine(cur, hcat(ind(cur), "쓰기 ", baseName, ".", fname, " = ", fv.val))
            }
            fatalError("미이식: 일반 필드 대입")
        }
        if tk == "MemoryTarget" { fatalError("미이식: MemoryTarget 대입") }
        if tk == "OffsetMemoryTarget" {
            let ot = typeResolve(astStrField(target, "value_type"))
            let oa = lowerExpr(astField(target, "address"), cur, "address")
            if !oa.st.ok { return oa.st }
            let ov = lowerExpr(astField(node, "expr"), oa.st, ot)
            cur = ov.st
            if !cur.ok { return cur }
            return addLine(cur, hcat(ind(cur), "포인터쓰기 오프셋 ", oa.val, ", ", typeDisplay(ot), ", ", ov.val))
        }
        if tk != "IndexTarget" { return fail(cur, hcat("미지원 대입 대상: ", tk)) }
        let bTarget = astField(target, "base")
        if astKind(bTarget) != "NameTarget" { return fail(cur, "중첩 배열 대입은 아직 미지원입니다") }
        let tn = astStrField(bTarget, "name")
        let tt = symType(cur, tn)
        if tt.hasPrefix("overlay_array:") {
            if astBoolField(target, "natural") { return fail(cur, "순번 오버레이 대입은 아직 이식 중입니다") }
            let re = jNode("NameExpr", ["name", "compiler_generated"], [.string(tn), .bool(false)])
            let ie = jNode("IndexAccessExpr", ["base", "index", "natural"], [re, astField(target, "index"), .bool(false)])
            let oa = overlayArrayAddrLower(ie, cur, "쓰기")
            let ov = lowerExpr(astField(node, "expr"), oa.st, oa.ty)
            return addLine(ov.st, hcat(ind(ov.st), "포인터쓰기 오프셋 ", oa.val, ", ", typeDisplay(oa.ty), ", ", ov.val))
        }
        if tt.hasSuffix("동적배열형") {
            let setName = hcat(dynArrayFnHead(tt), "동적배열설정")
            let re = jNode("NameExpr", ["name", "compiler_generated"], [.string(tn), .bool(false)])
            let se = jNode("CallExpr", ["name", "args", "compiler_generated"], [.string(setName), .array([re, astField(target, "index"), astField(node, "expr")]), .bool(false)])
            let sr = lowerExpr(se, cur, tt)
            cur = sr.st
            if !cur.ok { return cur }
            return addLine(cur, hcat(ind(cur), "쓰기 ", tn, " = ", sr.val))
        }
        let et = fixedArrayElemType(tt)
        let ir = lowerExpr(astField(target, "index"), cur, "")
        if !ir.st.ok { return ir.st }
        let vr = lowerExpr(astField(node, "expr"), ir.st, et)
        cur = vr.st
        if !cur.ok { return cur }
        var line = hcat(ind(cur), "쓰기 ", tn, "[")
        if astBoolField(target, "natural") { line = hcat(line, "순번 ") }
        line = hcat(line, ir.val, "] = ", vr.val)
        return addLine(cur, line)
    }

    // MARK: ForEach / While / Unsafe

    func stmtForEach(_ s: HState, _ node: J, _ pair: J, _ lineS: BStr, _ rt: BStr) -> HState {
        var cur = s
        let ae = astField(node, "array")
        let at = exprStaticType(ae, cur)
        var et = fixedArrayElemType(at)
        if et.count == 0 {
            let gd = firstFunctionDef(hcat(dynArrayFnHead(at), "동적배열가져오기"))
            et = typeResolve(astStrField(gd, "return_type"))
        }
        if et.count == 0 { return fail(cur, "각 반복의 원소 타입을 찾을 수 없습니다") }
        let lineV = jAt(pair, 0)
        let labelBase = cur.label
        let zero = lowerExpr(jNode("IntLiteral", ["value"], [jObj(["integer"], [.string("0")])]), cur, "u64")
        cur = zero.st
        let idxName = hcat("__for_", lineS, "_", hDec(labelBase), "_순번")
        cur = addLine(cur, hcat(ind(cur), "변수 ", idxName, ": 자연수64 = ", zero.val))
        cur = symAdd(cur, idxName, "u64")
        let condL = nextLabel(cur, "각반복조건")
        let bodyL = nextLabel(condL.st, "각반복본문")
        let incL = nextLabel(bodyL.st, "각반복증가")
        let endL = nextLabel(incL.st, "각반복끝")
        cur = addLine(endL.st, hcat(ind(endL.st), "이동 ", condL.val))
        cur = addLine(cur, hcat(ind(cur), condL.val, ":"))
        let idxE = jNode("NameExpr", ["name"], [.string(idxName)])
        var lenE: J
        if fixedArrayElemType(at).count > 0 {
            lenE = jNode("IntLiteral", ["value"], [jObj(["integer"], [.string(hDecU(fixedArrayLen(at)))])])
        } else {
            lenE = jNode("FieldAccessExpr", ["base", "field"], [ae, .string("길이")])
        }
        let cond = jNode("CompareCondition", ["left", "op", "right"], [idxE, .string("<"), lenE])
        let cr = conditionLower(cond, cur)
        cur = cr.st
        cur = addLine(cur, hcat(ind(cur), "분기 ", cr.val, ", ", bodyL.val, ", ", endL.val))
        cur = addLine(cur, hcat(ind(cur), bodyL.val, ":"))
        let oIndent = cur.indent
        let outer = cur.sym
        cur = symAdd(cur, hcat("@반복끝:", endL.val), "bool")
        cur = symAdd(cur, hcat("@반복계속:", incL.val), "bool")
        cur = ctxChange(cur, oIndent + 1, cur.sym)
        var body: [J] = []
        let posV = astField(node, "position_name")
        if !astIsNull(posV) {
            let pd = jNode("Define", ["mutable", "name", "type_name", "expr"], [.bool(false), posV, .string("자연수64"), idxE])
            body.append(.array([lineV, pd]))
        }
        let ie = jNode("IndexAccessExpr", ["base", "index", "natural"], [ae, idxE, .bool(false)])
        let ed = jNode("Define", ["mutable", "name", "type_name", "expr"], [.bool(false), .string(astStrField(node, "item_name")), .string(typeDisplay(et)), ie])
        body.append(.array([lineV, ed]))
        let ob = astField(node, "body")
        for x in ob.arrayValue { body.append(x) }
        cur = functionStatements(cur, .array(body), rt)
        if !cur.ok { return cur }
        if !bodyEndsDirectly(ob) {
            cur = scopeStringCleanup(cur, outer.len)
            cur = addLine(cur, hcat(ind(cur), "이동 ", incL.val))
        }
        cur = ctxChange(cur, oIndent, outer)
        cur = addLine(cur, hcat(ind(cur), incL.val, ":"))
        cur = ctxChange(cur, oIndent + 1, cur.sym)
        let one = jNode("IntLiteral", ["value"], [jObj(["integer"], [.string("1")])])
        let inc = jNode("BinaryExpr", ["left", "op", "right"], [idxE, .string("+"), one])
        let nv = lowerExpr(inc, cur, "u64")
        cur = nv.st
        cur = addLine(cur, hcat(ind(cur), "쓰기 ", idxName, " = ", nv.val))
        cur = addLine(cur, hcat(ind(cur), "이동 ", condL.val))
        cur = ctxChange(cur, oIndent, outer)
        return addLine(cur, hcat(ind(cur), endL.val, ":"))
    }

    func stmtWhile(_ s: HState, _ node: J, _ rt: BStr) -> HState {
        var cur = s
        let outer = cur.sym
        let condL = nextLabel(cur, "반복조건")
        let bodyL = nextLabel(condL.st, "반복본문")
        let endL = nextLabel(bodyL.st, "반복끝")
        cur = addLine(endL.st, hcat(ind(endL.st), "이동 ", condL.val))
        cur = addLine(cur, hcat(ind(cur), condL.val, ":"))
        let cr = conditionLower(astField(node, "condition"), cur)
        cur = cr.st
        if !cur.ok { return cur }
        cur = addLine(cur, hcat(ind(cur), "분기 ", cr.val, ", ", bodyL.val, ", ", endL.val))
        cur = addLine(cur, hcat(ind(cur), bodyL.val, ":"))
        let oIndent = cur.indent
        cur = symAdd(cur, hcat("@반복끝:", endL.val), "bool")
        cur = symAdd(cur, hcat("@반복계속:", condL.val), "bool")
        cur = ctxChange(cur, oIndent + 1, cur.sym)
        cur = functionStatements(cur, astField(node, "body"), rt)
        if !cur.ok { return cur }
        cur = scopeStringCleanup(cur, outer.len)
        cur = addLine(cur, hcat(ind(cur), "이동 ", condL.val))
        cur = ctxChange(cur, oIndent, outer)
        return addLine(cur, hcat(ind(cur), endL.val, ":"))
    }

    func stmtUnsafe(_ s: HState, _ node: J, _ rt: BStr) -> HState {
        var cur = addLine(s, hcat(ind(s), "위험구역"))
        let oIndent = cur.indent
        let outer = cur.sym
        let before = cur.sym.len
        cur = ctxChange(cur, oIndent + 1, cur.sym)
        cur = functionStatements(cur, astField(node, "body"), rt)
        if !cur.ok { return cur }
        cur = scopeStringCleanup(cur, before)
        var pi = cur.sym.len
        while pi > before {
            pi -= 1
            let ps = cur.sym.name(pi)
            if ps.hasPrefix("@고정:") { cur = addLine(cur, hcat(ind(cur), "주소고정끝 ", hSub(ps, 8, ps.count - 8))) }
        }
        let after = cur.sym   // 정본: 위험후이름들 — 같은 버퍼를 보는 사본(별칭 의미 그대로)
        cur = ctxChange(cur, oIndent, outer)
        var mi = before
        while mi < after.len {
            let mk = after.name(mi)
            var tgt: BStr = ""
            if mk.hasPrefix("@해제struct:") { tgt = hSub(mk, 14, mk.count - 14) }
            else if mk.hasPrefix("@해제text:") { tgt = hSub(mk, 12, mk.count - 12) }
            else if mk.hasPrefix("@해제arr:") { tgt = hSub(mk, 11, mk.count - 11) }
            else if mk.hasPrefix("@해제:") { tgt = hSub(mk, 8, mk.count - 8) }
            if tgt.count > 0 && symType(cur, tgt).count > 0 { cur = symAdd(cur, mk, after.type(mi)) }
            mi += 1
        }
        var pubi = before
        while pubi < after.len {
            let pn = after.name(pubi)
            if !pn.hasPrefix("@") && symType(cur, pn).count == 0 { cur = symAdd(cur, pn, after.type(pubi)) }
            pubi += 1
        }
        return addLine(cur, hcat(ind(cur), "위험구역끝"))
    }

    // MARK: Execute / ExprStmt

    func stmtExecute(_ s: HState, _ node: J) -> HState {
        var cur = s
        let conc = symType(cur, "@동시묶음")
        let cdef = callDefSelect(astStrField(node, "name"), astField(node, "args"), cur)
        var isAsync = false
        if !astIsNull(cdef) { isAsync = astBoolField(cdef, "is_async") }
        if conc.count > 0 && isAsync { fatalError("미이식: 동시 묶음 실행") }
        if astStrField(node, "name") == "종료" {
            var ee = jAt(astField(node, "args"), 0)
            if jIsArray(ee) && jLen(ee) == 2 { ee = jAt(ee, 1) }
            let ev = lowerExpr(ee, cur, "u64")
            cur = ev.st
            if !cur.ok { return cur }
            var canClean = symType(cur, "@현재함수").count > 0
            if symType(cur, "@위험구역").count > 0 { canClean = true }
            if canClean {
                cur = scopeStringCleanup(cur, 0)
                cur = preemptCleanup(cur, 0)
            }
            cur = addLine(cur, hcat(ind(cur), "호출 @종료[큰자연수](", ev.val, ")"))
            return addLine(cur, hcat(ind(cur), "도달불가"))
        }
        var ex = node
        if astBoolField(node, "is_try") {
            let call = jNode("CallExpr", ["name", "args"], [astField(node, "name"), astField(node, "args")])
            ex = jNode("TryExpr", ["expr"], [call])
        }
        let r = lowerExpr(ex, cur, "")
        cur = r.st
        if !cur.ok { return cur }
        if r.ty != "void" {
            cur = addLine(cur, hcat(ind(cur), "버림 ", r.val, ": ", typeDisplay(r.ty)))
        }
        return cur
    }

    func stmtExprStmt(_ s: HState, _ node: J) -> HState {
        var cur = s
        let e = astField(node, "expr")
        let conc = symType(cur, "@동시묶음")
        if conc.count > 0 && astKind(e) == "CallExpr" {
            let d = callDefSelect(astStrField(e, "name"), astField(e, "args"), cur)
            if !astIsNull(d) && astBoolField(d, "is_async") { fatalError("미이식: 동시 묶음 식문장") }
        }
        let r = lowerExpr(e, cur, "")
        cur = r.st
        if !cur.ok { return cur }
        if r.ty != "void" {
            cur = addLine(cur, hcat(ind(cur), "버림 ", r.val, ": ", typeDisplay(r.ty)))
        }
        return returnCallConsumeMoves(cur, e, "")
    }
}
