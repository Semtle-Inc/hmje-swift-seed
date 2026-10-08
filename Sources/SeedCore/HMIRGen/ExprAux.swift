// HMIR생성/표현식_보조.hmje, 표현식_타입.hmje, 표현식_정적타입.hmje, 표현식_출력.hmje

extension HMIRGenerator {

    // MARK: 표현식_보조.hmje

    // 정본: HMIR구조체필드소비이동
    func structFieldConsumeMove(_ s: HState, _ name: BStr, _ v: BStr, _ t: BStr) -> HState {
        var cur = addLine(s, hcat(ind(s), "소유권이동 ", name, " -> ", v))
        var mark: BStr = "@해제struct:"
        if typeResolve(t) == "text" { mark = "@해제text:" }
        else if typeDisplay(t).hasSuffix("의 배열") { mark = "@해제arr:" }
        else if typeResolve(t).hasSuffix("문자열선택값") { mark = "@해제선택text:" }
        cur = symAdd(cur, hcat(mark, name), "bool")
        return cur
    }

    // 정본: HMIR문자열리터럴표시
    func stringLiteralDisplay(_ v: BStr) -> BStr {
        let useDouble = hHas(v, "'") && !hHas(v, "\"")
        var out: [UInt8] = [useDouble ? 34 : 39]
        v.withBytes { p in
            for b in p {
                switch b {
                case 10: out.append(92); out.append(110)
                case 9: out.append(92); out.append(116)
                case 13: out.append(92); out.append(114)
                case 0: out.append(92); out.append(48)
                case 92: out.append(92); out.append(92)
                case 39:
                    if useDouble { out.append(39) } else { out.append(92); out.append(39) }
                case 34 where useDouble: out.append(92); out.append(34)
                default: out.append(b)
                }
            }
        }
        out.append(useDouble ? 34 : 39)
        return BStr(out)
    }

    // 정본: HMIR이항연산표시
    func binaryOpDisplay(_ op: BStr) -> BStr {
        switch op {
        case "+": return "더하기"
        case "-": return "빼기"
        case "*": return "곱하기"
        case "/": return "나누기"
        case "%": return "나머지"
        case "&": return "비트곱"
        case "|": return "비트합"
        case "^": return "비트배타합"
        case "<<": return "왼쪽이동"
        case ">>": return "오른쪽이동"
        default: return ""
        }
    }

    // 정본: HMIR호출소비이동들
    func callConsumeMoves(_ s: HState, _ args: J, _ params: J, _ srcNames: [BStr], _ allowLocal: Bool, _ allowParam: Bool, _ keep: BStr) -> HState {
        var cur = s
        for i in 0..<jLen(args) {
            let p = jAt(params, i)
            let ptn = astStrField(p, "type_name")
            var ownedCons = typeDisplay(ptn).hasSuffix("의 배열")
            if typeResolve(ptn) == "text" { ownedCons = true }
            if isOwnedType(cur, ptn) { ownedCons = true }
            let pd = typeDisplay(ptn)
            if pd.hasSuffix(" 보내는 채널") || pd.hasSuffix(" 받는 채널") { ownedCons = true }
            if astBoolField(p, "consuming") && ownedCons {
                var actual = jAt(args, i)
                if jIsArray(actual) && jLen(actual) == 2 { actual = jAt(actual, 1) }
                var real: BStr = ""
                if i < srcNames.count { real = srcNames[i] }
                if real.count == 0 && astKind(actual) == "NameExpr" { real = astStrField(actual, "name") }
                if real.count > 0 {
                    let isParam = symType(cur, hcat("@소비:", real)).count > 0
                    let isStr = symType(cur, hcat("@지역text:", real)).count > 0
                    let isArr = symType(cur, hcat("@소유:", real)).count > 0
                    let isStruct = symType(cur, hcat("@소유struct:", real)).count > 0
                    let isOptStr = symType(cur, hcat("@소유선택text:", real)).count > 0
                    var moved = false
                    let mark = hcat("@호출이동:", symType(cur, "@현재줄"), ":", real)
                    if symType(cur, mark).count > 0 { moved = true }
                    var target = false
                    if isParam && allowParam { target = true }
                    if allowLocal && (isStr || isArr || isStruct || isOptStr) { target = true }
                    if real == keep { target = false }
                    if moved { target = false }
                    if target {
                        cur = addLine(cur, hcat(ind(cur), "소유권이동 ", real, " -> 호출"))
                        cur = symAdd(cur, mark, "bool")
                        if isStr { cur = symAdd(cur, hcat("@해제text:", real), "bool") }
                        if isArr { cur = symAdd(cur, hcat("@해제arr:", real), "bool") }
                        if isStruct { cur = symAdd(cur, hcat("@해제struct:", real), "bool") }
                        if isOptStr { cur = symAdd(cur, hcat("@해제선택text:", real), "bool") }
                    }
                }
            }
        }
        return cur
    }

