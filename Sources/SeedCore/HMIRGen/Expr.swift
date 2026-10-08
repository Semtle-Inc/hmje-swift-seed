// HMIR생성/표현식.hmje — HMIR표현식낮추기, HMIR조건낮추기

extension HMIRGenerator {

    // 정본: HMIR이름값인자벗기기
    func stripNamedArg(_ a: J) -> J {
        if jIsArray(a) && jLen(a) == 2 { return jAt(a, 1) }
        return a
    }

    /// `ind + 임시 + ": " + 표시 + 나머지` 한 줄을 내고 결과를 돌려준다.
    @inline(__always) func emitTemp(_ s: HState, _ disp: BStr, _ rest: BStr, _ ty: BStr) -> HRes {
        let t = nextTemp(s)
        return HRes(st: addLine(t.st, hcat(ind(s), t.val, ": ", disp, rest)), val: t.val, ty: ty)
    }

    // 정본: HMIR표현식낮추기
    func lowerExpr(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let kind = astKind(node)
        switch kind {
        case "AwaitExpr":
            fatalError("미이식: HMIR표현식낮추기 AwaitExpr")
        case "TryExpr":
            return lowerTry(node, s, hint)
        case "IntLiteral":
            let raw = astTagStr(astField(node, "value"), "integer")
            var it = typeResolve(hint)
            if it.count == 0 { it = "i64" }
            return emitTemp(s, typeDisplay(it), hcat(" = 상수값 ", raw), it)
        case "FloatLiteral":
            let raw = astTagStr(astField(node, "value"), "float")
            var ft = typeResolve(hint)
            if ft != "f32" && ft != "f64" { ft = "f64" }
            return emitTemp(s, typeDisplay(ft), hcat(" = 상수값 ", raw), ft)
        case "StringLiteral":
            var lt: BStr = "text"
            if typeResolve(hint) == "char" { lt = "char" }
            return emitTemp(s, typeDisplay(lt), hcat(" = 상수값 ", stringLiteralDisplay(astStrField(node, "value"))), lt)
        case "FileDataExpr":
            let ft = typeResolve(hint)
            return emitTemp(s, typeDisplay(ft), hcat(" = 파일데이터 ", stringLiteralDisplay(astStrField(node, "path"))), ft)
        case "OptionalNoneExpr":
            let ot = typeResolve(hint)
            var sn = ot
            if sn.hasPrefix("struct:") { sn = hSub(sn, 7, sn.count - 7) }
            let of = structFields(sn)
            if typeResolve(astStr(astObjField(of, "있음"))) != "bool" || astStr(astObjField(of, "값")).count == 0 {
                return exprError(s, "없음에는 선택값 타입이 필요합니다")
            }
            return emitTemp(s, typeDisplay(ot), " = 상수값 없음", ot)
        case "OptionalUnwrapExpr":
            let r = lowerExpr(astField(node, "expr"), s, "")
            if !r.st.ok { return r }
            var on = typeResolve(r.ty)
            if on.hasPrefix("struct:") { on = hSub(on, 7, on.count - 7) }
            let ut = typeResolve(astStr(astObjField(structFields(on), "값")))
            let h = emitTemp(r.st, "참거짓", hcat(" = 필드읽기 ", r.val, ".있음"), "bool")
            return emitTemp(h.st, typeDisplay(ut), hcat(" = 필드읽기 ", r.val, ".값"), ut)
        case "DynamicArrayPopExpr":
            return lowerPop(node, s, hint)
        case "BoolLiteral":
            var d: BStr = "거짓"
            if case .bool(let b) = astField(node, "value"), b { d = "참" }
            return emitTemp(s, "참거짓", hcat(" = 상수값 ", d), "bool")
        case "CastExpr":
            return lowerCast(node, s, hint)
        case "NameExpr":
            return lowerName(node, s, hint)
        case "FieldAccessExpr":
            return lowerFieldAccess(node, s, hint)
        case "AddressOfExpr":
            let an = astStrField(node, "name")
            if symType(s, an).count == 0 { return exprError(s, hcat("주소 대상이 없습니다: ", an)) }
            return emitTemp(s, "주소", hcat(" = 주소값 ", an), "address")
        case "FunctionAddressExpr":
            fatalError("미이식: HMIR표현식낮추기 FunctionAddressExpr")
        case "ClosureValueExpr":
            fatalError("미이식: HMIR표현식낮추기 ClosureValueExpr")
        case "FixedArrayFillExpr":
            let ft = typeResolve(astStrField(node, "type_name"))
            let et = typeResolve(fixedArrayElemType(ft))
            let v = lowerExpr(astField(node, "value"), s, et)
            if !v.st.ok { return v }
            var vals: BStr = ""
            let n = fixedArrayLen(ft)
            var i: UInt64 = 0
            while i < n {
                if i > 0 { vals = hcat(vals, ", ") }
                vals = hcat(vals, v.val)
                i += 1
            }
            return emitTemp(v.st, typeDisplay(ft), hcat(" = 배열값 [", vals, "]"), ft)
        case "OverlayBindExpr":
            return lowerOverlayBind(node, s)
        case "ArrayBufferViewExpr":
            let ae = astField(node, "array")
            let at = exprStaticType(ae, s)
            let gn = hcat(dynArrayFnHead(at), "동적배열가져오기")
            let gd = firstFunctionDef(gn)
            if astIsNull(gd) { return exprError(s, "버퍼뷰 배열 원소 타입을 찾을 수 없습니다") }
            let et = typeResolve(astStrField(gd, "return_type"))
            let esz = packedTypeSize(et)
            let addrE = jNode("FieldAccessExpr", ["base", "field"], [ae, .string("데이터")])
            let lenE = jNode("FieldAccessExpr", ["base", "field"], [ae, .string("길이")])
            let szI = jNode("IntLiteral", ["value"], [jObj(["integer"], [.string(hDecU(esz))])])
            let szE = jNode("CastExpr", ["type_name", "expr", "compiler_generated"], [.string("자연수64"), szI, .bool(false)])
            let blE = jNode("BinaryExpr", ["left", "op", "right"], [lenE, .string("*"), szE])
            let fl = jObj(["기준주소", "길이"], [addrE, blE])
            let se = jNode("StructInitExpr", ["name", "fields"], [.string("버퍼뷰"), fl])
            return lowerExpr(se, s, "struct:버퍼뷰")
        case "ArrayLiteral":
            return lowerArrayLiteral(node, s, hint)
        case "UnaryExpr":
            var ut = typeResolve(hint)
            if ut.count == 0 { ut = exprStaticType(astField(node, "operand"), s) }
            let o = lowerExpr(astField(node, "operand"), s, "")
            if !o.st.ok { return o }
            let op = astStrField(node, "op")
            var rest: BStr
            if op == "~" { rest = " = 비트반전 " } else { rest = hcat(" = 단항 ", op, " ") }
            rest = hcat(rest, o.val)
            return emitTemp(o.st, typeDisplay(ut), rest, ut)
        case "BinaryExpr":
            return lowerBinary(node, s, hint)
        case "IndexAccessExpr":
            return lowerIndex(node, s, hint)
        case "OffsetMemoryReadExpr":
            let rt = typeResolve(astStrField(node, "value_type"))
            let a = lowerExpr(astField(node, "address"), s, "address")
            if !a.st.ok { return a }
            var resT = rt
            let hi = typeResolve(hint)
            if hi.count > 0 && hi != rt && isNumericFamily(hi) && isNumericFamily(rt) { resT = hi }
            return emitTemp(a.st, typeDisplay(resT), hcat(" = 오프셋읽기 ", a.val, ", ", typeDisplay(rt)), resT)
        case "MemoryReadExpr":
            let bn = astField(node, "base")
            let bt = typeResolve(exprStaticType(bn, s))
            var bh: BStr = "address", ih: BStr = "i64"
            if bt == "text" { bh = "text"; ih = "u64" }
            let b = lowerExpr(bn, s, bh)
            if !b.st.ok { return b }
            let ix = lowerExpr(astField(node, "index"), b.st, ih)
            if !ix.st.ok { return ix }
            let mt = typeResolve(astStrField(node, "value_type"))
            var rest: BStr = bt == "text" ? " = 문자열바이트읽기 " : " = 포인터읽기 "
            rest = hcat(rest, b.val, ", ", ix.val)
            if bt != "text" { rest = hcat(rest, ", ", typeDisplay(mt)) }
            return emitTemp(ix.st, typeDisplay(mt), rest, mt)
        case "StructInitExpr":
            return lowerStructInit(node, s, hint)
        case "CallExpr", "Execute":
            return lowerCall(node, s, hint, kind)
        default:
            var e = hcat("미지원 표현식: ", kind)
            let ln = symType(s, "@현재줄")
            if ln.count > 0 { e = hcat(e, " (줄 ", ln, ")") }
            e = hcat(e, ": ", BStr(JSONWriter.serialize(node)))
            return exprError(s, e)
        }
    }

