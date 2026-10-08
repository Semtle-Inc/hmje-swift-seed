// 타입검사/ 이식: 검사구조체환경 · 검사함수환경 · 검사문서생성 (+ 반환 타입 추론이 쓰는 표현식 타입 판정).
// 검사문서오류(오류 검사)는 올바른 입력에서 결과를 바꾸지 않으므로 옮기지 않는다.

extension HMIRGenerator {

    // MARK: 타입검사/타입.hmje

    // 정본: 검사함수타입인가
    func tcIsFunctionType(_ t: BStr) -> Bool {
        var tail = false
        if t.hasSuffix("반환") { tail = true }
        if t.hasSuffix("반환하지 않음") { tail = true }
        if !tail { return false }
        if hHas(t, " 받아 ") { return true }
        if hHas(t, "받지 않고") { return true }
        return false
    }

    // 정본: 검사함수타입접두
    func tcFunctionTypePrefix(_ t: BStr) -> BStr {
        var out: [UInt8] = Array("함수값".utf8)
        t.withBytes { for b in $0 where b != 32 { out.append(b) } }
        return BStr(out)
    }

    // 정본: 검사컨테이너접두사
    func tcContainerPrefix(_ elem: BStr) -> BStr {
        if tcIsFunctionType(elem) { return tcFunctionTypePrefix(elem) }
        return tcGenTypePrefix(elem)
    }

    // 정본: 검사생성타입접두사
    func tcGenTypePrefix(_ elem: BStr) -> BStr {
        let inner = tcTypeNormalize(elem)
        switch inner {
        case "u8": return "자연수8"
        case "u16": return "자연수16"
        case "u32": return "자연수32"
        case "u64": return "자연수64"
        case "i8": return "정수8"
        case "i16": return "정수16"
        case "i32": return "정수32"
        case "i64": return "정수64"
        case "f32": return "실수32"
        case "f64": return "실수64"
        case "char": return "문자"
        case "bool": return "참거짓"
        case "address": return "주소"
        case "text": return "문자열배열"
        default: break
        }
        if inner.hasPrefix("struct:") {
            let name = hSub(inner, 7, inner.count - 7)
            if name.hasSuffix("동적배열형") {
                return hcat(hSub(name, 0, name.count - 15), "배열")
            }
            return name
        }
        return elem
    }

    // 정본: 검사타입정규화
    func tcTypeNormalize(_ t: BStr) -> BStr {
        if t.count == 0 { return "" }
        if t.hasPrefix("struct:") { return t }
        if t.hasSuffix("동적배열형") { return hcat("struct:", t) }
        if t.hasSuffix("?") {
            let base = hSub(t, 0, t.count - 1)
            var optName = tcContainerPrefix(base)
            if tcTypeNormalize(base) == "text" { optName = "문자열" }
            return hcat("struct:", optName, "선택값")
        }
        if t == "문자열의 배열" { return "struct:문자열배열동적배열형" }
        if t.hasSuffix("의 배열") {
            let elem = hSub(t, 0, t.count - 10)
            return hcat("struct:", tcContainerPrefix(elem), "동적배열형")
        }
        switch t {
        case "문자열", "글", "string", "text": return "text"
        case "문자", "글자", "char": return "char"
        case "참거짓", "불리언", "불", "bool": return "bool"
        case "주소", "원시주소", "address": return "address"
        case "작은자연수", "자연수8": return "u8"
        case "중간자연수", "자연수16": return "u16"
        case "자연수32": return "u32"
        case "자연수", "자연수64", "큰자연수": return "u64"
        case "작은정수", "정수8": return "i8"
        case "중간정수", "정수16": return "i16"
        case "정수32": return "i32"
        case "정수", "정수64", "큰정수": return "i64"
        case "실수32": return "f32"
        case "실수64", "실수": return "f64"
        default: return t
        }
    }

    // MARK: 타입검사/검증.hmje (반환 타입 추론이 쓰는 부분)

    // 정본: 검사빈심볼들
    func tcEmptySymbols() -> J { .object(keys: [], values: []) }

    // 정본: 검사심볼추가
    func tcSymAdd(_ syms: J, _ name: BStr, _ type: BStr) -> J { jReplaceAll(syms, name, .string(type)) }