    // 정본: HMIR오버레이배열주소낮추기
    func overlayArrayAddrLower(_ node: J, _ s: HState, _ tag: BStr) -> HRes {
        let bt = exprStaticType(astField(node, "base"), s)
        let et = typeResolve(hSub(bt, 14, bt.count - 14))
        let esz = packedElemSize(et)
        let idx = lowerExpr(astField(node, "index"), s, "u64")
        let le = jNode("FieldAccessExpr", ["base", "field"], [astField(node, "base"), .string("길이")])
        let len = lowerExpr(le, idx.st, "u64")
        let sz = nextTemp(len.st)
        let szl = hcat(ind(len.st), sz.val, ": 큰자연수 = 상수값 ", hDecU(esz))
        let szs = addLine(sz.st, szl)
        let cnt = nextTemp(szs)
        let cntl = hcat(ind(szs), cnt.val, ": 큰자연수 = ", binaryOpDisplay("/"), " ", len.val, ", ", sz.val)
        let cmp = nextTemp(cnt.st)
        let cmpl = hcat(ind(cnt.st), cmp.val, ": 참거짓 = 비교 < ", idx.val, ", ", cnt.val)
        let ok = nextLabel(cmp.st, hcat("슬라이스", tag, "충분"))
        let over = nextLabel(ok.st, hcat("슬라이스", tag, "초과"))
        var cur = addLine(over.st, cntl)
        cur = addLine(cur, cmpl)
        cur = addLine(cur, hcat(ind(cur), "분기 ", cmp.val, ", ", ok.val, ", ", over.val))
        cur = addLine(cur, hcat(ind(cur), over.val, ":"))
        cur = ctxChange(cur, cur.indent + 1, cur.sym)
        cur = addLine(cur, hcat(ind(cur), "도달불가"))
        cur = ctxChange(cur, cur.indent - 1, cur.sym)
        cur = addLine(cur, hcat(ind(cur), ok.val, ":"))
        let ae = jNode("FieldAccessExpr", ["base", "field"], [astField(node, "base"), .string("기준주소")])
        let av = lowerExpr(ae, cur, "address")
        let i64 = lowerExpr(astField(node, "index"), av.st, "u64")
        let sz2 = nextTemp(i64.st)
        cur = addLine(sz2.st, hcat(ind(i64.st), sz2.val, ": 큰자연수 = 상수값 ", hDecU(esz)))
        let by = nextTemp(cur)
        cur = addLine(by.st, hcat(ind(cur), by.val, ": 자연수64 = ", binaryOpDisplay("*"), " ", i64.val, ", ", sz2.val))
        let ra = nextTemp(cur)
        let done = addLine(ra.st, hcat(ind(cur), ra.val, ": 주소 = ", binaryOpDisplay("+"), " ", av.val, ", ", by.val))
        return HRes(st: done, val: ra.val, ty: et)
    }

    // 정본: HMIR동적배열단항호출
    func dynArrayUnaryCall(_ s: HState, _ v: BStr, _ t: BStr, _ tail: BStr, _ hasRet: Bool) -> HRes {
        let fn = hcat(dynArrayFnHead(t), tail)
        if hasRet {
            let tmp = nextTemp(s)
            let line = hcat(ind(s), tmp.val, ": ", typeDisplay(t), " = 호출 @", fn, "[", typeDisplay(t), "](", v, ")")
            return HRes(st: addLine(tmp.st, line), val: tmp.val, ty: t)
        }
        let line = hcat(ind(s), "호출 @", fn, "[", typeDisplay(t), "](", v, ")")
        return HRes(st: addLine(s, line), val: "void", ty: "void")
    }