    func lowerTry(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let tv = lowerExpr(astField(node, "expr"), s, hint)
        if !tv.st.ok { return tv }
        if tv.ty != "i64" { return exprError(tv.st, "지금은 정수64 반환값만 시도한 값으로 처리할 수 있습니다.") }
        let fl = symType(tv.st, "@시도실패표지")
        let fv = symType(tv.st, "@시도실패변수")
        if fl.count == 0 { return exprError(tv.st, "시도는 '시도할 작업은' 블록 안에서만 사용할 수 있습니다.") }
        fatalError("미이식: TryExpr (시도 블록)")
    }

    func lowerPop(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let pn = astStrField(node, "name")
        let at = symType(s, pn)
        if at.count == 0 { return exprError(s, hcat("정의되지 않은 값입니다: ", pn)) }
        let pre = dynArrayFnHead(at)
        let fnName = hcat(pre, "동적배열꺼내기값")
        let fd = firstFunctionDef(fnName)
        var rt = typeResolve(hint)
        if !astIsNull(fd) { rt = typeResolve(astStrField(fd, "return_type")) }
        if rt.count == 0 { return exprError(s, hcat("동적배열 꺼내기 반환 타입을 찾을 수 없습니다: ", fnName)) }
        let ar = emitTemp(s, typeDisplay(at), hcat(" = 읽기 ", pn), at)
        let popped = emitTemp(ar.st, typeDisplay(rt), hcat(" = 호출 @", fnName, "[", typeDisplay(at), "](", ar.val, ")"), rt)
        let has = emitTemp(popped.st, "참거짓", hcat(" = 필드읽기 ", popped.val, ".있음"), "bool")
        let noneL = nextLabel(has.st, "꺼내기없음")
        let someL = nextLabel(noneL.st, "꺼내기있음")
        let endL = nextLabel(someL.st, "꺼내기끝")
        var cur = endL.st
        let oi = cur.indent
        cur = addLine(cur, hcat(ind(cur), "분기 ", has.val, ", ", someL.val, ", ", noneL.val))
        cur = addLine(cur, hcat(ind(cur), someL.val, ":"))
        cur = ctxChange(cur, oi + 1, cur.sym)
        let rr = emitTemp(cur, typeDisplay(at), hcat(" = 읽기 ", pn), at)
        let lr = emitTemp(rr.st, typeDisplay(at), hcat(" = 읽기 ", pn), at)
        let ln = emitTemp(lr.st, "큰자연수", hcat(" = 필드읽기 ", lr.val, ".길이"), "u64")
        let one = emitTemp(ln.st, "큰자연수", " = 상수값 1", "u64")
        let ix = emitTemp(one.st, "큰자연수", hcat(" = 빼기 ", ln.val, ", ", one.val), "u64")
        let rm = emitTemp(ix.st, typeDisplay(at), hcat(" = 호출 @", pre, "동적배열제거[", typeDisplay(at), ", 큰자연수](", rr.val, ", ", ix.val, ")"), at)
        cur = addLine(rm.st, hcat(ind(rm.st), "쓰기 ", pn, " = ", rm.val))
        cur = addLine(cur, hcat(ind(cur), "이동 ", endL.val))
        cur = ctxChange(cur, oi, cur.sym)
        cur = addLine(cur, hcat(ind(cur), noneL.val, ":"))
        cur = ctxChange(cur, oi + 1, cur.sym)
        cur = addLine(cur, hcat(ind(cur), "이동 ", endL.val))
        cur = ctxChange(cur, oi, cur.sym)
        cur = addLine(cur, hcat(ind(cur), endL.val, ":"))
        return HRes(st: cur, val: popped.val, ty: rt)
    }

    func lowerCast(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let cn = astStrField(node, "type_name")
        var ct = typeResolve(cn)
        let ebt = symType(s, hcat("@열거기반:", cn))
        if ebt.count > 0 { ct = hcat("enum:", cn) }
        let src = astField(node, "expr")
        var sh: BStr = ""
        let sk = astKind(src)
        if sk == "IntLiteral" || sk == "FloatLiteral" || sk == "StringLiteral" || sk == "ArrayLiteral" { sh = ct }
        if ebt.count > 0 { sh = ebt }
        if sk == "BinaryExpr" || sk == "UnaryExpr" { sh = "" }
        let r = lowerExpr(src, s, sh)
        if !r.st.ok { return r }
        if typeResolve(r.ty) == ct { return HRes(st: r.st, val: r.val, ty: ct) }
        let c = emitTemp(r.st, typeDisplay(ct), hcat(" = 변환 ", r.val, ", ", typeDisplay(ct)), ct)
        let hi = typeResolve(hint)
        if hi.count > 0 && hi != ct && isNumericFamily(hi) && isNumericFamily(ct) {
            return emitTemp(c.st, typeDisplay(hi), hcat(" = 변환 ", c.val, ", ", typeDisplay(hi)), hi)
        }
        return c
    }

    func lowerName(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let name = astStrField(node, "name")
        let st = symType(s, name)
        if st.count == 0 {
            let en = typeDisplay(hint)
            let ek = hcat(en, ".", name)
            if symType(s, hcat("@열거타입:", ek)).count > 0 {
                let eb = jNode("NameExpr", ["name"], [.string(en)])
                let ee = jNode("FieldAccessExpr", ["base", "field"], [eb, .string(name)])
                return lowerExpr(ee, s, hint)
            }
            let ft = typeResolve(hint)
            let fd = accessSignatureDef(name, fnValueParamTypes(ft), fnValueReturnType(ft), s)
            if isFnValueType(ft) && !astIsNull(fd) {
                if !accessAllowed(fd, s) { return exprError(s, hcat("모듈 접근 거부: 함수 값 ", name)) }
                if accessAmbiguous(fd, s) { return exprError(s, "모호한 함수 호출: 직접 가져온 모듈의 같은 서명") }
                return emitTemp(s, typeDisplay(ft), hcat(" = 함수값 ", accessCodeName(fd)), ft)
            }
            var e = hcat("값을 찾을 수 없습니다: ", name)
            let ln = symType(s, "@현재줄")
            if ln.count > 0 { e = hcat(e, " (줄 ", ln, ")") }
            return exprError(s, e)
        }
        let r = emitTemp(s, typeDisplay(st), hcat(" = 읽기 ", name), st)
        var same = st == typeResolve(hint)
        if typeDisplay(st) == typeDisplay(hint) { same = true }
        if hint.count > 0 && !same {
            return emitTemp(r.st, typeDisplay(hint), hcat(" = 변환 ", r.val, ", ", typeDisplay(hint)), typeResolve(hint))
        }
        return r
    }