    // 정본: 검사심볼타입
    func tcSymType(_ syms: J, _ name: BStr) -> BStr {
        let v = jStrFieldValue(syms, name)
        if v == "!moved" || v.hasPrefix("!moved:") { return "!moved" }
        if v.hasPrefix("!scope-ended:") { return "!moved" }
        if v.hasPrefix("!consuming:") { return hSub(v, 11, v.count - 11) }
        if v.hasPrefix("!pinned:") { return hSub(v, 8, v.count - 8) }
        if v.hasPrefix("!borrowed-source:") { return hSub(v, 17, v.count - 17) }
        if v.hasPrefix("!borrowed:") { return hSub(v, 10, v.count - 10) }
        return v
    }

    // 정본: 검사숫자타입인가
    func tcIsNumeric(_ t: BStr) -> Bool {
        switch t {
        case "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "f32", "f64": return true
        default: return false
        }
    }

    // 정본: 검사타입호환
    func tcTypeCompatible(_ actual: BStr, _ expected: BStr) -> Bool {
        if actual.count == 0 || expected.count == 0 { return true }
        if expected.hasPrefix("struct:") && expected.hasSuffix("선택값") { return true }
        if actual.hasPrefix("struct:") {
            if hSub(actual, 7, actual.count - 7) == expected { return true }
        }
        if expected.hasPrefix("struct:") {
            if hSub(expected, 7, expected.count - 7) == actual { return true }
        }
        if tcIsNumeric(actual) && tcIsNumeric(expected) { return true }
        if actual == "char" && expected == "u8" { return true }
        if actual == "u8" && expected == "char" { return true }
        return actual == expected
    }

    // 정본: 검사접근문맥설정
    func tcAccessContext(_ syms: J, _ node: J) -> J {
        var r = tcSymAdd(syms, "@접근파일", astStrField(node, "source_path"))
        r = tcSymAdd(r, "@접근주인", astStrField(node, "access_owner"))
        r = tcSymAdd(r, "@접근가져옴", astStrField(node, "access_imports"))
        return r
    }

    // 정본: 검사접근정의허용
    func tcAccessAllowed(_ def: J, _ syms: J) -> Bool {
        astModuleDefAllowed(def, tcSymType(syms, "@접근파일"), tcSymType(syms, "@접근주인"), tcSymType(syms, "@접근가져옴"))
    }

    // 정본: 검사호출타입
    func tcCallType(_ e: J, _ syms: J, _ structs: J, _ funcs: J) -> BStr {
        let name = astStrField(e, "name")
        let args = astField(e, "args")
        let attr = astObjectAttrField(name)
        if attr.count > 0 && args.arrayValue.count == 1 {
            let baseT = tcExprType(args.arrayValue[0], syms, structs, funcs, "")
            if baseT.hasPrefix("struct:") {
                let sname = hSub(baseT, 7, baseT.count - 7)
                if let sf = structs.field(sname) {
                    let at = jStrFieldValue(sf, attr)
                    if at.count > 0 { return tcDeclTypeNormalize(at, structs) }
                }
            }
        }
        guard let overloads = funcs.field(name) else { return "" }
        let cands = overloads.arrayValue
        let argv = args.arrayValue
        for f in cands {
            if astBoolField(e, "compiler_generated") == false && tcAccessAllowed(f, syms) == false { continue }
            let params = astField(f, "params").arrayValue
            if params.count == argv.count {
                var ok = true
                for i in 0..<argv.count {
                    let expected = astStrField(params[i], "type_name")
                    let actual = tcExprType(argv[i], syms, structs, funcs, expected)
                    if actual == "!moved" { return "!moved" }
                    if tcTypeCompatible(actual, expected) == false { ok = false }
                }
                if ok { return astStrField(f, "return_type") }
            }
        }
        return ""
    }