    // 정본: HMIR임시소유인자들해제
    func ownedTempArgsRelease(_ s: HState, _ vals: [BStr], _ types: [BStr]) -> HState {
        var cur = s
        var i = vals.count
        while i > 0 {
            i -= 1
            cur = ownedValueRelease(cur, vals[i], i < types.count ? types[i] : "")
        }
        return cur
    }

    // 정본: HMIR비동기인자소유
    func asyncArgOwn(_ r: HRes, _ arg: J, _ consuming: Bool) -> HRes {
        if !isOwnedType(r.st, r.ty) { return r }
        var ca = arg
        while astKind(ca) == "CastExpr" || astKind(ca) == "TryExpr" { ca = astField(ca, "expr") }
        let kind = astKind(ca)
        if consuming && kind == "NameExpr" {
            let n = astStrField(ca, "name")
            if symType(r.st, hcat("@소비:", n)).count > 0 || symType(r.st, hcat("@지역text:", n)).count > 0 || symType(r.st, hcat("@소유:", n)).count > 0 || symType(r.st, hcat("@소유struct:", n)).count > 0 || symType(r.st, hcat("@소유선택text:", n)).count > 0 {
                return r
            }
        }
        var temp = symType(r.st, hcat("@임시소유:", r.val)).count > 0
        if kind == "CallExpr" {
            if astObjectAttrField(astStrField(ca, "name")).count == 0 { temp = true }
        }
        switch kind {
        case "AwaitExpr", "StructInitExpr", "StructValueExpr", "StructUpdateExpr", "ClosureValueExpr", "ArrayLiteral", "DynamicArrayPopExpr":
            temp = true
        default: break
        }
        if kind == "IndexAccessExpr" {
            let bt = exprStaticType(astField(ca, "base"), r.st)
            if dynArrayFnHead(bt).count > 0 { temp = true }
        }
        var owned = r
        if !temp { owned = ownedValueRetain(r.st, r.val, r.ty) }
        let ts = ownAdd(owned.st, owned.val, owned.ty)
        return HRes(st: ts, val: owned.val, ty: owned.ty)
    }

    // 정본: HMIR열거문맥이름식
    func enumContextNameExpr(_ e: J, _ s: HState, _ hint: BStr) -> J {
        if astKind(e) != "NameExpr" { return .null }
        let name = astStrField(e, "name")
        if symType(s, name) != "" { return .null }
        let en = typeDisplay(hint)
        let key = hcat(en, ".", name)
        if symType(s, hcat("@열거타입:", key)) == "" { return .null }
        let base = jNode("NameExpr", ["name"], [.string(en)])
        return jNode("FieldAccessExpr", ["base", "field"], [base, .string(name)])
    }

    // 정본: HMIR열거비교문맥
    func enumCompareContext(_ node: J, _ s: HState) -> J {
        let op = astStrField(node, "op")
        if op != "==" && op != "!=" && op != "<" && op != ">" && op != "<=" && op != ">=" { return .null }
        var l = astField(node, "left")
        var r = astField(node, "right")
        var changed = false
        if astKind(l) == "NameExpr" && symType(s, astStrField(l, "name")) == "" {
            let nl = enumContextNameExpr(l, s, exprStaticType(r, s))
            if !astIsNull(nl) { l = nl; changed = true }
        }
        if astKind(r) == "NameExpr" && symType(s, astStrField(r, "name")) == "" {
            let nr = enumContextNameExpr(r, s, exprStaticType(l, s))
            if !astIsNull(nr) { r = nr; changed = true }
        }
        if changed { return jNode(astKind(node), ["left", "op", "right"], [l, .string(op), r]) }
        return .null
    }

    // MARK: 표현식_타입.hmje