    func lowerFieldAccess(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let eb = astField(node, "base")
        if astKind(eb) == "NameExpr" {
            let ek = hcat(astStrField(eb, "name"), ".", astStrField(node, "field"))
            let et = symType(s, hcat("@열거타입:", ek))
            if et.count > 0 {
                let sv = symType(s, hcat("@열거값:", ek))
                let ebt = symType(s, hcat("@열거기반:", astStrField(eb, "name")))
                var rest: BStr = " = 상수값 "
                if ebt == "text" || ebt == "char" { rest = hcat(rest, stringLiteralDisplay(sv)) } else { rest = hcat(rest, sv) }
                return emitTemp(s, typeDisplay(et), rest, et)
            }
        }
        let obt = exprStaticType(eb, s)
        if obt.hasPrefix("overlay:") {
            let os = hSub(obt, 8, obt.count - 8)
            let ofl = structFields(os)
            let ofn = astStrField(node, "field")
            var oft: BStr = ""
            var off: UInt64 = 0
            var found = false
            let ok = ofl.objectKeys, ov = ofl.objectValues
            var oi = 0
            while oi < ok.count && !found {
                if ok[oi] == ofn { oft = typeResolve(astStr(ov[oi])); found = true } else { off = off &+ packedTypeSize(astStr(ov[oi])) }
                oi += 1
            }
            if !found { return exprError(s, hcat("필드 타입을 찾을 수 없습니다: ", ofn)) }
            let ob = lowerExpr(eb, s, obt)
            let oo = emitTemp(ob.st, "큰자연수", hcat(" = 상수값 ", hDecU(off)), "u64")
            let oa = emitTemp(oo.st, "주소", hcat(" = ", binaryOpDisplay("+"), " ", ob.val, ", ", oo.val), "address")
            let orr = emitTemp(oa.st, typeDisplay(oft), hcat(" = 오프셋읽기 ", oa.val, ", ", typeDisplay(oft)), oft)
            let osz = packedTypeSize(oft)
            let en = symType(s, hcat("@구조체엔디안:", os))
            if osz > 1 && en == "big" {
                return emitTemp(orr.st, typeDisplay(oft), hcat(" = 바이트뒤집기 ", orr.val), oft)
            }
            return orr
        }
        let b = lowerExpr(eb, s, "")
        if !b.st.ok { return b }
        let fname = astStrField(node, "field")
        if fname == "원시값" {
            var rb = symType(b.st, hcat("@열거기반타입:", b.ty))
            if rb.count == 0 { rb = symType(b.st, hcat("@열거기반타입:", typeDisplay(b.ty))) }
            if rb.count > 0 { return HRes(st: b.st, val: b.val, ty: rb) }
        }
        var ft: BStr = ""
        if b.ty.hasSuffix("동적배열형") {
            if fname == "데이터" { ft = "address" }
            if fname == "길이" || fname == "용량" { ft = "u64" }
        } else if b.ty.hasPrefix("overlay_array:") {
            if fname == "기준주소" { ft = "address" }
            if fname == "길이" { ft = "u64" }
        } else if typeResolve(b.ty) == "text" {
            if fname == "주소" { ft = "address" }
            if fname == "길이" { ft = "u64" }
            if fname == "용량" || fname == "플래그" { ft = "u64" }
        } else {
            var bsn = b.ty
            if bsn.hasPrefix("struct:") { bsn = hSub(bsn, 7, bsn.count - 7) }
            var sf = structFields(bsn)
            if astIsNull(sf) && hHas(bsn, "고정배열") {
                var si = 0
                let allv = structs.objectValues
                while si < allv.count && astIsNull(sf) {
                    let cf = allv[si]
                    let cvt = astObjField(cf, "값")
                    if !astIsNull(cvt) {
                        if fixedArrayLen(typeResolve(astStr(cvt))) > 0 { sf = cf }
                    }
                    si += 1
                }
            }
            ft = typeResolve(astStr(astObjField(sf, fname)))
        }
        if ft.count == 0 {
            var e = hcat("필드 타입을 찾을 수 없습니다: ", fname, " (바탕 타입 ", b.ty, ")")
            let ln = symType(b.st, "@현재줄")
            if ln.count > 0 { e = hcat(e, " (줄 ", ln, ")") }
            return exprError(b.st, e)
        }
        let fr = emitTemp(b.st, typeDisplay(ft), hcat(" = 필드읽기 ", b.val, ".", fname), ft)
        var fst = fr.st
        var fval = fr.val
        let bk = astKind(eb)
        var baseTemp = false
        if bk == "CallExpr" || bk == "StructInitExpr" { baseTemp = true }
        if bk == "IndexAccessExpr" {
            let ibt = exprStaticType(astField(eb, "base"), fst)
            if ibt.hasSuffix("동적배열형") { baseTemp = true }
        }
        if symType(fst, hcat("@임시소유:", b.val)).count > 0 { baseTemp = true }
        var rel = isOwnedType(fst, b.ty)
        if !baseTemp { rel = false }
        if rel {
            if isOwnedType(fst, ft) {
                let k = ownedValueRetain(fst, fval, ft)
                fst = k.st
                fval = k.val
                fst = symAdd(fst, hcat("@임시소유:", fval), ft)
            }
            fst = ownedValueRelease(fst, b.val, b.ty)
        }
        return HRes(st: fst, val: fval, ty: ft)
    }

    func lowerOverlayBind(_ node: J, _ s: HState) -> HRes {
        let ot = exprStaticType(node, s)
        if astBoolField(node, "is_array") {
            let b = lowerExpr(astField(node, "buffer"), s, "struct:버퍼뷰")
            return HRes(st: b.st, val: b.val, ty: ot)
        }
        let osz = packedTypeSize(astStrField(node, "struct_name"))
        let le = jNode("FieldAccessExpr", ["base", "field"], [astField(node, "buffer"), .string("길이")])
        let l = lowerExpr(le, s, "u64")
        let szT = nextTemp(l.st)
        let szl = hcat(ind(l.st), szT.val, ": 큰자연수 = 상수값 ", hDecU(osz))
        let cmp = nextTemp(szT.st)
        let cmpl = hcat(ind(szT.st), cmp.val, ": 참거짓 = 비교 >= ", l.val, ", ", szT.val)
        let okL = nextLabel(cmp.st, "오버레이크기충분")
        let badL = nextLabel(okL.st, "오버레이크기부족")
        var cur = addLine(badL.st, szl)
        cur = addLine(cur, cmpl)
        cur = addLine(cur, hcat(ind(cur), "분기 ", cmp.val, ", ", okL.val, ", ", badL.val))
        cur = addLine(cur, hcat(ind(cur), badL.val, ":"))
        cur = ctxChange(cur, cur.indent + 1, cur.sym)
        cur = addLine(cur, hcat(ind(cur), "도달불가"))
        cur = ctxChange(cur, cur.indent - 1, cur.sym)
        cur = addLine(cur, hcat(ind(cur), okL.val, ":"))
        let ae = jNode("FieldAccessExpr", ["base", "field"], [astField(node, "buffer"), .string("기준주소")])
        let a = lowerExpr(ae, cur, "address")
        return HRes(st: a.st, val: a.val, ty: ot)
    }