    // 정본: 검사표현식타입
    func tcExprType(_ e: J, _ syms: J, _ structs: J, _ funcs: J, _ hint: BStr) -> BStr {
        let kind = astKind(e)
        switch kind {
        case "IntLiteral":
            if hint.hasPrefix("i") || hint.hasPrefix("u") || hint.hasPrefix("f") || hint == "address" { return hint }
            return "i64"
        case "FloatLiteral":
            if hint == "f32" || hint == "f64" { return hint }
            return "f64"
        case "StringLiteral":
            if hint == "char" { return "char" }
            return "text"
        case "FileDataExpr": return hint
        case "BoolLiteral": return "bool"
        case "NameExpr": return tcSymType(syms, astStrField(e, "name"))
        case "CastExpr": return tcDeclTypeNormalize(astStrField(e, "type_name"), structs)
        case "AddressOfExpr": return "address"
        case "StructInitExpr": return hcat("struct:", astStrField(e, "name"))
        case "CallExpr": return tcCallType(e, syms, structs, funcs)
        default: break
        }
        if kind == "OptionalUnwrapExpr" {
            let ot = tcExprType(astField(e, "expr"), syms, structs, funcs, "")
            if ot.hasPrefix("struct:") {
                let on = hSub(ot, 7, ot.count - 7)
                if let of = structs.field(on) {
                    return tcDeclTypeNormalize(jStrFieldValue(of, "값"), structs)
                }
            }
        }
        if kind == "DynamicArrayPopExpr" {
            let at = tcSymType(syms, astStrField(e, "name"))
            if at.hasPrefix("struct:") && at.hasSuffix("동적배열형") {
                let pre = hSub(at, 7, at.count - 7 - 15)
                if let pops = funcs.field(hcat(pre, "동적배열꺼내기값")) {
                    if pops.arrayValue.count > 0 {
                        return tcDeclTypeNormalize(astStrField(pops.arrayValue[0], "return_type"), structs)
                    }
                }
            }
        }
        if kind == "IndexAccessExpr" {
            let at = tcExprType(astField(e, "base"), syms, structs, funcs, "")
            if at.hasPrefix("struct:") && at.hasSuffix("동적배열형") {
                let pre = hSub(at, 7, at.count - 7 - 15)
                if let gets = funcs.field(hcat(pre, "동적배열가져오기")) {
                    if gets.arrayValue.count > 0 {
                        return astStrField(gets.arrayValue[0], "return_type")
                    }
                }
            }
        }
        if kind == "BinaryExpr" {
            let l = tcExprType(astField(e, "left"), syms, structs, funcs, hint)
            let r = tcExprType(astField(e, "right"), syms, structs, funcs, l)
            if l == "!moved" || r == "!moved" { return "!moved" }
            if tcTypeCompatible(l, r) {
                let op = astStrField(e, "op")
                if op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" { return "bool" }
                return l
            }
        }
        if kind == "FieldAccessExpr" {
            let bt = tcExprType(astField(e, "base"), syms, structs, funcs, "")
            if bt == "!moved" { return "!moved" }
            if bt.hasPrefix("struct:") {
                let sn = hSub(bt, 7, bt.count - 7)
                if let fs = structs.field(sn) {
                    let st = jStrFieldValue(fs, astStrField(e, "field"))
                    return tcDeclTypeNormalize(st, structs)
                }
            }
        }
        return ""
    }

    // MARK: 타입검사/등록.hmje

    // 정본: 검사선언타입정규화
    func tcDeclTypeNormalize(_ t: BStr, _ structs: J) -> BStr {
        let base = tcTypeNormalize(t)
        if base != t { return base }
        for k in structs.objectKeys where k == t { return hcat("struct:", t) }
        return base
    }

    // 정본: 검사첫반환타입
    func tcFirstReturnType(_ v: J, _ structs: J) -> BStr {
        switch v {
        case .object(_, let vals):
            if astKind(v) == "Return" {
                let surf = astStrField(v, "type_name")
                if surf.count > 0 { return tcDeclTypeNormalize(surf, structs) }
            }
            for x in vals {
                let t = tcFirstReturnType(x, structs)
                if t.count > 0 { return t }
            }
        case .array(let a):
            for x in a {
                let t = tcFirstReturnType(x, structs)
                if t.count > 0 { return t }
            }
        default: break
        }
        return ""
    }

    // 정본: 검사반환식타입
    func tcReturnExprType(_ e: J, _ syms: J, _ structs: J, _ funcs: J) -> BStr {
        let kind = astKind(e)
        if kind == "FixedArrayFillExpr" { return tcDeclTypeNormalize(astStrField(e, "type_name"), structs) }
        if kind == "UnaryExpr" { return tcReturnExprType(astField(e, "operand"), syms, structs, funcs) }
        return tcExprType(e, syms, structs, funcs, "")
    }