    func isPackedDot(_ n: BStr) -> Bool {
        n == "빠른포장4정수8내적32" || n == "빠른포장4정수8쌍내적32" || n == "빠른포장4더하기2정수8내적16" || n == "빠른포장4더하기2정수8쌍내적32"
    }
    func isPackedAcc(_ n: BStr) -> Bool {
        n == "빠른포장4정수8쌍부분곱더하기32" || n == "빠른포장4정수8넷부분곱더하기32" || n == "빠른Q6_KQ8_K부분곱더하기256"
    }

    // 정본: HMIR내장호출반환타입
    func builtinCallReturnType(_ n: BStr) -> BStr {
        if n == "빠른반정밀도접기" { return "u16" }
        if n == "빠른반정밀도풀기" || n == "빠른곱더하기32" || n == "빠른F16실수32내적8배수" { return "f32" }
        if n == "빠른실수32최댓값16" || n == "빠른실수32합8" { return "f32" }
        if isPackedDot(n) { return "i64" }
        if isPackedAcc(n) || n == "빠른재배치Q4_0여덟행렬곱" || n == "빠른실수32배열곱더하기16" || n == "빠른실수32Q8_0양자화32" { return "void" }
        if n == "CPU휴식" || n == "CPU대기" { return "void" }
        return ""
    }

    // 정본: HMIR커널내장반환타입
    func kernelBuiltinReturnType(_ n: BStr) -> BStr {
        switch n {
        case "기다리기", "주소공간전환", "앱엔트리호출", "GDT로드", "IDT로드", "TSS로드", "유저모드진입", "시스템호출테이블적용",
             "문맥전환", "인터럽트활성화", "인터럽트비활성화", "소프트인터럽트2", "소프트인터럽트32":
            return "void"
        case "인터럽트플래그": return "u64"
        case "현재주소공간", "프로세스유저모드트램폴린주소", "SMPAP진입주소": return "address"
        default: return ""
        }
    }

    // 정본: HMIR커널내장연산이름
    func kernelBuiltinOpName(_ n: BStr) -> BStr {
        switch n {
        case "기다리기": return "대기밀리초"
        case "현재주소공간": return "주소공간읽기"
        case "주소공간전환": return "주소공간쓰기"
        case "인터럽트플래그": return "인터럽트플래그읽기"
        default: return n
        }
    }

    // 정본: HMIR포장원소크기
    func packedElemSize(_ t: BStr) -> UInt64 {
        switch typeResolve(t) {
        case "i8", "u8", "char", "bool": return 1
        case "i16", "u16": return 2
        case "i32", "u32", "f32": return 4
        default: return 8
        }
    }

    // 정본: HMIR포장타입크기
    func packedTypeSize(_ t: BStr) -> UInt64 {
        let inner = typeResolve(t)
        switch inner {
        case "i8", "u8", "char", "bool": return 1
        case "i16", "u16": return 2
        case "i32", "u32", "f32": return 4
        case "i64", "u64", "f64", "address": return 8
        default: break
        }
        var sn = inner
        if sn.hasPrefix("struct:") { sn = hSub(sn, 7, sn.count - 7) }
        let fs = structFields(sn)
        if astIsNull(fs) { return 8 }
        var sz: UInt64 = 0
        for v in fs.objectValues { sz = sz &+ packedTypeSize(astStr(v)) }
        return sz
    }

    // 정본: HMIR합성AST노드3
    func synthNode3(_ kind: BStr, _ k1: BStr, _ k2: BStr, _ k3: BStr, _ v1: J, _ v2: J, _ v3: J) -> J {
        jNode(kind, [k1, k2, k3], [v1, v2, v3])
    }

    // 정본: HMIR함수첫정의
    func firstFunctionDef(_ name: BStr) -> J { jAt(funcOverloads(name), 0) }

    // 정본: HMIR수치계열타입인가
    func isNumericFamily(_ t: BStr) -> Bool {
        switch typeResolve(t) {
        case "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "f32", "f64", "address": return true
        default: return false
        }
    }

    // 정본: HMIR호출숫자타입인가
    func isCallNumeric(_ t: BStr) -> Bool {
        switch typeResolve(t) {
        case "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "f32", "f64": return true
        default: return false
        }
    }

