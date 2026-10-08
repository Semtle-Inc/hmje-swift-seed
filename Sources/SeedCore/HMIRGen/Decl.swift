// HMIR생성/선언.hmje, 함수.hmje, 특성비교.hmje

extension HMIRGenerator {

    // MARK: 선언.hmje

    // 정본: HMIR열거정수범위인가
    func enumIntInRange(_ v: BStr, _ base: BStr) -> Bool {
        if base.hasPrefix("u") {
            guard let n = hParseU64(v) else { return false }
            if base == "u8" { return n <= 255 }
            if base == "u16" { return n <= 65535 }
            if base == "u32" { return n <= 4294967295 }
            return base == "u64"
        }
        guard let n = hParseI64(v) else { return false }
        if base == "i8" { return n >= -128 && n <= 127 }
        if base == "i16" { return n >= -32768 && n <= 32767 }
        if base == "i32" { return n >= -2147483648 && n <= 2147483647 }
        return base == "i64"
    }

    // 정본: HMIR열거상수값
    func enumConstValue(_ node: J, _ base: BStr) -> J {
        let kind = astKind(node)
        if base == "text" || base == "char" {
            if kind == "StringLiteral" {
                let v = astStrField(node, "value")
                if base == "text" || v.string.count == 1 { return .string(v) }
            }
            return .null
        }
        if base == "bool" {
            if kind == "BoolLiteral" {
                if astBoolField(node, "value") { return .string("참") }
                return .string("거짓")
            }
            return .null
        }
        var e = node
        var sign: BStr = ""
        if kind == "UnaryExpr" && astStrField(node, "op") == "-" {
            sign = "-"
            e = astField(node, "operand")
        }
        var v: BStr = ""
        if astKind(e) == "IntLiteral" {
            v = hcat(sign, astTagStr(astField(e, "value"), "integer"))
        } else if astKind(e) == "FloatLiteral" && (base == "f32" || base == "f64") {
            v = hcat(sign, astTagStr(astField(e, "value"), "float"))
        }
        if v.count == 0 { return .null }
        if base == "f32" || base == "f64" {
            if let dot = hFind(v, ".") {
                var end = v.count
                while end > dot + 2 && hByte(v, end - 1) == 48 { end -= 1 }
                v = hSub(v, 0, end)
            } else {
                v = hcat(v, ".0")
            }
            if v == "-0.0" { v = "0.0" }
            return .string(v)
        }
        if enumIntInRange(v, base) {
            if v.hasPrefix("-") { return .string(BStr(String(hParseI64(v) ?? 0))) }
            return .string(hDecU(hParseU64(v) ?? 0))
        }
        return .null
    }

    // 정본: HMIR열거다음정수
    func enumNextInt(_ v: BStr) -> BStr {
        if v.hasPrefix("-") {
            if let n = hParseI64(v) { return BStr(String(n &+ 1)) }
        }
        if let p = hParseU64(v) {
            if p < UInt64.max { return hDecU(p + 1) }
        }
        return ""
    }