    func lowerArrayLiteral(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let elems = astField(node, "elements")
        let at = typeResolve(hint)
        if at.hasSuffix("동적배열형") {
            let head = dynArrayFnHead(at)
            let cn = hcat(head, "동적배열생성")
            let an = hcat(head, "동적배열추가")
            let ad = firstFunctionDef(an)
            if astIsNull(ad) { return exprError(s, hcat("동적배열 추가 함수를 찾을 수 없습니다: ", an)) }
            let et = typeResolve(astStrField(jAt(astField(ad, "params"), 1), "type_name"))
            let c = emitTemp(s, typeDisplay(at), hcat(" = 호출 @", cn, "[]()"), at)
            var cur = c.st
            var val = c.val
            for i in 0..<jLen(elems) {
                let ee = jAt(elems, i)
                let er = lowerExpr(ee, cur, et)
                if !er.st.ok { return er }
                let ap = emitTemp(er.st, typeDisplay(at), hcat(" = 호출 @", an, "[", typeDisplay(at), ", ", typeDisplay(et), "](", val, ", ", er.val, ")"), at)
                cur = ap.st
                var ce = ee
                if astKind(ce) == "CastExpr" { ce = astField(ce, "expr") }
                var temp = false
                let ck = astKind(ce)
                if ck == "CallExpr" || ck == "ArrayLiteral" || ck == "StructInitExpr" { temp = true }
                if symType(cur, hcat("@임시소유:", er.val)).count > 0 { temp = true }
                var owned = et == "text"
                if isOwnedType(cur, et) { owned = true }
                if temp && owned { cur = ownedValueRelease(cur, er.val, et) }
                val = ap.val
            }
            cur = symAdd(cur, hcat("@임시소유:", val), at)
            return HRes(st: cur, val: val, ty: at)
        }
        let et = fixedArrayElemType(at)
        if et.count == 0 { return exprError(s, hcat("배열 원소 타입을 찾을 수 없습니다: ", at)) }
        var cur = s
        var vals: BStr = ""
        for i in 0..<jLen(elems) {
            let ee = jAt(elems, i)
            let er = lowerExpr(ee, cur, et)
            if !er.st.ok { return er }
            cur = er.st
            var ev = er.val
            let ek = astKind(ee)
            var borrow = ek == "NameExpr"
            if ek == "FieldAccessExpr" || ek == "IndexAccessExpr" || ek == "OptionalUnwrapExpr" { borrow = true }
            if borrow && isOwnedType(cur, et) {
                let k = ownedValueRetain(cur, ev, et)
                cur = k.st
                ev = k.val
            }
            if i > 0 { vals = hcat(vals, ", ") }
            vals = hcat(vals, ev)
        }
        return emitTemp(cur, typeDisplay(at), hcat(" = 배열값 [", vals, "]"), at)
    }

    func lowerBinary(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let ec = enumCompareContext(node, s)
        if !astIsNull(ec) { return lowerExpr(ec, s, hint) }
        let op = astStrField(node, "op")
        if op == "&&" || op == "||" {
            let l = lowerExpr(astField(node, "left"), s, "")
            if !l.st.ok { return l }
            if typeResolve(l.ty) != "bool" { return exprError(l.st, hcat("논리 연산의 왼쪽 값은 참거짓이어야 합니다: 실제=", l.ty)) }
            let r = lowerExpr(astField(node, "right"), l.st, "")
            if !r.st.ok { return r }
            if typeResolve(r.ty) != "bool" { return exprError(r.st, hcat("논리 연산의 오른쪽 값은 참거짓이어야 합니다: 실제=", r.ty)) }
            let lo: BStr = op == "||" ? "논리합" : "논리곱"
            return emitTemp(r.st, "참거짓", hcat(" = ", lo, " ", l.val, ", ", r.val), "bool")
        }
        if op == "+" {
            let ln = astField(node, "left")
            if typeResolve(exprStaticType(ln, s)) == "text" {
                let call = synthNode3("CallExpr", "name", "args", "compiler_generated", .string("문자열붙인값"), .array([ln, astField(node, "right")]), .bool(false))
                let cr = lowerExpr(call, s, "text")
                if !cr.st.ok { return cr }
                let st2 = symAdd(cr.st, hcat("@임시소유:", cr.val), "text")
                return HRes(st: st2, val: cr.val, ty: "text")
            }
        }
        let isCmp = op == "==" || op == "!=" || op == ">" || op == ">=" || op == "<" || op == "<="
        let isEq = op == "==" || op == "!="
        if isCmp && isEq {
            let ln = astField(node, "left")
            let rn = astField(node, "right")
            if typeResolve(exprStaticType(ln, s)) == "text" {
                let call = synthNode3("CallExpr", "name", "args", "compiler_generated", .string("문자열같은가"), .array([ln, rn]), .bool(false))
                let cr = lowerExpr(call, s, "bool")
                if op == "==" { return cr }
                return emitTemp(cr.st, "참거짓", hcat(" = 부정 ", cr.val), "bool")
            }
        }
        var ot = typeResolve(hint)
        if isCmp { ot = "" } else if ot.count == 0 { ot = typeResolve(exprStaticType(node, s)) }
        let l = lowerExpr(astField(node, "left"), s, ot)
        if !l.st.ok { return l }
        if ot.count == 0 { ot = l.ty }
        var rh = ot
        if isCmp {
            rh = ""
            if astKind(astField(node, "right")) == "IntLiteral" {
                let li = typeResolve(l.ty)
                if li.hasPrefix("i") || li.hasPrefix("u") || li == "address" { rh = li }
            }
        }
        let r = lowerExpr(astField(node, "right"), l.st, rh)
        if !r.st.ok { return r }
        if isCmp {
            var leb = symType(r.st, hcat("@열거기반타입:", l.ty))
            if leb.count == 0 { leb = symType(r.st, hcat("@열거기반타입:", typeDisplay(l.ty))) }
            var lstr = leb == "text"
            if typeResolve(l.ty) == "text" { lstr = true }
            if lstr && isEq {
                let c = emitTemp(r.st, "참거짓", hcat(" = 호출 @문자열같은가[문자열, 문자열](", l.val, ", ", r.val, ")"), "bool")
                if op == "==" { return c }
                return emitTemp(c.st, "참거짓", hcat(" = 부정 ", c.val), "bool")
            }
            return emitTemp(r.st, "참거짓", hcat(" = 비교 ", op, " ", l.val, ", ", r.val), "bool")
        }
        let od = binaryOpDisplay(op)
        if od.count == 0 { return exprError(r.st, hcat("지원하지 않는 이항 연산입니다: ", op)) }
        return emitTemp(r.st, typeDisplay(ot), hcat(" = ", od, " ", l.val, ", ", r.val), ot)
    }

