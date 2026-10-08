// HMIR생성/정리.hmje

extension HMIRGenerator {

    // 정본: HMIR몸통직접끝나는가
    func bodyEndsDirectly(_ body: J) -> Bool {
        let n = jLen(body)
        if n == 0 { return false }
        let last = jAt(jAt(body, n - 1), 1)
        let kind = astKind(last)
        if kind == "Return" || kind == "Break" || kind == "Continue" { return true }
        if kind == "UnsafeBlock" { return bodyEndsDirectly(astField(last, "body")) }
        if kind == "PreemptDisableBlock" { return bodyEndsDirectly(astField(last, "body")) }
        if kind == "DeadlineBlock" { return bodyEndsDirectly(astField(last, "body")) }
        if kind == "If" || kind == "Switch" {
            let eb = astField(last, "else_body")
            if astIsNull(eb) { return false }
            if !bodyEndsDirectly(eb) { return false }
            let branches = astField(last, "branches")
            for i in 0..<jLen(branches) {
                if !bodyEndsDirectly(jAt(jAt(branches, i), 1)) { return false }
            }
            return true
        }
        if kind == "Execute" {
            if astStrField(last, "name") == "종료" { return true }
        }
        if kind == "ExprStmt" {
            let e = astField(last, "expr")
            if astKind(e) == "CallExpr" && astStrField(e, "name") == "종료" { return true }
        }
        return false
    }

    // 정본: HMIR문자열지역해제
    func stringLocalRelease(_ s: HState, _ name: BStr) -> HState {
        let rt = nextTemp(s)
        var cur = addLine(rt.st, hcat(ind(s), rt.val, ": 문자열 = 읽기 ", name))
        cur = addLine(cur, hcat(ind(cur), "호출 @문자열해제[문자열](", rt.val, ")"))
        return addLine(cur, hcat(ind(cur), "소유권해제 ", name))
    }

    // 정본: HMIR문자열값해제
    func stringValueRelease(_ s: HState, _ name: BStr) -> HState {
        let rt = nextTemp(s)
        let cur = addLine(rt.st, hcat(ind(s), rt.val, ": 문자열 = 읽기 ", name))
        return addLine(cur, hcat(ind(cur), "호출 @문자열해제[문자열](", rt.val, ")"))
    }

    // 정본: HMIR동적배열지역해제
    func dynArrayLocalRelease(_ s: HState, _ name: BStr, _ t: BStr) -> HState {
        let rt = nextTemp(s)
        let cur = addLine(rt.st, hcat(ind(s), rt.val, ": ", typeDisplay(t), " = 읽기 ", name))
        return dynArrayUnaryCall(cur, rt.val, t, "동적배열해제", false).st
    }

    // 정본: HMIR소유타입인가
    func isOwnedType(_ s: HState, _ t: BStr) -> Bool {
        let inner = typeResolve(t)
        if isFnValueType(inner) { return true }
        if inner == "text" || typeDisplay(inner).hasSuffix("의 배열") { return true }
        let fe = fixedArrayElemType(inner)
        if fe.count > 0 { return isOwnedType(s, fe) }
        var sname = inner
        if sname.hasPrefix("struct:") { sname = hSub(sname, 7, sname.count - 7) }
        if isChannelEndpointStruct(sname) { return true }
        let fields = structFields(sname)
        if astIsNull(fields) { return false }
        for v in fields.objectValues {
            if isOwnedType(s, astStr(v)) { return true }
        }
        return false
    }