    // 정본: HMIR열거등록
    func enumRegister(_ s: HState, _ node: J) -> HState {
        let en = astStrField(node, "name")
        var base = typeResolve(astStrField(node, "base_type"))
        if base.count == 0 { base = "u64" }
        if base != "text" && base != "char" && base != "bool" && base != "f32" && base != "f64" && !enumIntInRange("0", base) {
            return fail(s, "열거형 기반 타입은 정수, 실수, 문자, 참거짓, 문자열이어야 합니다")
        }
        let cases = astField(node, "cases")
        var cur = s
        var nextInt: BStr = "1"
        var prevNames: [BStr] = [], prevVals: [BStr] = []
        for c in cases.arrayValue {
            let cname = astStr(jAt(c, 0))
            let cval = jAt(c, 1)
            var norm: J = .null
            if astIsNull(cval) {
                if base == "text" { norm = .string(cname) } else if enumIntInRange(nextInt, base) { norm = .string(nextInt) }
            } else {
                norm = enumConstValue(cval, base)
            }
            if astIsNull(norm) { return fail(cur, hcat("열거형 값은 기반 타입에 맞는 범위의 상수여야 합니다: ", cname)) }
            let sv = astStr(norm)
            for i in 0..<prevNames.count {
                if prevNames[i] == cname { return fail(cur, hcat("열거형 종류가 중복됩니다: ", en, ".", cname)) }
                if prevVals[i] == sv {
                    return fail(cur, hcat("열거형 값이 중복됩니다: ", en, ".", cname, " = ", sv, " (이전: ", en, ".", prevNames[i], ")"))
                }
            }
            prevNames.append(cname)
            prevVals.append(sv)
            if enumIntInRange(sv, base) { nextInt = enumNextInt(sv) }
            let key = hcat(en, ".", cname)
            cur = symAdd(cur, hcat("@열거타입:", key), hcat("enum:", en))
            cur = symAdd(cur, hcat("@열거값:", key), sv)
        }
        cur = symAdd(cur, hcat("@열거기반:", en), base)
        cur = symAdd(cur, hcat("@열거기반타입:", "enum:", en), base)
        cur = symAdd(cur, hcat("@열거기반타입:", en), base)
        return cur
    }

    // 정본: HMIR열거선언
    func enumDeclare(_ s: HState, _ node: J) -> HState {
        if !s.ok { return s }
        let en = astStrField(node, "name")
        let base = symType(s, hcat("@열거기반:", en))
        var line = hcat("  종류 ", en, " = ", typeDisplay(base), " { ")
        let cases = astField(node, "cases").arrayValue
        for (i, c) in cases.enumerated() {
            if i > 0 { line = hcat(line, ", ") }
            let name = astStr(jAt(c, 0))
            let v = symType(s, hcat("@열거값:", en, ".", name))
            line = hcat(line, name, " = ")
            if base == "text" || base == "char" { line = hcat(line, stringLiteralDisplay(v)) } else { line = hcat(line, v) }
        }
        line = hcat(line, " }")
        return addLine(s, line)
    }

    // 정본: HMIR구조체선언들
    func structDeclarations(_ s: HState) -> HState {
        var cur = s
        let ks = structs.objectKeys, vs = structs.objectValues
        for i in 0..<ks.count {
            var line = hcat("  타입 ", ks[i], " = 구조체 { ")
            let fk = vs[i].objectKeys, fv = vs[i].objectValues
            for j in 0..<fk.count {
                if j > 0 { line = hcat(line, ", ") }
                line = hcat(line, fk[j], ": ", typeDisplay(astStr(fv[j])))
            }
            line = hcat(line, " }")
            cur = addLine(cur, line)
        }
        return cur
    }

    // 정본: HMIR외부함수선언
    func externalFunctionDecl(_ s: HState, _ node: J) -> HState {
        let ext = astField(node, "external_name")
        if astIsNull(ext) { return s }
        var line = hcat("  외부함수 ", astStr(ext), "(")
        for (i, p) in astField(node, "params").arrayValue.enumerated() {
            if i > 0 { line = hcat(line, ", ") }
            if astBoolField(p, "consuming") { line = hcat(line, "소비하는 ") }
            line = hcat(line, astStrField(p, "name"), ": ", typeDisplay(astStrField(p, "type_name")))
        }
        line = hcat(line, ") -> ")
        var rt = typeResolve(astStrField(node, "return_type"))
        if rt.count == 0 { rt = "void" }
        line = hcat(line, typeDisplay(rt))
        return addLine(s, line)
    }

    // MARK: 함수.hmje