    func lowerIndex(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let rbk = astKind(astField(node, "base"))
        let obt = exprStaticType(astField(node, "base"), s)
        if obt.hasPrefix("overlay_array:") {
            if astBoolField(node, "natural") { return exprError(s, "순번 오버레이 인덱스는 아직 이식 중입니다") }
            let oa = overlayArrayAddrLower(node, s, "인덱스")
            return emitTemp(oa.st, typeDisplay(oa.ty), hcat(" = 오프셋읽기 ", oa.val, ", ", typeDisplay(oa.ty)), oa.ty)
        }
        let b = lowerExpr(astField(node, "base"), s, "")
        if !b.st.ok { return b }
        var ih: BStr = ""
        if b.ty.hasSuffix("동적배열형") { ih = "u64" }
        let iv = lowerExpr(astField(node, "index"), b.st, ih)
        if !iv.st.ok { return iv }
        let et = fixedArrayElemType(b.ty)
        if et.count == 0 {
            if b.ty.hasSuffix("동적배열형") {
                let dh = dynArrayFnHead(b.ty)
                let gn = hcat(dh, "동적배열가져오기")
                let gd = firstFunctionDef(gn)
                if astIsNull(gd) { return exprError(iv.st, hcat("동적배열 가져오기 함수를 찾을 수 없습니다: ", gn)) }
                var dst = iv.st
                var dv = iv.val
                let dt = iv.ty
                if astBoolField(node, "natural") {
                    let nn = astField(node, "index")
                    var posSpecial = false
                    if astKind(nn) == "NameExpr" { posSpecial = astStrField(nn, "name") == "위치" }
                    if !posSpecial {
                        let one = emitTemp(dst, typeDisplay(dt), " = 상수값 1", dt)
                        let sub = emitTemp(one.st, typeDisplay(dt), hcat(" = 빼기 ", dv, ", ", one.val), dt)
                        dst = sub.st
                        dv = sub.val
                    }
                }
                if dt != "u64" {
                    let cv = emitTemp(dst, "큰자연수", hcat(" = 변환 ", dv, ", 큰자연수"), "u64")
                    dst = cv.st
                    dv = cv.val
                }
                let det = typeResolve(astStrField(gd, "return_type"))
                let g = emitTemp(dst, typeDisplay(det), hcat(" = 호출 @", gn, "[", typeDisplay(b.ty), ", 큰자연수](", b.val, ", ", dv, ")"), det)
                var gst = g.st
                let dbk = astKind(astField(node, "base"))
                var baseTemp = dbk == "IndexAccessExpr" || dbk == "CallExpr"
                if symType(gst, hcat("@임시소유:", b.val)).count > 0 { baseTemp = true }
                var rel = isOwnedType(gst, b.ty)
                if !baseTemp { rel = false }
                if rel { gst = ownedValueRelease(gst, b.val, b.ty) }
                if isOwnedType(gst, det) { gst = symAdd(gst, hcat("@임시소유:", g.val), det) }
                return HRes(st: gst, val: g.val, ty: det)
            }
            return exprError(iv.st, hcat("고정배열이 아닌 인덱스 접근은 아직 미지원입니다: ", b.ty))
        }
        var basis: BStr = "영기반"
        if astBoolField(node, "natural") {
            basis = "순번"
            let inode = astField(node, "index")
            if astKind(inode) == "NameExpr" && astStrField(inode, "name") == "위치" { basis = "영기반" }
        }
        var dispT = et
        let hi = typeResolve(hint)
        if hi.count > 0 && hi != et && isNumericFamily(hi) && isNumericFamily(et) { dispT = hi }
        let r = emitTemp(iv.st, typeDisplay(dispT), hcat(" = 인덱스읽기 ", b.val, "[", iv.val, "], ", basis), et)
        var ist = r.st
        var rv = r.val
        if rbk == "CallExpr" && isOwnedType(ist, et) {
            let k = ownedValueRetain(ist, rv, et)
            ist = k.st
            rv = k.val
            var n = Int(fixedArrayLen(b.ty))
            while n > 0 {
                n -= 1
                let fi = emitTemp(ist, "큰정수", hcat(" = 상수값 ", hDec(n)), "i64")
                let fv = emitTemp(fi.st, typeDisplay(et), hcat(" = 인덱스읽기 ", b.val, "[", fi.val, "], 영기반"), et)
                ist = ownedValueRelease(fv.st, fv.val, et)
            }
            ist = symAdd(ist, hcat("@임시소유:", rv), et)
        }
        return HRes(st: ist, val: rv, ty: et)
    }

    func lowerStructInit(_ node: J, _ s: HState, _ hint: BStr) -> HRes {
        let base0 = s.ownVals.count
        let sname = astStrField(node, "name")
        var hn = typeResolve(hint)
        if hn.hasPrefix("struct:") { hn = hSub(hn, 7, hn.count - 7) }
        if hn != sname && hn.hasSuffix("선택값") {
            let hf = structFields(hn)
            let ovt = typeResolve(astStr(astObjField(hf, "값")))
            let tag = typeResolve(astStr(astObjField(hf, "있음")))
            if tag == "bool" && typeDisplay(ovt) == typeDisplay(hcat("struct:", sname)) {
                return optionalSomeLower(s, node, hint)
            }
        }
        let df = structFields(sname)
        let vf = astField(node, "fields")
        var cur = s
        var list: BStr = ""
        let dk = df.objectKeys, dv = df.objectValues
        for i in 0..<dk.count {
            let fname = dk[i]
            let ft = typeResolve(astStr(dv[i]))
            let fnode = astObjField(vf, fname)
            var fr = lowerExpr(fnode, cur, ft)
            if !fr.st.ok { return fr }
            let fk = astKind(fnode)
            var borrow = fk == "NameExpr"
            if fk == "FieldAccessExpr" { borrow = true }
            if fk == "OptionalUnwrapExpr" { borrow = true }
            if symType(fr.st, hcat("@임시소유:", fr.val)).count > 0 { borrow = false }
            if fk == "NameExpr" && isOwnedType(fr.st, ft) {
                let on = astStrField(fnode, "name")
                if symType(fr.st, hcat("@소비:", on)).count > 0 {
                    borrow = false
                    let ms = structFieldConsumeMove(fr.st, on, fr.val, ft)
                    fr = HRes(st: ms, val: fr.val, ty: fr.ty)
                }
            }
            if ft == "text" && borrow {
                let k = emitTemp(fr.st, "문자열", hcat(" = 호출 @문자열참조[문자열](", fr.val, ")"), "text")
                fr = k
            }
            if typeDisplay(ft).hasSuffix("의 배열") && borrow {
                let k = dynArrayUnaryCall(fr.st, fr.val, ft, "동적배열참조", true)
                fr = HRes(st: k.st, val: k.val, ty: ft)
            }
            var sk = isOwnedType(fr.st, ft)
            if ft == "text" || typeDisplay(ft).hasSuffix("의 배열") { sk = false }
            if sk && borrow {
                let k = ownedValueRetain(fr.st, fr.val, ft)
                fr = HRes(st: k.st, val: k.val, ty: ft)
            }
            cur = fr.st
            if isOwnedType(cur, ft) { cur = ownAdd(cur, fr.val, ft) }
            if i > 0 { list = hcat(list, ", ") }
            list = hcat(list, fname, ": ", fr.val)
        }
        var st2 = typeResolve(hint)
        if st2.count == 0 { st2 = hcat("struct:", sname) }
        let r = emitTemp(cur, typeDisplay(st2), hcat(" = 구조체값 ", sname, "(", list, ")"), st2)
        return HRes(st: ownRestoreLen(r.st, base0), val: r.val, ty: st2)
    }