    // 정본: HMIR소유값해제
    func ownedValueRelease(_ s: HState, _ v: BStr, _ t: BStr) -> HState {
        var cur = s
        let inner = typeResolve(t)
        let fet = fixedArrayElemType(inner)
        if fet.count > 0 {
            var i = Int(fixedArrayLen(inner))
            while i > 0 {
                i -= 1
                if isOwnedType(cur, fet) {
                    let idx = nextTemp(cur)
                    cur = addLine(idx.st, hcat(ind(cur), idx.val, ": 큰정수 = 상수값 ", hDec(i)))
                    let el = nextTemp(cur)
                    cur = addLine(el.st, hcat(ind(cur), el.val, ": ", typeDisplay(fet), " = 인덱스읽기 ", v, "[", idx.val, "], 영기반"))
                    cur = ownedValueRelease(cur, el.val, fet)
                }
            }
            return cur
        }
        if isFnValueType(inner) {
            return addLine(cur, hcat(ind(cur), "함수값해제 ", v))
        }
        if inner == "text" {
            return addLine(cur, hcat(ind(cur), "호출 @문자열해제[문자열](", v, ")"))
        }
        if typeDisplay(inner).hasSuffix("의 배열") {
            return dynArrayUnaryCall(cur, v, inner, "동적배열해제", false).st
        }
        var ep = inner
        if ep.hasPrefix("struct:") { ep = hSub(ep, 7, ep.count - 7) }
        if isChannelEndpointStruct(ep) {
            return addLine(cur, hcat(ind(cur), "호출 @", ep, "해제[", typeDisplay(inner), "](", v, ")"))
        }
        // (정본은 여기서 고정배열 갈래를 한 번 더 본다 — 위에서 이미 걸러졌다)
        var sname = inner
        if sname.hasPrefix("struct:") { sname = hSub(sname, 7, sname.count - 7) }
        let fields = structFields(sname)
        if astIsNull(fields) { return cur }
        let fk = fields.objectKeys, fv = fields.objectValues
        for i in 0..<fk.count {
            let ft = typeResolve(astStr(fv[i]))
            if isOwnedType(cur, ft) {
                let tmp = nextTemp(cur)
                cur = addLine(tmp.st, hcat(ind(cur), tmp.val, ": ", typeDisplay(ft), " = 필드읽기 ", v, ".", fk[i]))
                cur = ownedValueRelease(cur, tmp.val, ft)
            }
        }
        return cur
    }

    // 정본: HMIR소유값유지
    func ownedValueRetain(_ s: HState, _ v: BStr, _ t: BStr) -> HRes {
        var cur = s
        let inner = typeResolve(t)
        let fet = fixedArrayElemType(inner)
        if fet.count > 0 {
            var vals: BStr = ""
            var i = 0
            let n = Int(fixedArrayLen(inner))
            while i < n {
                let idx = nextTemp(cur)
                cur = addLine(idx.st, hcat(ind(cur), idx.val, ": 큰정수 = 상수값 ", hDec(i)))
                let el = nextTemp(cur)
                cur = addLine(el.st, hcat(ind(cur), el.val, ": ", typeDisplay(fet), " = 인덱스읽기 ", v, "[", idx.val, "], 영기반"))
                var rv = el.val
                if isOwnedType(cur, fet) {
                    let k = ownedValueRetain(cur, el.val, fet)
                    cur = k.st
                    rv = k.val
                }
                if i > 0 { vals = hcat(vals, ", ") }
                vals = hcat(vals, rv)
                i += 1
            }
            let res = nextTemp(cur)
            let line = hcat(ind(cur), res.val, ": ", typeDisplay(inner), " = 배열값 [", vals, "]")
            return HRes(st: addLine(res.st, line), val: res.val, ty: inner)
        }
        if isFnValueType(inner) {
            let tmp = nextTemp(cur)
            let line = hcat(ind(cur), tmp.val, ": ", typeDisplay(inner), " = 함수값참조 ", v)
            return HRes(st: addLine(tmp.st, line), val: tmp.val, ty: inner)
        }
        if inner == "text" {
            let tmp = nextTemp(cur)
            let line = hcat(ind(cur), tmp.val, ": 문자열 = 호출 @문자열참조[문자열](", v, ")")
            return HRes(st: addLine(tmp.st, line), val: tmp.val, ty: inner)
        }
        if typeDisplay(inner).hasSuffix("의 배열") {
            return dynArrayUnaryCall(cur, v, inner, "동적배열참조", true)
        }
        var ep = inner
        if ep.hasPrefix("struct:") { ep = hSub(ep, 7, ep.count - 7) }
        if isChannelEndpointStruct(ep) {
            let tmp = nextTemp(cur)
            let line = hcat(ind(cur), tmp.val, ": ", typeDisplay(inner), " = 호출 @", ep, "참조[", typeDisplay(inner), "](", v, ")")
            return HRes(st: addLine(tmp.st, line), val: tmp.val, ty: inner)
        }
        var sname = inner
        if sname.hasPrefix("struct:") { sname = hSub(sname, 7, sname.count - 7) }
        let fields = structFields(sname)
        if astIsNull(fields) { return HRes(st: cur, val: v, ty: inner) }
        var fieldList: BStr = ""
        let fk = fields.objectKeys, fv = fields.objectValues
        for i in 0..<fk.count {
            let fname = fk[i]
            let ft = typeResolve(astStr(fv[i]))
            let tmp = nextTemp(cur)
            cur = addLine(tmp.st, hcat(ind(cur), tmp.val, ": ", typeDisplay(ft), " = 필드읽기 ", v, ".", fname))
            var fval = tmp.val
            if isOwnedType(cur, ft) {
                let k = ownedValueRetain(cur, fval, ft)
                cur = k.st
                fval = k.val
            }
            if i > 0 { fieldList = hcat(fieldList, ", ") }
            fieldList = hcat(fieldList, fname, ": ", fval)
        }
        let res = nextTemp(cur)
        let line = hcat(ind(cur), res.val, ": ", typeDisplay(inner), " = 구조체값 ", sname, "(", fieldList, ")")
        return HRes(st: addLine(res.st, line), val: res.val, ty: inner)
    }