    // 정본: HMIR호출타입동일
    func callTypeSame(_ a: BStr, _ b: BStr) -> Bool {
        let ai = typeResolve(a), bi = typeResolve(b)
        if ai == bi { return true }
        if isFnValueType(ai) && isFnValueType(bi) {
            var aa = ai.hasPrefix("asyncfn")
            if hHas(ai, "비동기로") { aa = true }
            var ba = bi.hasPrefix("asyncfn")
            if hHas(bi, "비동기로") { ba = true }
            if aa != ba { return false }
            if !callTypeSame(fnValueReturnType(ai), fnValueReturnType(bi)) { return false }
            let ap = fnValueParamTypes(ai), bp = fnValueParamTypes(bi)
            if ap.count != bp.count { return false }
            for i in 0..<ap.count { if !callTypeSame(ap[i], bp[i]) { return false } }
            return true
        }
        return typeDisplay(ai) == typeDisplay(bi)
    }

    // 정본: HMIR호출타입호환
    func callTypeCompatible(_ a: BStr, _ b: BStr) -> Bool {
        let ad = typeDisplay(typeResolve(a))
        let bd = typeDisplay(typeResolve(b))
        if callTypeSame(a, b) { return true }
        if isCallNumeric(a) && isCallNumeric(b) { return true }
        if ad == "문자" && bd == "자연수8" { return true }
        if ad == "자연수8" && bd == "문자" { return true }
        return false
    }

    // 정본: HMIR함수노드정의고르기
    func functionNodeDefSelect(_ node: J) -> J {
        let name = astStrField(node, "name")
        let ap = astField(node, "params")
        let dups = funcOverloads(name)
        for round in 0..<2 {
            for cand in dups.arrayValue {
                if astStrField(node, "source_path") != astStrField(cand, "source_path") { continue }
                let cp = astField(cand, "params")
                var match = jLen(ap) == jLen(cp)
                var i = 0
                while i < jLen(ap) && match {
                    let at = typeResolve(astStrField(jAt(ap, i), "type_name"))
                    let ct = typeResolve(astStrField(jAt(cp, i), "type_name"))
                    var pm = at == ct
                    if round == 1 && !pm { pm = callTypeCompatible(at, ct) }
                    if !pm { match = false }
                    i += 1
                }
                if match { return cand }
            }
        }
        return firstFunctionDef(name)
    }

    // 정본: HMIR함수타입정의있는가
    func functionTypeDefExists(_ name: BStr, _ t: BStr) -> Bool {
        for d in funcOverloads(name).arrayValue {
            let ps = astField(d, "params")
            if jLen(ps) == 1 {
                if typeResolve(astStrField(jAt(ps, 0), "type_name")) == typeResolve(t) { return true }
            }
        }
        return false
    }

    // MARK: 표현식_정적타입.hmje