    func lowerCall(_ node: J, _ s: HState, _ hint: BStr, _ kind: BStr) -> HRes {
        let name = astStrField(node, "name")
        var portT: BStr = ""
        if name == "포트쓰기8" || name == "포트읽기8" { portT = "u8" }
        if name == "포트쓰기16" || name == "포트읽기16" { portT = "u16" }
        if name == "포트쓰기32" || name == "포트읽기32" { portT = "u32" }
        if portT.count > 0 {
            let pargs = astField(node, "args")
            let pn = lowerExpr(stripNamedArg(jAt(pargs, 0)), s, "")
            if !pn.st.ok { return pn }
            if name.hasPrefix("포트읽기") {
                return emitTemp(pn.st, typeDisplay(portT), hcat(" = 포트읽기 ", pn.val, ", ", typeDisplay(portT)), portT)
            }
            let pv = lowerExpr(stripNamedArg(jAt(pargs, 1)), pn.st, "")
            if !pv.st.ok { return pv }
            let ps = addLine(pv.st, hcat(ind(pv.st), "포트쓰기 ", pn.val, ", ", pv.val, ", ", typeDisplay(portT)))
            return HRes(st: ps, val: "void", ty: "void")
        }
        let attr = astObjectAttrField(name)
        let aargs = astField(node, "args")
        if attr.count > 0 && jLen(aargs) == 1 {
            let ab = jAt(aargs, 0)
            let abt = exprStaticType(ab, s)
            var asn = typeResolve(abt)
            if asn.hasPrefix("struct:") { asn = hSub(asn, 7, asn.count - 7) }
            if !astIsNull(astObjField(structFields(asn), attr)) {
                let an = jNode("FieldAccessExpr", ["base", "field"], [ab, .string(attr)])
                return lowerExpr(an, s, hint)
            }
        }
        if name == "원자읽기64" {
            let a = lowerExpr(jAt(astField(node, "args"), 0), s, "address")
            if !a.st.ok { return a }
            return emitTemp(a.st, "자연수64", hcat(" = 원자읽기64 ", a.val), "u64")
        }
        if name == "원자교환64" || name == "원자더하기64" {
            let xa = astField(node, "args")
            let a = lowerExpr(jAt(xa, 0), s, "address")
            if !a.st.ok { return a }
            let v = lowerExpr(jAt(xa, 1), a.st, "u64")
            if !v.st.ok { return v }
            return emitTemp(v.st, "자연수64", hcat(" = ", name, " ", a.val, ", ", v.val), "u64")
        }
        if name == "문자열구성" {
            var cur = s
            var vals: BStr = ""
            for i in 0..<jLen(aargs) {
                let h: BStr = i == 0 ? "address" : "u64"
                let r = lowerExpr(jAt(aargs, i), cur, h)
                if !r.st.ok { return r }
                cur = r.st
                if i > 0 { vals = hcat(vals, ", ") }
                vals = hcat(vals, r.val)
            }
            return emitTemp(cur, "문자열", hcat(" = 문자열구성 ", vals), "text")
        }
        let cargs = aargs
        if name == "빠른실수32배열곱더하기16" || name == "빠른실수32최댓값16" || name == "빠른실수32합8" || name == "빠른실수32Q8_0양자화32" || isPackedDot(name) || isPackedAcc(name) {
            var vs = s
            var vl: [BStr] = []
            for i in 0..<jLen(cargs) {
                let va = stripNamedArg(jAt(cargs, i))
                let vt = exprStaticType(va, vs)
                let vr = lowerExpr(va, vs, vt)
                if !vr.st.ok { return vr }
                vs = vr.st
                vl.append(vr.val)
            }
            var line = ind(vs)
            var rv: BStr = "void", rt: BStr = "void"
            if name == "빠른실수32최댓값16" || name == "빠른실수32합8" {
                let t = nextTemp(vs); vs = t.st; rv = t.val; rt = "f32"
                line = hcat(line, t.val, ": 실수32 = ")
            } else if isPackedDot(name) {
                let t = nextTemp(vs); vs = t.st; rv = t.val; rt = "i64"
                line = hcat(line, t.val, ": 정수64 = ")
            }
            line = hcat(line, name, " ")
            for (i, x) in vl.enumerated() {
                if i > 0 { line = hcat(line, ", ") }
                line = hcat(line, x)
            }
            return HRes(st: addLine(vs, line), val: rv, ty: rt)
        }
        if name == "같은지" && jLen(cargs) == 2 && !isUserEquality(cargs, s) {
            let le = jAt(cargs, 0), re = jAt(cargs, 1)
            var et = exprStaticType(le, s)
            if et.count == 0 { et = exprStaticType(re, s) }
            if typeResolve(et) == "text" {
                let sn = jNode("CallExpr", ["name", "args", "compiler_generated"], [.string("문자열같은가"), cargs, .bool(false)])
                return lowerExpr(sn, s, "bool")
            }
            let l = lowerExpr(le, s, et)
            if !l.st.ok { return l }
            let r = lowerExpr(re, l.st, et)
            if !r.st.ok { return r }
            if l.ty.hasPrefix("struct:") || !astIsNull(structFields(l.ty)) {
                let c = equalityValueLower(r.st, l.val, r.val, l.ty)
                var cs = equalityTempCleanup(c.st, le, l.val, l.ty)
                cs = equalityTempCleanup(cs, re, r.val, r.ty)
                return HRes(st: cs, val: c.val, ty: c.ty)
            }
            return emitTemp(r.st, "참거짓", hcat(" = 비교 == ", l.val, ", ", r.val), "bool")
        }
        if name == "출력" && jLen(cargs) == 1 {
            let pa = stripNamedArg(jAt(cargs, 0))
            var pt = exprStaticType(pa, s)
            if !functionTypeDefExists("출력", pt) {
                let pr = lowerExpr(pa, s, pt)
                if pr.ty.count > 0 { pt = pr.ty }
                if pt.count == 0 { pt = pr.ty }
                if pt.count == 0 {
                    var e = hcat("출력 타입을 추론할 수 없습니다: ", astKind(pa))
                    if astKind(pa) == "NameExpr" { e = hcat(e, " ", astStrField(pa, "name")) }
                    if astKind(pa) == "IndexAccessExpr" {
                        let eb = astField(pa, "base")
                        if astKind(eb) == "NameExpr" { e = hcat(e, " ", astStrField(eb, "name")) }
                    }
                    return exprError(pr.st, e)
                }
                var ps = pr.st
                if functionTypeDefExists("출력", pt) {
                    ps = addLine(ps, hcat(ind(ps), "호출 @출력[", typeDisplay(pt), "](", pr.val, ")"))
                } else {
                    ps = genPrint(ps, pr.val, pt, false)
                    ps = printString(ps, "\n")
                }
                return HRes(st: ps, val: "void", ty: "void")
            }
        }
        if name == "작은지" || name == "큰지" {
            if jLen(cargs) == 2 {
                let ln = stripNamedArg(jAt(cargs, 0))
                let rn = stripNamedArg(jAt(cargs, 1))
                let lt = typeResolve(exprStaticType(ln, s))
                var numeric = lt.hasPrefix("i")
                if lt.hasPrefix("u") || lt.hasPrefix("f") { numeric = true }
                if numeric {
                    let l = lowerExpr(ln, s, "")
                    let r = lowerExpr(rn, l.st, l.ty)
                    let op: BStr = name == "큰지" ? "> " : "< "
                    return emitTemp(r.st, "참거짓", hcat(" = 비교 ", op, l.val, ", ", r.val), "bool")
                }
            }
        }
        if name == "자연어길이" || name == "자연어용량" || name == "자연어비었는지" || name == "자연어주소" {
            let nb = jAt(cargs, 0)
            let nt = exprStaticType(nb, s)
            if name == "자연어길이" {
                if typeResolve(nt) == "text" {
                    return lowerExpr(jNode("CallExpr", ["name", "args"], [.string("문자열길이"), .array([nb])]), s, hint)
                }
                return lowerExpr(jNode("FieldAccessExpr", ["base", "field"], [nb, .string("길이")]), s, hint)
            }
            if name == "자연어용량" {
                return lowerExpr(jNode("FieldAccessExpr", ["base", "field"], [nb, .string("용량")]), s, hint)
            }
            if name == "자연어비었는지" {
                if typeResolve(nt) == "text" {
                    return lowerExpr(jNode("CallExpr", ["name", "args"], [.string("문자열비었는가"), .array([nb])]), s, "bool")
                }
                let lc = jNode("CallExpr", ["name", "args"], [.string("자연어길이"), .array([nb])])
                let z = jNode("IntLiteral", ["value"], [jObj(["integer"], [.string("0")])])
                let be = jNode("BinaryExpr", ["left", "op", "right"], [lc, .string("=="), z])
                return lowerExpr(be, s, "bool")
            }
            if name == "자연어주소" {
                if typeResolve(nt) == "text" {
                    return lowerExpr(jNode("CallExpr", ["name", "args"], [.string("문자열주소"), .array([nb])]), s, "address")
                }
                if astKind(nb) == "NameExpr" {
                    return lowerExpr(jNode("AddressOfExpr", ["name"], [.string(astStrField(nb, "name"))]), s, "address")
                }
            }
        }
        let brt = builtinCallReturnType(name)
        if brt.count > 0 {
            var cur = s
            var vals: BStr = ""
            for i in 0..<jLen(cargs) {
                let r = lowerExpr(stripNamedArg(jAt(cargs, i)), cur, "")
                cur = r.st
                if i > 0 { vals = hcat(vals, ", ") }
                vals = hcat(vals, r.val)
            }
            if brt == "void" {
                var line = hcat(ind(cur), name)
                if vals.count > 0 { line = hcat(line, " ", vals) }
                return HRes(st: addLine(cur, line), val: "void", ty: "void")
            }
            return emitTemp(cur, typeDisplay(brt), hcat(" = ", name, " ", vals), brt)
        }
        let def = callDefSelect(name, cargs, s)
        if !astBoolField(node, "compiler_generated") && !astIsNull(def) && !accessAllowed(def, s) {
            return exprError(s, hcat("모듈 접근 거부: 선택된 overload ", name))
        }
        if !astIsNull(def) && accessAmbiguous(def, s) {
            return exprError(s, "모호한 함수 호출: 직접 가져온 모듈의 같은 서명")
        }
        if !astIsNull(def) && astBoolField(def, "is_async") {
            return exprError(s, hcat("비동기 함수는 기다린 결과 또는 동시 작업으로 호출해야 합니다: ", name))
        }
        if astIsNull(def) {
            return lowerCallNoDef(node, s, hint, name, cargs)
        }
        let params = astField(def, "params")
        let args = cargs
        if jLen(params) != jLen(args) { return exprError(s, hcat("인자 수가 맞지 않습니다: ", name)) }
        var cur = s
        let base0 = s.ownVals.count
        var argVals: BStr = ""
        var argTypes: BStr = ""
        var tmpStrs: [BStr] = []
        var tmpOwnVals: [BStr] = []
        var tmpOwnTypes: [BStr] = []
        var srcNames: [BStr] = []
        for i in 0..<jLen(args) {
            let p = jAt(params, i)
            let pt = typeResolve(astStrField(p, "type_name"))
            let actual = stripNamedArg(jAt(args, i))
            let ak = astKind(actual)
            var srcName: BStr = ""
            if ak == "NameExpr" { srcName = astStrField(actual, "name") }
            srcNames.append(srcName)
            var idxDyn = false
            if ak == "IndexAccessExpr" {
                let bt = exprStaticType(astField(actual, "base"), cur)
                if dynArrayFnHead(bt).count > 0 { idxDyn = true }
            }
            var on = pt
            if on.hasPrefix("struct:") { on = hSub(on, 7, on.count - 7) }
            var wrap = on.hasSuffix("선택값")
            if wrap {
                let ovt = typeResolve(astStr(astObjField(structFields(on), "값")))
                let at = exprStaticType(actual, cur)
                if at.count > 0 && typeDisplay(at) != typeDisplay(ovt) { wrap = false }
            }
            if ak == "OptionalNoneExpr" || ak == "StructInitExpr" || ak == "DynamicArrayPopExpr" { wrap = false }
            if exprStaticType(actual, cur) == pt { wrap = false }
            var ar: HRes
            if wrap { ar = optionalSomeLower(cur, actual, pt) } else { ar = lowerExpr(actual, cur, pt) }
            if !ar.st.ok { return ar }
            if !callTypeCompatible(ar.ty, pt) {
                return exprError(ar.st, hcat("호출 인자 타입이 맞지 않습니다: ", name, " 기대=", pt, " 실제=", ar.ty))
            }
            if astBoolField(p, "consuming") { ar = asyncArgOwn(ar, actual, true) }
            cur = ar.st
            if i > 0 { argVals = hcat(argVals, ", "); argTypes = hcat(argTypes, ", ") }
            argVals = hcat(argVals, ar.val)
            argTypes = hcat(argTypes, typeDisplay(pt))
            var ca = actual
            if astKind(actual) == "CastExpr" { ca = astField(actual, "expr") }
            let cak = astKind(ca)
            if ar.ty == "text" {
                var tempStr = cak == "CallExpr" || cak == "IndexAccessExpr"
                let tmark = symType(cur, hcat("@임시소유:", ar.val)).count > 0
                if tmark { tempStr = true }
                if cak == "CallExpr" {
                    if astObjectAttrField(astStrField(ca, "name")).count > 0 { tempStr = false }
                }
                if ak == "IndexAccessExpr" {
                    tempStr = false
                    if idxDyn || tmark { tempStr = true }
                }
                if tempStr && !astBoolField(p, "consuming") {
                    tmpStrs.append(ar.val)
                    cur = ownAdd(cur, ar.val, "text")
                }
            }
            var ownT = isOwnedType(cur, ar.ty)
            if ar.ty == "text" { ownT = false }
            var tempE = cak == "CallExpr"
            if wrap { tempE = true }
            if cak == "IndexAccessExpr" { tempE = true }
            if cak == "StructInitExpr" || cak == "StructValueExpr" || cak == "StructUpdateExpr" { tempE = true }
            let omark = symType(cur, hcat("@임시소유:", ar.val)).count > 0
            if omark { tempE = true }
            if ak == "IndexAccessExpr" {
                tempE = false
                if idxDyn || omark { tempE = true }
            }
            if ownT && tempE && !astBoolField(p, "consuming") {
                tmpOwnVals.append(ar.val)
                tmpOwnTypes.append(ar.ty)
                cur = ownAdd(cur, ar.val, ar.ty)
            }
        }
        var ri = typeResolve(astStrField(def, "return_type"))
        if ri.count == 0 { ri = "void" }
        let ext = astField(def, "external_name")
        var sym: BStr = "@"
        if !astIsNull(ext) { sym = hcat("@외부:", astStr(ext)) } else { sym = hcat(sym, accessCodeName(def)) }
        sym = hcat(sym, "[", argTypes, "]")
        let isExec = kind == "Execute"
        if ri == "void" {
            var vs = addLine(cur, hcat(ind(cur), "호출 ", sym, "(", argVals, ")"))
            var k = tmpStrs.count
            while k > 0 {
                k -= 1
                vs = addLine(vs, hcat(ind(vs), "호출 @문자열해제[문자열](", tmpStrs[k], ")"))
            }
            vs = ownedTempArgsRelease(vs, tmpOwnVals, tmpOwnTypes)
            vs = ownRestoreLen(vs, base0)
            vs = callConsumeMoves(vs, args, params, srcNames, isExec, true, "")
            return HRes(st: vs, val: "void", ty: "void")
        }
        let t = nextTemp(cur)
        var ns = addLine(t.st, hcat(ind(cur), t.val, ": ", typeDisplay(ri), " = 호출 ", sym, "(", argVals, ")"))
        var rv = t.val
        var rt = ri
        let hi = typeResolve(hint)
        if hi.count > 0 && hi != ri && isNumericFamily(hi) && isNumericFamily(ri) {
            let c = emitTemp(ns, typeDisplay(hi), hcat(" = 변환 ", t.val, ", ", typeDisplay(hi)), hi)
            ns = c.st
            rv = c.val
            rt = hi
        }
        var k = tmpStrs.count
        while k > 0 {
            k -= 1
            ns = addLine(ns, hcat(ind(ns), "호출 @문자열해제[문자열](", tmpStrs[k], ")"))
        }
        ns = ownedTempArgsRelease(ns, tmpOwnVals, tmpOwnTypes)
        ns = ownRestoreLen(ns, base0)
        ns = callConsumeMoves(ns, args, params, srcNames, isExec, true, "")
        return HRes(st: ns, val: rv, ty: rt)
    }