    // 정본: HMIR문자열선택지역해제
    func stringOptionalLocalRelease(_ s: HState, _ name: BStr, _ t: BStr) -> HState {
        let or = nextTemp(s)
        let st1 = addLine(or.st, hcat(ind(s), or.val, ": ", typeDisplay(t), " = 읽기 ", name))
        let vr = nextTemp(st1)
        var cur = addLine(vr.st, hcat(ind(st1), vr.val, ": 문자열 = 필드읽기 ", or.val, ".값"))
        cur = addLine(cur, hcat(ind(cur), "호출 @문자열해제[문자열](", vr.val, ")"))
        return cur
    }

    // 정본: HMIR범위문자열정리
    func scopeStringCleanup(_ s: HState, _ start: Int) -> HState {
        var cur = s
        var i = s.sym.len
        while i > start {
            i -= 1
            let sym = s.sym.name(i)
            if sym.hasPrefix("@빌림:") {
                let n = hSub(sym, 8, sym.count - 8)
                if symType(cur, hcat("@빌림끝:", n)).count == 0 {
                    cur = addLine(cur, hcat(ind(cur), "빌림끝 ", n))
                    cur = symAdd(cur, hcat("@빌림끝:", n), "bool")
                }
            }
            if sym.hasPrefix("@지역text:") {
                let n = hSub(sym, 12, sym.count - 12)
                if symType(cur, hcat("@해제text:", n)).count == 0 {
                    cur = stringValueRelease(cur, n)
                }
            }
            if sym.hasPrefix("@소유:") {
                let n = hSub(sym, 8, sym.count - 8)
                if symType(cur, hcat("@해제arr:", n)).count == 0 {
                    cur = dynArrayLocalRelease(cur, n, symType(cur, n))
                }
            }
            if sym.hasPrefix("@소유선택text:") {
                let n = hSub(sym, 18, sym.count - 18)
                if symType(cur, hcat("@해제선택text:", n)).count == 0 {
                    cur = stringOptionalLocalRelease(cur, n, symType(cur, n))
                }
            }
            if sym.hasPrefix("@소유struct:") {
                let n = hSub(sym, 14, sym.count - 14)
                if symType(cur, hcat("@해제struct:", n)).count == 0 {
                    let rt = nextTemp(cur)
                    cur = addLine(rt.st, hcat(ind(cur), rt.val, ": ", typeDisplay(symType(cur, n)), " = 읽기 ", n))
                    cur = ownedValueRelease(cur, rt.val, symType(cur, n))
                }
            }
        }
        return cur
    }

    // 정본: HMIR실패지역정리
    func failureLocalCleanup(_ s: HState) -> HState {
        var start = 0
        if symType(s, "@시도실패표지").count > 0 {
            if let v = hParseU64(symType(s, "@시도정리시작")) { start = Int(v) }
        }
        var cur = ownedTempArgsRelease(s, s.ownVals, s.ownTypes)
        cur = scopeStringCleanup(cur, start)
        return ctxChange(cur, cur.indent, s.sym)
    }

    // 정본: HMIR범위빌림정리
    func scopeBorrowCleanup(_ s: HState, _ start: Int) -> HState {
        var cur = s
        var i = s.sym.len
        while i > start {
            i -= 1
            let sym = s.sym.name(i)
            if sym.hasPrefix("@빌림:") {
                let n = hSub(sym, 8, sym.count - 8)
                if symType(cur, hcat("@빌림끝:", n)).count == 0 {
                    cur = addLine(cur, hcat(ind(cur), "빌림끝 ", n))
                    cur = symAdd(cur, hcat("@빌림끝:", n), "bool")
                }
            }
        }
        return cur
    }

    // 정본: HMIR선점정리
    func preemptCleanup(_ s: HState, _ start: Int) -> HState {
        var cur = s
        var i = start
        while i < s.sym.len {
            if s.sym.name(i).hasPrefix("@선점:") {
                cur = addLine(cur, hcat(ind(cur), "호출 @커널선점허용[]()"))
            }
            i += 1
        }
        return cur
    }

