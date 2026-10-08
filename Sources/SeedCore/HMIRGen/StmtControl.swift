// HMIR생성/문장_보조.hmje, 문장_제어흐름.hmje

extension HMIRGenerator {

    // MARK: 문장_보조.hmje

    // 정본: HMIR식뿌리이름
    func exprRootName(_ e: J) -> BStr {
        let k = astKind(e)
        if k == "NameExpr" { return astStrField(e, "name") }
        if k == "FieldAccessExpr" || k == "IndexAccessExpr" { return exprRootName(astField(e, "base")) }
        if k == "OptionalUnwrapExpr" || k == "CastExpr" { return exprRootName(astField(e, "expr")) }
        return ""
    }

    // 정본: HMIR객체설정대입
    func objectSetAssign(_ node: J) -> J {
        if astKind(node) != "Execute" { return node }
        let name = astStrField(node, "name")
        var field: BStr = "", vname: BStr = ""
        if name == "객체이름정하기" { field = "이름"; vname = "이름" } else if name == "객체형식정하기" { field = "형식"; vname = "형식" }
        if field.count == 0 { return node }
        let args = astField(node, "args")
        var target: J = .null, value: J = .null
        for i in 0..<jLen(args) {
            let a = jAt(args, i)
            let n = astStr(jAt(a, 0))
            if n == "대상" { target = jAt(a, 1) }
            if n == vname { value = jAt(a, 1) }
        }
        if astIsNull(target) || astIsNull(value) { return node }
        let tn = astStrField(target, "name")
        let nameT = jNode("NameTarget", ["name"], [.string(tn)])
        let fieldT = jNode("FieldTarget", ["base", "field"], [nameT, .string(field)])
        return jNode("Assign", ["target", "expr"], [fieldT, value])
    }

    // 정본: HMIR필드대상경로
    func fieldTargetPath(_ t: J) -> BStr {
        let k = astKind(t)
        if k == "NameTarget" { return astStrField(t, "name") }
        if k == "FieldTarget" {
            let bp = fieldTargetPath(astField(t, "base"))
            if bp.count > 0 { return hcat(bp, ".", astStrField(t, "field")) }
        }
        return ""
    }

    // 정본: HMIR필드대상타입
    func fieldTargetType(_ t: J, _ s: HState) -> BStr {
        let k = astKind(t)
        if k == "NameTarget" { return symType(s, astStrField(t, "name")) }
        if k == "FieldTarget" {
            var bt = fieldTargetType(astField(t, "base"), s)
            if bt.hasPrefix("struct:") { bt = hSub(bt, 7, bt.count - 7) }
            if bt.hasPrefix("overlay:") { bt = hSub(bt, 8, bt.count - 8) }
            let ftv = astObjField(structFields(bt), astStrField(t, "field"))
            if !astIsNull(ftv) { return typeResolve(astStr(ftv)) }
        }
        return ""
    }

    // 정본: HMIR대상읽기식
    func targetReadExpr(_ t: J) -> J {
        let k = astKind(t)
        if k == "NameTarget" { return jNode("NameExpr", ["name"], [astField(t, "name")]) }
        if k == "FieldTarget" { return jNode("FieldAccessExpr", ["base", "field"], [targetReadExpr(astField(t, "base")), astField(t, "field")]) }
        if k == "IndexTarget" {
            return jNode("IndexAccessExpr", ["base", "index", "natural"], [targetReadExpr(astField(t, "base")), astField(t, "index"), astField(t, "natural")])
        }
        return .null
    }

    // MARK: 문장_제어흐름.hmje

    // 정본: HMIR선택있음낮추기
    func optionalSomeLower(_ s: HState, _ e: J, _ optType: BStr) -> HRes {
        var sname = typeResolve(optType)
        if sname.hasPrefix("struct:") { sname = hSub(sname, 7, sname.count - 7) }
        let of = structFields(sname)
        let vt = typeResolve(astStr(astObjField(of, "값")))
        let has = nextTemp(s)
        let hs = addLine(has.st, hcat(ind(s), has.val, ": 참거짓 = 상수값 참"))
        var vr = lowerExpr(e, hs, vt)
        if !vr.st.ok { return vr }
        var ce = e
        while astKind(ce) == "CastExpr" || astKind(ce) == "TryExpr" { ce = astField(ce, "expr") }
        let ek = astKind(ce)
        var borrowed = ek == "NameExpr" || ek == "FieldAccessExpr" || ek == "OptionalUnwrapExpr" || ek == "OffsetMemoryReadExpr"
        if ek == "IndexAccessExpr" {
            let bt = exprStaticType(astField(ce, "base"), vr.st)
            borrowed = dynArrayFnHead(bt).count == 0
        }
        if ek == "NameExpr" {
            if symType(vr.st, hcat("@소비:", astStrField(ce, "name"))) != "" { borrowed = false }
        }
        if symType(vr.st, hcat("@임시소유:", vr.val)) != "" { borrowed = false }
        if borrowed && isOwnedType(vr.st, vt) { vr = ownedValueRetain(vr.st, vr.val, vt) }
        let ot = nextTemp(vr.st)
        let line = hcat(ind(vr.st), ot.val, ": ", typeDisplay(optType), " = 구조체값 ", sname, "(있음: ", has.val, ", 값: ", vr.val, ")")
        return HRes(st: addLine(ot.st, line), val: ot.val, ty: optType)
    }