    // 정본: HMIR식정적타입
    func exprStaticType(_ node: J, _ s: HState) -> BStr {
        let kind = astKind(node)
        switch kind {
        case "AwaitExpr": return exprStaticType(astField(node, "call"), s)
        case "NameExpr": return symType(s, astStrField(node, "name"))
        case "CastExpr":
            let cn = astStrField(node, "type_name")
            if symType(s, hcat("@열거기반:", cn)).count > 0 { return hcat("enum:", cn) }
            return typeResolve(cn)
        case "BoolLiteral": return "bool"
        case "StringLiteral": return "text"
        case "FileDataExpr": return ""
        case "TryExpr": return exprStaticType(astField(node, "expr"), s)
        case "IntLiteral": return "i64"
        case "FloatLiteral": return "f64"
        case "StructInitExpr": return hcat("struct:", astStrField(node, "name"))
        case "AddressOfExpr", "FunctionAddressExpr": return "address"
        case "MemoryReadExpr", "OffsetMemoryReadExpr": return typeResolve(astStrField(node, "value_type"))
        case "FixedArrayFillExpr": return typeResolve(astStrField(node, "type_name"))
        case "OverlayBindExpr":
            var oe = typeResolve(astStrField(node, "struct_name"))
            if astBoolField(node, "is_array") { return hcat("overlay_array:", oe) }
            if oe.hasPrefix("struct:") { oe = hSub(oe, 7, oe.count - 7) }
            return hcat("overlay:", oe)
        case "ArrayBufferViewExpr": return "struct:버퍼뷰"
        default: break
        }
        if kind == "OptionalUnwrapExpr" {
            var on = typeResolve(exprStaticType(astField(node, "expr"), s))
            if on.hasPrefix("struct:") { on = hSub(on, 7, on.count - 7) }
            let vt = astObjField(structFields(on), "값")
            if !astIsNull(vt) { return typeResolve(astStr(vt)) }
        }
        if kind == "UnaryExpr" { return exprStaticType(astField(node, "operand"), s) }
        if kind == "BinaryExpr" {
            let op = astStrField(node, "op")
            switch op {
            case "==", "!=", "<", ">", "<=", ">=", "and", "or", "&&", "||": return "bool"
            default: break
            }
            let lt = exprStaticType(astField(node, "left"), s)
            let rt = exprStaticType(astField(node, "right"), s)
            if astKind(astField(node, "left")) == "IntLiteral" && rt.count > 0 { return rt }
            if lt.count > 0 { return lt }
            return rt
        }
        if kind == "FieldAccessExpr" {
            let eb = astField(node, "base")
            let field = astStrField(node, "field")
            if astKind(eb) == "NameExpr" {
                let et = symType(s, hcat("@열거타입:", astStrField(eb, "name"), ".", field))
                if et.count > 0 { return et }
            }
            let bt = exprStaticType(eb, s)
            if field == "원시값" {
                var eb2 = symType(s, hcat("@열거기반타입:", bt))
                if eb2.count == 0 { eb2 = symType(s, hcat("@열거기반타입:", typeDisplay(bt))) }
                if eb2.count > 0 { return eb2 }
            }
            if typeResolve(bt) == "text" {
                if field == "길이" || field == "용량" || field == "바이트길이" { return "u64" }
                if field == "주소" { return "address" }
            }
            if bt.hasSuffix("동적배열형") {
                if field == "데이터" { return "address" }
                if field == "길이" || field == "용량" { return "u64" }
            }
            if bt.hasPrefix("overlay_array:") {
                if field == "기준주소" { return "address" }
                if field == "길이" { return "u64" }
            }
            var sn = typeResolve(bt)
            if sn.hasPrefix("struct:") { sn = hSub(sn, 7, sn.count - 7) }
            if sn.hasPrefix("overlay:") { sn = hSub(sn, 8, sn.count - 8) }
            let fs = structFields(sn)
            if !astIsNull(fs) { return typeResolve(astStr(astObjField(fs, field))) }
        }
        if kind == "IndexAccessExpr" {
            let bt = exprStaticType(astField(node, "base"), s)
            if bt.hasPrefix("overlay_array:") { return typeResolve(hSub(bt, 14, bt.count - 14)) }
            let fe = fixedArrayElemType(bt)
            if fe.count > 0 { return typeResolve(fe) }
            if bt.hasSuffix("동적배열형") {
                let gd = firstFunctionDef(hcat(dynArrayFnHead(bt), "동적배열가져오기"))
                if !astIsNull(gd) { return typeResolve(astStrField(gd, "return_type")) }
            }
        }
        if kind == "CallExpr" {
            let cn = astStrField(node, "name")
            if cn == "자연어길이" || cn == "자연어용량" { return "u64" }
            if cn == "자연어비었는지" { return "bool" }
            if cn == "자연어주소" { return "address" }
            let attr = astObjectAttrField(cn)
            let aargs = astField(node, "args")
            if attr.count > 0 && jLen(aargs) == 1 {
                let bt = exprStaticType(jAt(aargs, 0), s)
                var sn = typeResolve(bt)
                if sn.hasPrefix("struct:") { sn = hSub(sn, 7, sn.count - 7) }
                let atv = astObjField(structFields(sn), attr)
                if !astIsNull(atv) { return typeResolve(astStr(atv)) }
            }
            let def = callDefSelect(cn, aargs, s)
            if !astIsNull(def) { return typeResolve(astStrField(def, "return_type")) }
            let fvt = symType(s, cn)
            if isFnValueType(fvt) { return fnValueReturnType(fvt) }
            let kt = kernelBuiltinReturnType(cn)
            if kt.count > 0 && kt != "void" { return kt }
        }
        return ""
    }