    func lowerCallNoDef(_ node: J, _ s: HState, _ hint: BStr, _ name: BStr, _ cargs: J) -> HRes {
        let ift = symType(s, name)
        if isAsyncFnValueType(ift) { return exprError(s, hcat("비동기 함수값은 기다린 결과로 호출해야 합니다: ", name)) }
        if isFnValueType(ift) {
            var cur = s
            var vals: BStr = ""
            let ips = fnValueParamTypes(ift)
            for i in 0..<jLen(cargs) {
                let a = jAt(cargs, i)
                var h = exprStaticType(a, cur)
                if i < ips.count && ips[i].count > 0 { h = ips[i] }
                let r = lowerExpr(a, cur, h)
                cur = r.st
                if i > 0 { vals = hcat(vals, ", ") }
                vals = hcat(vals, r.val)
            }
            var irt = fnValueReturnType(ift)
            if irt.count == 0 { irt = typeResolve(hint) }
            if irt == "void" {
                return HRes(st: addLine(cur, hcat(ind(cur), "간접호출 ", name, "(", vals, ")")), val: "void", ty: "void")
            }
            return emitTemp(cur, typeDisplay(irt), hcat(" = 간접호출 ", name, "(", vals, ")"), irt)
        }
        let kt = kernelBuiltinReturnType(name)
        if kt.count > 0 {
            var ks = s
            var kv: BStr = ""
            for i in 0..<jLen(cargs) {
                let r = lowerExpr(stripNamedArg(jAt(cargs, i)), ks, "")
                ks = r.st
                if !ks.ok { return r }
                if i > 0 { kv = hcat(kv, ", ") }
                kv = hcat(kv, r.val)
            }
            let kop = kernelBuiltinOpName(name)
            if kt == "void" {
                var line = hcat(ind(ks), kop)
                if kv.count > 0 { line = hcat(line, " ", kv) }
                return HRes(st: addLine(ks, line), val: "void", ty: "void")
            }
            let t = nextTemp(ks)
            var line = hcat(ind(ks), t.val, ": ")
            if name == "인터럽트플래그" { line = hcat(line, "자연수64") } else { line = hcat(line, typeDisplay(kt)) }
            line = hcat(line, " = ", kop)
            if kv.count > 0 { line = hcat(line, " ", kv) }
            return HRes(st: addLine(t.st, line), val: t.val, ty: kt)
        }
        var e = hcat("함수를 찾을 수 없습니다: ", name)
        let fc = firstFunctionDef(name)
        if !astIsNull(fc) {
            let fp = astField(fc, "params")
            for i in 0..<jLen(cargs) {
                var a = jAt(cargs, i)
                if jIsArray(a) && jLen(a) == 2 { a = jAt(a, 1) }
                let actual = exprStaticType(a, s)
                var expected: BStr = "없음"
                if i < jLen(fp) { expected = typeResolve(astStrField(jAt(fp, i), "type_name")) }
                if !callTypeCompatible(actual, expected) {
                    e = hcat(e, " [인자 ", hDec(i + 1), ": 기대=", expected, ", 실제=", actual, ", 식=", astKind(a), "]")
                }
            }
        }
        return exprError(s, e)
    }