    // 정본: 검사몸통정의심볼
    func tcBodyDefineSymbol(_ syms: J, _ node: J, _ structs: J, _ funcs: J) -> J {
        let kind = astKind(node)
        var t: BStr = ""
        if kind == "Define" {
            t = tcDeclTypeNormalize(astStrField(node, "type_name"), structs)
            if t.count == 0 { t = tcReturnExprType(astField(node, "expr"), syms, structs, funcs) }
        } else if kind == "BorrowDefine" {
            t = tcDeclTypeNormalize(astStrField(node, "type_name"), structs)
        } else if kind == "ReferenceDefine" {
            t = tcReturnExprType(astField(node, "expr"), syms, structs, funcs)
        } else if kind == "MoveDefine" {
            t = tcSymType(syms, astStrField(node, "source"))
        } else {
            return syms
        }
        if t.count == 0 || t == "!moved" { return syms }
        return tcSymAdd(syms, astStrField(node, "name"), t)
    }

    // 정본: 검사몸통반환타입
    func tcBodyReturnType(_ stmts: J, _ syms: J, _ structs: J, _ funcs: J) -> BStr {
        var cur = syms
        for pair in stmts.arrayValue {
            var found: BStr = ""
            if pair.arrayValue.count == 2 {
                let node = pair.arrayValue[1]
                let kind = astKind(node)
                if kind == "Return" {
                    let re = astField(node, "expr")
                    if !astIsNull(re) {
                        let surf = astStrField(node, "type_name")
                        if surf.count > 0 {
                            found = tcDeclTypeNormalize(surf, structs)
                        } else {
                            found = tcReturnExprType(re, cur, structs, funcs)
                        }
                    }
                } else if kind == "If" || kind == "Switch" {
                    let branches = astField(node, "branches").arrayValue
                    var bi = 0
                    while bi < branches.count && found.count == 0 {
                        let b = branches[bi]
                        if b.arrayValue.count == 2 {
                            found = tcBodyReturnType(b.arrayValue[1], cur, structs, funcs)
                        }
                        bi += 1
                    }
                    let eb = astField(node, "else_body")
                    if found.count == 0 && !astIsNull(eb) {
                        found = tcBodyReturnType(eb, cur, structs, funcs)
                    }
                } else if kind == "While" || kind == "ForEach" || kind == "UnsafeBlock" || kind == "PreemptDisableBlock" || kind == "DeadlineBlock" {
                    found = tcBodyReturnType(astField(node, "body"), cur, structs, funcs)
                } else if kind == "TryBlock" {
                    found = tcBodyReturnType(astField(node, "body"), cur, structs, funcs)
                    let fb = astField(node, "failure_body")
                    if found.count == 0 && !astIsNull(fb) { found = tcBodyReturnType(fb, cur, structs, funcs) }
                    let fin = astField(node, "finally_body")
                    if found.count == 0 && !astIsNull(fin) { found = tcBodyReturnType(fin, cur, structs, funcs) }
                } else {
                    cur = tcBodyDefineSymbol(cur, node, structs, funcs)
                }
            }
            if found.count > 0 { return found }
        }
        return ""
    }

    // 정본: 검사첫반환호출이름
    func tcFirstReturnCallName(_ v: J) -> BStr {
        switch v {
        case .object(_, let vals):
            if astKind(v) == "Return" {
                let re = astField(v, "expr")
                if astKind(re) == "CallExpr" { return astStrField(re, "name") }
            }
            for x in vals {
                let n = tcFirstReturnCallName(x)
                if n.count > 0 { return n }
            }
        case .array(let a):
            for x in a {
                let n = tcFirstReturnCallName(x)
                if n.count > 0 { return n }
            }
        default: break
        }
        return ""
    }

    // 정본: 검사매개정규화
    func tcParamNormalize(_ p: J, _ structs: J) -> J {
        let t = tcDeclTypeNormalize(astStrField(p, "type_name"), structs)
        return jNodeReplaceField(p, "type_name", .string(t))
    }