    // 정본: HMIR호출정의고르기
    func callDefSelect(_ name: BStr, _ args: J, _ s: HState) -> J {
        let dups = funcOverloads(name)
        var rejected: J = .null
        let na = jLen(args)
        for round in 0..<2 {
            for cand in dups.arrayValue {
                let params = astField(cand, "params")
                var match = jLen(params) == na
                var i = 0
                while i < na && match {
                    var actual = jAt(args, i)
                    if jIsArray(actual) && jLen(actual) == 2 { actual = jAt(actual, 1) }
                    let st = exprStaticType(actual, s)
                    let pt = typeResolve(astStrField(jAt(params, i), "type_name"))
                    if st.count > 0 {
                        var am = st == pt
                        if round == 1 && !am {
                            am = callTypeCompatible(st, pt)
                            if !am {
                                var on = pt
                                if on.hasPrefix("struct:") { on = hSub(on, 7, on.count - 7) }
                                if on.hasSuffix("선택값") {
                                    let ovt = typeResolve(astStr(astObjField(structFields(on), "값")))
                                    am = callTypeCompatible(st, ovt)
                                }
                            }
                        }
                        if !am { match = false }
                    }
                    i += 1
                }
                if match {
                    if accessAllowed(cand, s) { return cand }
                    if astIsNull(rejected) { rejected = cand }
                }
            }
        }
        return rejected
    }

    // MARK: 표현식_출력.hmje

    // 정본: HMIR출력조각호출
    func printPieceCall(_ s: HState, _ v: BStr, _ t: BStr) -> HState {
        addLine(s, hcat(ind(s), "호출 @출력조각[", typeDisplay(t), "](", v, ")"))
    }

    // 정본: HMIR출력문자열
    func printString(_ s: HState, _ v: BStr) -> HState {
        let t = nextTemp(s)
        let nx = addLine(t.st, hcat(ind(s), t.val, ": 문자열 = 상수값 ", stringLiteralDisplay(v)))
        return printPieceCall(nx, t.val, "text")
    }

    // 정본: HMIR생성출력
    func genPrint(_ s: HState, _ v: BStr, _ t: BStr, _ quote: Bool) -> HState {
        let inner = typeResolve(t)
        if (quote && inner == "text") || (quote && inner == "char") {
            var cur = printString(s, "\"")
            cur = printPieceCall(cur, v, inner)
            return printString(cur, "\"")
        }
        if functionTypeDefExists("출력조각", inner) { return printPieceCall(s, v, inner) }
        let fe = fixedArrayElemType(inner)
        if fe.count > 0 {
            var cur = printString(s, "[")
            let n = fixedArrayLen(inner)
            var i: UInt64 = 0
            while i < n {
                if i > 0 { cur = printString(cur, ", ") }
                let it = nextTemp(cur)
                cur = addLine(it.st, hcat(ind(cur), it.val, ": 큰정수 = 상수값 ", hDecU(i)))
                let et = nextTemp(cur)
                cur = addLine(et.st, hcat(ind(cur), et.val, ": ", typeDisplay(fe), " = 인덱스읽기 ", v, "[", it.val, "], 영기반"))
                cur = genPrint(cur, et.val, fe, true)
                i += 1
            }
            return printString(cur, "]")
        }
        var sn = inner
        if sn.hasPrefix("struct:") { sn = hSub(sn, 7, sn.count - 7) }
        let fs = structFields(sn)
        if astIsNull(fs) { return fail(s, hcat("출력할 수 없는 타입: ", typeDisplay(t))) }
        var cur = printString(s, "{")
        let fk = fs.objectKeys, fv = fs.objectValues
        for i in 0..<fk.count {
            let ft = typeResolve(astStr(fv[i]))
            if i > 0 { cur = printString(cur, ", ") }
            cur = printString(cur, hcat(fk[i], ": "))
            let tmp = nextTemp(cur)
            cur = addLine(tmp.st, hcat(ind(cur), tmp.val, ": ", typeDisplay(ft), " = 필드읽기 ", v, ".", fk[i]))
            cur = genPrint(cur, tmp.val, ft, true)
        }
        return printString(cur, "}")
    }
}