    // 정본: HMIR조건낮추기
    func conditionLower(_ node: J, _ s: HState) -> HRes {
        let kind = astKind(node)
        switch kind {
        case "OptionalBindCondition":
            let v = lowerExpr(astField(node, "expr"), s, "")
            if !v.st.ok { return v }
            return emitTemp(v.st, "참거짓", hcat(" = 필드읽기 ", v.val, ".있음"), "bool")
        case "OptionalHasValueCondition":
            let v = lowerExpr(astField(node, "expr"), s, "")
            if !v.st.ok { return v }
            let h = emitTemp(v.st, "참거짓", hcat(" = 필드읽기 ", v.val, ".있음"), "bool")
            if astBoolField(node, "has_value") { return h }
            return emitTemp(h.st, "참거짓", hcat(" = 부정 ", h.val), "bool")
        case "BoolExprCondition":
            let e = astField(node, "expr")
            let et = exprStaticType(e, s)
            if typeResolve(et).hasSuffix("선택값") {
                let v = lowerExpr(e, s, "")
                if !v.st.ok { return v }
                return emitTemp(v.st, "참거짓", hcat(" = 필드읽기 ", v.val, ".있음"), "bool")
            }
            return lowerExpr(e, s, "bool")
        case "CompareCondition":
            let ec = enumCompareContext(node, s)
            if !astIsNull(ec) { return conditionLower(ec, s) }
            let op = astStrField(node, "op")
            let ln = astField(node, "left")
            let rn = astField(node, "right")
            let lst = exprStaticType(ln, s)
            var strCmp = typeResolve(lst) == "text"
            var eb = symType(s, hcat("@열거기반타입:", lst))
            if eb.count == 0 { eb = symType(s, hcat("@열거기반타입:", typeDisplay(lst))) }
            if eb == "text" { strCmp = true }
            if (strCmp && op == "==") || (strCmp && op == "!=") {
                if eb == "text" {
                    let l = lowerExpr(ln, s, "")
                    let r = lowerExpr(rn, l.st, "")
                    let c = emitTemp(r.st, "참거짓", hcat(" = 호출 @문자열같은가[문자열, 문자열](", l.val, ", ", r.val, ")"), "bool")
                    if op == "==" { return c }
                    return emitTemp(c.st, "참거짓", hcat(" = 부정 ", c.val), "bool")
                }
                let ce = jNode("CallExpr", ["name", "args", "compiler_generated"], [.string("문자열같은가"), .array([ln, rn]), .bool(false)])
                let cr = lowerExpr(ce, s, "bool")
                if op == "==" { return cr }
                return emitTemp(cr.st, "참거짓", hcat(" = 부정 ", cr.val), "bool")
            }
            var lh: BStr = ""
            if astKind(ln) == "IntLiteral" && astKind(rn) != "IntLiteral" { lh = exprStaticType(rn, s) }
            let l = lowerExpr(ln, s, lh)
            if !l.st.ok { return l }
            var rh: BStr = ""
            if astKind(rn) == "IntLiteral" {
                let li = typeResolve(l.ty)
                if li.hasPrefix("i") || li.hasPrefix("u") || li == "address" { rh = li }
            }
            let r = lowerExpr(rn, l.st, rh)
            if !r.st.ok { return r }
            return emitTemp(r.st, "참거짓", hcat(" = 비교 ", op, " ", l.val, ", ", r.val), "bool")
        case "LogicalCondition":
            let l = conditionLower(astField(node, "left"), s)
            if !l.st.ok { return l }
            let r = conditionLower(astField(node, "right"), l.st)
            if !r.st.ok { return r }
            let lo: BStr = astStrField(node, "op") == "또는" ? "논리합" : "논리곱"
            return emitTemp(r.st, "참거짓", hcat(" = ", lo, " ", l.val, ", ", r.val), "bool")
        case "NotCondition":
            let o = conditionLower(astField(node, "condition"), s)
            if !o.st.ok { return o }
            return emitTemp(o.st, "참거짓", hcat(" = 부정 ", o.val), "bool")
        default:
            return exprError(s, hcat("미지원 조건: ", kind))
        }
    }
}