    // 정본: HMIR외부선언가려지나
    func externalDeclShadowed(_ node: J) -> Bool {
        let cands = funcOverloads(astStrField(node, "name"))
        let params = astField(node, "params")
        for cand in cands.arrayValue {
            if astIsNull(astField(cand, "external_name")) {
                let cps = astField(cand, "params")
                if jLen(cps) == jLen(params) {
                    var same = true
                    for i in 0..<jLen(params) {
                        if typeResolve(astStrField(jAt(params, i), "type_name")) != typeResolve(astStrField(jAt(cps, i), "type_name")) { same = false }
                    }
                    if same { return true }
                }
            }
        }
        return false
    }

    // 정본: HMIR일반함수직접
    func plainFunctionDirect(_ s: HState, _ node: J) -> HState {
        let ext = astField(node, "external_name")
        if !astIsNull(ext) {
            if externalDeclShadowed(node) { return s }
            if astBoolField(node, "is_async") { fatalError("미이식: HMIR외부비동기함수") }
            return externalFunctionDecl(s, node)
        }
        let name = astStrField(node, "name")
        let reg = functionNodeDefSelect(node)
        var rt = typeResolve(astStrField(reg, "return_type"))
        if rt.count == 0 { rt = "void" }
        let params = astField(node, "params").arrayValue
        let isAsync = astBoolField(node, "is_async")
        var head: BStr = isAsync ? "  비동기함수 " : "  함수 "
        head = hcat(head, accessCodeName(node), "(")
        for (i, p) in params.enumerated() {
            if i > 0 { head = hcat(head, ", ") }
            var frameConsume = astBoolField(p, "consuming")
            if isAsync && isOwnedType(s, astStrField(p, "type_name")) { frameConsume = true }
            if frameConsume { head = hcat(head, "소비하는 ") }
            head = hcat(head, astStrField(p, "name"), ": ", typeDisplay(astStrField(p, "type_name")))
        }
        head = hcat(head, ") -> ", typeDisplay(rt))
        var cur = addLine(s, head)
        let globals = cur.sym
        cur = ctxChange(cur, 2, globals)
        cur = symAdd(cur, "@현재함수", name)
        cur = accessContext(cur, node)
        if isAsync { cur = symAdd(cur, "@현재비동기", "bool") }
        if astBoolField(node, "can_fail") || astBoolField(reg, "can_fail") { cur = symAdd(cur, "@현재함수실패가능", "bool") }
        for p in params {
            let pn = astStrField(p, "name")
            let pt = typeResolve(astStrField(p, "type_name"))
            cur = symAdd(cur, pn, pt)
            if isAsync && pt == "text" { cur = symAdd(cur, hcat("@지역text:", pn), "bool") }
            if isAsync && typeDisplay(pt).hasSuffix("의 배열") { cur = symAdd(cur, hcat("@소유:", pn), "bool") }
            var structOwned = false
            if isAsync { structOwned = isOwnedType(cur, pt) }
            if pt == "text" || typeDisplay(pt).hasSuffix("의 배열") { structOwned = false }
            if structOwned { cur = symAdd(cur, hcat("@소유struct:", pn), "bool") }
            if astBoolField(p, "consuming") { cur = symAdd(cur, hcat("@소비:", pn), "bool") }
        }
        cur = functionStatements(cur, astField(node, "body"), rt)
        if !cur.ok { return cur }
        if !bodyEndsDirectly(astField(node, "body")) {
            cur = scopeStringCleanup(cur, globals.len)
        }
        cur = ctxChange(cur, 1, globals)
        cur = addLine(cur, "  함수끝")
        return cur
    }

    // MARK: 특성비교.hmje

    // 정본: HMIR동등정의
    func equalityDef(_ t: BStr) -> J {
        for cand in funcOverloads("같은지").arrayValue {
            let ps = astField(cand, "params").arrayValue
            if ps.count == 2 {
                if callTypeSame(astStrField(ps[0], "type_name"), t) && callTypeSame(astStrField(ps[1], "type_name"), t) { return cand }
            }
        }
        return .null
    }