    // 정본: 검사함수정규화
    func tcFunctionNormalize(_ fn: J, _ structs: J, _ funcs: J) -> J {
        let params = astField(fn, "params")
        var newParams: [J] = []
        var psyms = tcAccessContext(tcEmptySymbols(), fn)
        for p in params.arrayValue {
            let np = tcParamNormalize(p, structs)
            newParams.append(np)
            psyms = tcSymAdd(psyms, astStrField(np, "name"), astStrField(np, "type_name"))
        }
        var rt = tcDeclTypeNormalize(astStrField(fn, "return_type"), structs)
        if rt.count == 0 { rt = tcFirstReturnType(astField(fn, "body"), structs) }
        if rt.count == 0 { rt = tcBodyReturnType(astField(fn, "body"), psyms, structs, funcs) }
        var nf = jNodeReplaceField(fn, "params", .array(newParams))
        if rt.count > 0 { nf = jNodeReplaceField(nf, "return_type", .string(rt)) }
        return nf
    }

    // 정본: 검사구조체필드표시
    func tcStructFieldDisplay(_ surf: BStr) -> BStr {
        let inner = tcTypeNormalize(surf)
        if inner.hasPrefix("struct:") && inner.hasSuffix("동적배열형") {
            let sname = hSub(inner, 7, inner.count - 7)
            let pre = hSub(sname, 0, sname.count - 15)
            var ed = pre
            if pre == "자연수64" { ed = "큰자연수" } else if pre == "정수64" { ed = "큰정수" } else if pre == "문자열배열" { ed = "문자열" }
            return hcat(ed, "의 배열")
        }
        return surf
    }

    // 정본: 검사구조체환경
    func tcStructEnv(_ stmts: J) -> J {
        var keys: [BStr] = ["버퍼뷰"]
        var vals: [J] = [.object(keys: ["기준주소", "길이"], values: [.string("주소"), .string("자연수64")])]
        for pair in stmts.arrayValue {
            if pair.arrayValue.count == 2 {
                let node = pair.arrayValue[1]
                if astKind(node) == "StructDef" {
                    keys.append(astStrField(node, "name"))
                    let rf = astField(node, "fields")
                    var fk: [BStr] = [], fv: [J] = []
                    for k in rf.objectKeys {
                        fk.append(k)
                        fv.append(.string(tcStructFieldDisplay(jStrFieldValue(rf, k))))
                    }
                    vals.append(.object(keys: fk, values: fv))
                }
            }
        }
        return .object(keys: keys, values: vals)
    }

    // 정본: 검사함수환경
    func tcFunctionEnv(_ stmts: J, _ structs: J) -> J {
        var fkeys: [BStr] = []
        var fvals: [J] = []
        var keyIndex: [BStr: Int] = [:]
        for pair in stmts.arrayValue {
            if pair.arrayValue.count == 2 {
                let node = pair.arrayValue[1]
                if astKind(node) == "FunctionDef" {
                    let name = astStrField(node, "name")
                    var nf = tcFunctionNormalize(node, structs, .object(keys: fkeys, values: fvals))
                    if astStrField(nf, "return_type").count == 0 {
                        let callName = tcFirstReturnCallName(astField(node, "body"))
                        // 정본은 같은 이름 키를 전부 훑지만 키는 유일하다.
                        if let k = keyIndex[callName] {
                            let dup = fvals[k]
                            if dup.arrayValue.count > 0 {
                                let cr = astStrField(dup.arrayValue[0], "return_type")
                                if cr.count > 0 { nf = jNodeReplaceField(nf, "return_type", .string(cr)) }
                            }
                        }
                    }
                    if let k = keyIndex[name] {
                        var dups = fvals[k].arrayValue
                        fvals[k] = .null
                        dups.append(nf)
                        fvals[k] = .array(dups)
                    } else {
                        keyIndex[name] = fkeys.count
                        fkeys.append(name)
                        fvals.append(.array([nf]))
                    }
                }
            }
        }
        return .object(keys: fkeys, values: fvals)
    }

    // 정본: 검사문서생성
    func tcDocument(_ prepared: J) -> J {
        guard let stmts = prepared.field("statements") else { return .null }
        let structs = tcStructEnv(stmts)
        let funcs = tcFunctionEnv(stmts, structs)
        return .object(keys: ["format", "statements", "struct_defs", "functions"],
                       values: [.string("hmje-typed-ast-v1"), stmts, structs, funcs])
    }
}