    // 정본: HMIRIf낮추기
    func ifLower(_ s: HState, _ node: J, _ rt: BStr) -> HState {
        let branches = astField(node, "branches")
        let elseBody = astField(node, "else_body")
        let endL = nextLabel(s, "조건끝")
        var cur = endL.st
        let outerIndent = s.indent
        let outer = s.sym
        var lastFalse = endL.val
        let nb = jLen(branches)
        for bi in 0..<nb {
            let b = jAt(branches, bi)
            let cond = jAt(b, 0)
            let body = jAt(b, 1)
            let trueL = nextLabel(cur, "조건참")
            cur = trueL.st
            let isLast = bi + 1 == nb
            var falseL = endL.val
            if isLast && !astIsNull(elseBody) {
                let f = nextLabel(cur, "조건거짓"); cur = f.st; falseL = f.val
            } else if !isLast {
                let f = nextLabel(cur, "조건다음"); cur = f.st; falseL = f.val
            }
            lastFalse = falseL
            let cr = conditionLower(cond, cur)
            cur = cr.st
            if !cur.ok { return cur }
            cur = addLine(cur, hcat(ind(cur), "분기 ", cr.val, ", ", trueL.val, ", ", falseL))
            cur = addLine(cur, hcat(ind(cur), trueL.val, ":"))
            cur = ctxChange(cur, outerIndent + 1, outer)
            if astKind(cond) == "OptionalBindCondition" {
                let bv = lowerExpr(astField(cond, "expr"), cur, "")
                cur = bv.st
                if !cur.ok { return cur }
                var bn = typeResolve(bv.ty)
                if bn.hasPrefix("struct:") { bn = hSub(bn, 7, bn.count - 7) }
                let bt = typeResolve(astStr(astObjField(structFields(bn), "값")))
                let bt2 = nextTemp(cur)
                cur = addLine(bt2.st, hcat(ind(cur), bt2.val, ": ", typeDisplay(bt), " = 필드읽기 ", bv.val, ".값"))
                let bname = astStrField(cond, "name")
                cur = addLine(cur, hcat(ind(cur), "상수 ", bname, ": ", typeDisplay(bt), " = ", bt2.val))
                cur = symAdd(cur, bname, bt)
            }
            cur = functionStatements(cur, body, rt)
            if !cur.ok { return cur }
            if !bodyEndsDirectly(body) {
                cur = scopeStringCleanup(cur, outer.len)
                cur = addLine(cur, hcat(ind(cur), "이동 ", endL.val))
            }
            cur = ctxChange(cur, outerIndent, outer)
            if !isLast { cur = addLine(cur, hcat(ind(cur), falseL, ":")) }
        }
        if !astIsNull(elseBody) {
            cur = addLine(cur, hcat(ind(cur), lastFalse, ":"))
            cur = ctxChange(cur, outerIndent + 1, outer)
            cur = functionStatements(cur, elseBody, rt)
            if !cur.ok { return cur }
            if !bodyEndsDirectly(elseBody) {
                cur = scopeStringCleanup(cur, outer.len)
                cur = addLine(cur, hcat(ind(cur), "이동 ", endL.val))
            }
            cur = ctxChange(cur, outerIndent, outer)
        }
        var allEnd = !astIsNull(elseBody)
        if allEnd { allEnd = bodyEndsDirectly(elseBody) }
        var ci = 0
        while ci < nb && allEnd {
            allEnd = bodyEndsDirectly(jAt(jAt(branches, ci), 1))
            ci += 1
        }
        if allEnd { return cur }
        return addLine(cur, hcat(ind(cur), endL.val, ":"))
    }

    // 정본: HMIR활성끝정리 (끝맥락은 TryBlock/비동기에서만 선다 — 네 입력에는 없다)
    func activeEndCleanup(_ s: HState, _ rt: BStr) -> HState {
        if astIsNull(s.endCtx) { return s }
        fatalError("미이식: HMIR활성끝정리내부")
    }

    // 정본: HMIR동적배열인덱스낮추기
    func dynArrayIndexLower(_ s: HState, _ index: J, _ natural: Bool) -> HRes {
        var direct = true
        if natural { direct = false }
        if natural && astKind(index) == "NameExpr" && astStrField(index, "name") == "위치" { direct = true }
        if direct { return lowerExpr(index, s, "u64") }
        let ov = lowerExpr(index, s, "")
        let one = nextTemp(ov.st)
        let os = addLine(one.st, hcat(ind(ov.st), one.val, ": 큰정수 = 상수값 1"))
        let zb = nextTemp(os)
        let zs = addLine(zb.st, hcat(ind(os), zb.val, ": 큰정수 = ", binaryOpDisplay("-"), " ", ov.val, ", ", one.val))
        let cv = nextTemp(zs)
        let cs = addLine(cv.st, hcat(ind(zs), cv.val, ": 큰자연수 = 변환 ", zb.val, ", 큰자연수"))
        return HRes(st: cs, val: cv.val, ty: "u64")
    }
}