    // 정본: HMIR같은지사용자정의인가
    func isUserEquality(_ args: J, _ s: HState) -> Bool {
        if jLen(args) != 2 { return false }
        let l = exprStaticType(jAt(args, 0), s)
        let r = exprStaticType(jAt(args, 1), s)
        if !callTypeSame(l, r) { return false }
        return !astIsNull(equalityDef(l))
    }

    // 정본: HMIR동등값낮추기
    func equalityValueLower(_ input: HState, _ lv: BStr, _ rv: BStr, _ t: BStr) -> HRes {
        var st = input
        let def = equalityDef(t)
        let inner = typeResolve(t)
        if !astIsNull(def) || inner == "text" {
            var name: BStr = "문자열같은가"
            var pdisp: BStr = "문자열"
            var callPre: BStr = "@"
            var lpass = lv, rpass = rv
            if !astIsNull(def) {
                if typeResolve(astStrField(def, "return_type")) != "bool" {
                    return exprError(st, "같은지 특성 함수는 참거짓을 반환해야 합니다")
                }
                name = "같은지"
                pdisp = typeDisplay(inner)
                let ext = astField(def, "external_name")
                if !astIsNull(ext) { name = astStr(ext); callPre = "@외부:" }
                let ps = astField(def, "params")
                if astBoolField(jAt(ps, 0), "consuming") {
                    let k = ownedValueRetain(st, lv, inner)
                    st = k.st; lpass = k.val
                }
                if astBoolField(jAt(ps, 1), "consuming") {
                    let k = ownedValueRetain(st, rv, inner)
                    st = k.st; rpass = k.val
                }
            }
            let tmp = nextTemp(st)
            let line = hcat(ind(st), tmp.val, ": 참거짓 = 호출 ", callPre, name, "[", pdisp, ", ", pdisp, "](", lpass, ", ", rpass, ")")
            return HRes(st: addLine(tmp.st, line), val: tmp.val, ty: "bool")
        }
        if typeDisplay(inner).hasSuffix("의 배열") {
            return exprError(st, "동적 배열의 같은지 특성에는 명시한 동등 함수가 필요합니다")
        }
        var sname = inner
        if sname.hasPrefix("struct:") { sname = hSub(sname, 7, sname.count - 7) }
        let fields = structFields(sname)
        if !astIsNull(fields) {
            var result: BStr = "참"
            let fk = fields.objectKeys, fv = fields.objectValues
            for i in 0..<fk.count {
                let fname = fk[i]
                let ft = typeResolve(astStr(fv[i]))
                let lf = nextTemp(st)
                st = addLine(lf.st, hcat(ind(st), lf.val, ": ", typeDisplay(ft), " = 필드읽기 ", lv, ".", fname))
                let rf = nextTemp(st)
                st = addLine(rf.st, hcat(ind(st), rf.val, ": ", typeDisplay(ft), " = 필드읽기 ", rv, ".", fname))
                let cmp = equalityValueLower(st, lf.val, rf.val, ft)
                if !cmp.st.ok { return cmp }
                st = cmp.st
                if i == 0 {
                    result = cmp.val
                } else {
                    let m = nextTemp(st)
                    st = addLine(m.st, hcat(ind(st), m.val, ": 참거짓 = 논리곱 ", result, ", ", cmp.val))
                    result = m.val
                }
            }
            return HRes(st: st, val: result, ty: "bool")
        }
        let tmp = nextTemp(st)
        let line = hcat(ind(st), tmp.val, ": 참거짓 = 비교 == ", lv, ", ", rv)
        return HRes(st: addLine(tmp.st, line), val: tmp.val, ty: "bool")
    }

    // 정본: HMIR동등임시정리
    func equalityTempCleanup(_ s: HState, _ node: J, _ v: BStr, _ t: BStr) -> HState {
        var base = node
        if astKind(base) == "CastExpr" { base = astField(base, "expr") }
        let kind = astKind(base)
        if kind == "CallExpr" || kind == "StructInitExpr" || symType(s, hcat("@임시소유:", v)).count > 0 {
            return ownedValueRelease(s, v, t)
        }
        return s
    }
}