    // 정본: HMIR호출이대상을소비하는가
    func callConsumesTarget(_ e: J, _ target: BStr) -> Bool {
        if astKind(e) != "CallExpr" { return false }
        let def = firstFunctionDef(astStrField(e, "name"))
        if astIsNull(def) { return false }
        let params = astField(def, "params")
        let args = astField(e, "args")
        for i in 0..<jLen(args) {
            let arg = jAt(args, i)
            if i < jLen(params) {
                if astBoolField(jAt(params, i), "consuming") && astKind(arg) == "NameExpr" {
                    if astStrField(arg, "name") == target { return true }
                }
            }
            if astKind(arg) == "CallExpr" {
                if callConsumesTarget(arg, target) { return true }
            }
        }
        return false
    }

    // 정본: HMIR반환소비미리수집
    func returnConsumePreCollect(_ s: HState, _ v: J, _ fnName: BStr) -> HState {
        var cur = s
        var curName = fnName
        if case .object = v {
            if astKind(v) == "FunctionDef" { curName = astStrField(v, "name") }
        }
        if case .array(let arr) = v {
            if arr.count == 2 {
                let lineV = arr[0]
                let node = arr[1]
                if astKind(node) == "Return" {
                    let re = astField(node, "expr")
                    if astKind(re) == "CallExpr" {
                        let cargs = astField(re, "args")
                        let cdef = firstFunctionDef(astStrField(re, "name"))
                        if !astIsNull(cdef) {
                            let cparams = astField(cdef, "params")
                            for i in 0..<jLen(cargs) {
                                var actual = jAt(cargs, i)
                                if jIsArray(actual) && jLen(actual) == 2 { actual = jAt(actual, 1) }
                                let param = jAt(cparams, i)
                                var owned = typeResolve(astStrField(param, "type_name")) == "text"
                                if typeDisplay(astStrField(param, "type_name")).hasSuffix("의 배열") || isOwnedType(cur, astStrField(param, "type_name")) { owned = true }
                                if astBoolField(param, "consuming") && owned && astKind(actual) == "NameExpr" {
                                    let ls = astTagStr(lineV, "integer")
                                    let head = hcat("@반환소비미리:", curName, ":", ls, ":")
                                    cur = symAdd(cur, hcat(head, hDec(i)), astStrField(actual, "name"))
                                }
                            }
                        }
                    }
                }
            }
            var i = arr.count
            while i > 0 {
                i -= 1
                cur = returnConsumePreCollect(cur, arr[i], curName)
            }
        } else if case .object(_, let vals) = v {
            var i = vals.count
            while i > 0 {
                i -= 1
                cur = returnConsumePreCollect(cur, vals[i], curName)
            }
        }
        return cur
    }

    // 정본: HMIR함수반환소비미리수집
    func returnConsumePreCollectAll(_ s: HState) -> HState {
        var cur = s
        let ks = funcs.objectKeys, vs = funcs.objectValues
        var i = ks.count
        while i > 0 {
            i -= 1
            cur = returnConsumePreCollect(cur, vs[i], ks[i])
        }
        return cur
    }

    // 정본: HMIR반환소비미리이동
    func returnConsumePreMove(_ s: HState, _ line: BStr) -> HState {
        var cur = s
        let fnName = symType(s, "@현재함수")
        let head = hcat("@반환소비미리:", fnName, ":", line, ":")
        var i = 0
        while i < s.sym.len {
            if s.sym.name(i).hasPrefix(head) {
                let real = s.sym.type(i)
                let mark = hcat("@호출이동:", line, ":", real)
                if symType(cur, mark).count == 0 {
                    cur = addLine(cur, hcat(ind(cur), "소유권이동 ", real, " -> 호출"))
                    cur = symAdd(cur, mark, "bool")
                    cur = symAdd(cur, hcat("@해제text:", real), "bool")
                    cur = symAdd(cur, hcat("@해제arr:", real), "bool")
                    cur = symAdd(cur, hcat("@해제struct:", real), "bool")
                    cur = symAdd(cur, hcat("@해제선택text:", real), "bool")
                }
            }
            i += 1
        }
        return cur
    }

    // 정본: HMIR반환호출소비이동들
    func returnCallConsumeMoves(_ s: HState, _ e: J, _ keepName: BStr) -> HState {
        if astKind(e) != "CallExpr" { return s }
        let name = astStrField(e, "name")
        let args = astField(e, "args")
        let def = callDefSelect(name, args, s)
        if astIsNull(def) { return s }
        let params = astField(def, "params")
        var cur = s
        for i in 0..<jLen(args) {
            let arg = jAt(args, i)
            if astKind(arg) == "CallExpr" {
                cur = returnCallConsumeMoves(cur, arg, keepName)
            }
        }
        return callConsumeMoves(cur, args, params, [], true, false, keepName)
    }
}
