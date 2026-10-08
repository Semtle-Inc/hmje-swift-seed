// 정본: 준비/제네릭.hmje의 `준비단형…`(임의 타입 함수 단형화)과 준비/구조단형.hmje.
// 네 도구에는 사용자 제네릭 구조체가 없다(사전·집합뿐) — 사용자구조있나 갈래는 미이식.

struct MonoTable {
    var genNames: [BStr] = []
    var genNodes: [J] = []
    var structNames: [BStr] = []
    var structNameSet: Set<BStr> = []
    var structs: [J] = []
    var funcNames: [BStr] = []
    var funcParamCounts: [Int] = []
    var funcReturns: [BStr] = []
    var funcNodes: [J] = []
    var hasUserStruct = false
    /// 호출 이름 → funcNames 안의 위치들(원래 순서)
    var funcIndex: [BStr: [Int]] = [:]
}

struct MonoState {
    var symNames: [BStr] = []
    var symTypes: [BStr] = []
    var specNames: [BStr] = []
    var specFuncs: [J] = []
    var specRets: [BStr] = []
}

enum Mono {
    // 정본: 준비단형원시내부
    static func primInternal(_ t: BStr) -> BStr {
        switch t {
        case "문자열", "글", "string", "text": return "text"
        case "문자", "글자", "char": return "char"
        case "참거짓", "불리언", "불", "bool": return "bool"
        case "주소", "원시주소", "address": return "address"
        case "작은자연수", "자연수8", "u8": return "u8"
        case "중간자연수", "자연수16", "u16": return "u16"
        case "자연수32", "u32": return "u32"
        case "자연수", "자연수64", "큰자연수", "u64": return "u64"
        case "작은정수", "정수8", "i8": return "i8"
        case "중간정수", "정수16", "i16": return "i16"
        case "정수32", "i32": return "i32"
        case "정수", "정수64", "큰정수", "i64": return "i64"
        case "실수32", "float32", "f32": return "f32"
        case "실수64", "실수", "float", "float64", "f64": return "f64"
        default: return ""
        }
    }

    // 정본: 준비단형내부
    static func internalType(_ t: BStr, _ tb: MonoTable) -> BStr {
        if t == "" { return "" }
        if t.hasSuffix("의 배열") {
            let inner = internalType(t.sub(0, t.count - BStr("의 배열").count), tb)
            if inner == "" { return "" }
            return "배열<" + inner + ">"
        }
        if t.hasSuffix("?") {
            let inner = internalType(t.sub(0, t.count - 1), tb)
            if inner == "" { return "" }
            return "선택<" + inner + ">"
        }
        let p = primInternal(t)
        if p != "" { return p }
        if tb.structNameSet.contains(t) { return "struct:" + t }
        return ""
    }

    // 정본: 준비단형표시
    static func display(_ i: BStr) -> BStr {
        if i.hasPrefix("배열<") {
            let h = BStr("배열<").count
            return display(i.sub(h, i.count - h - 1)) + "의 배열"
        }
        if i.hasPrefix("선택<") {
            let h = BStr("선택<").count
            return display(i.sub(h, i.count - h - 1)) + "?"
        }
        switch i {
        case "text": return "문자열"
        case "char": return "문자"
        case "bool": return "참거짓"
        case "address": return "주소"
        case "f32": return "실수32"
        case "f64": return "실수64"
        case "u8": return "자연수8"
        case "u16": return "자연수16"
        case "u32": return "자연수32"
        case "u64": return "큰자연수"
        case "i8": return "정수8"
        case "i16": return "정수16"
        case "i32": return "정수32"
        case "i64": return "큰정수"
        default: break
        }
        if i.hasPrefix("struct:") { let h = BStr("struct:").count; return i.sub(h, i.count - h) }
        return i
    }

    // 정본: 준비단형특수이름
    static func specName(_ name: BStr, _ internals: [BStr]) -> BStr {
        var r = name
        var hashIn: BStr = ""
        for (i, x) in internals.enumerated() {
            var d = display(x)
            if x.hasPrefix("배열<") { d = "배열" } else if x.hasPrefix("선택<") { d = "선택" }
            r = r + "__" + d
            if i > 0 { hashIn = hashIn + "|" }
            hashIn = hashIn + x
        }
        return r + "_" + Generic.hash8(hashIn)
    }

    // 정본: 준비단형본문반환
    static func bodyReturn(_ v: J) -> BStr {
        switch v {
        case .array(let a):
            for x in a { let r = bodyReturn(x); if r != "" { return r } }
            return ""
        case .object(_, let vs):
            if astKind(v) == "Return", case .string(let s) = astField(v, "type_name") { return s }
            for x in vs { let r = bodyReturn(x); if r != "" { return r } }
            return ""
        default: return ""
        }
    }

    // 정본: 준비단형함수반환표면
    static func functionReturnSurface(_ fn: J) -> BStr {
        if case .string(let s) = astField(fn, "return_type") { return s }
        return bodyReturn(astField(fn, "body"))
    }

    // 정본: 준비구조제네릭 (사전·집합은 널)
    static func userGenericStruct(_ name: BStr, _ structs: [J]) -> J {
        if name == "사전" || name == "집합" { return .null }
        for s in structs where astStrField(s, "name") == name && astField(s, "type_params").arrayValue.count > 0 { return s }
        return .null
    }

    // 정본: 준비단형표기초
    static func tableBase(_ stmts: [J]) -> MonoTable {
        var tb = MonoTable()
        var genStructs: [J] = []
        for ls in stmts {
            let node = lineNode(ls)
            if astKind(node) == "StructDef" {
                let n = astStrField(node, "name")
                tb.structNames.append(n); tb.structNameSet.insert(n)
                tb.structs.append(node)
                let tp = astField(node, "type_params")
                if tp.isArray && tp.arrayValue.count > 0 {
                    genStructs.append(ls)
                    if n != "사전" && n != "집합" { tb.hasUserStruct = true }
                }
            }
        }
        if tb.hasUserStruct { fatalError("미이식: 준비구조단형(사용자 제네릭 구조체)") }
        for ls in stmts {
            let node = lineNode(ls)
            if astKind(node) == "FunctionDef" {
                let base = Generic.functionBase(node, genStructs)
                let tps = astField(node, "type_params").arrayValue
                if base != "" && base != "사전" && base != "집합" {
                    fatalError("미이식: 준비단형표기초(사용자 제네릭 구조체 기반 함수)")
                }
                if tps.count > 0 && base != "사전" && base != "집합" {
                    tb.genNames.append(astStrField(node, "name"))
                    tb.genNodes.append(jarr([ls.arrayValue[0], nodeReplace(node, "type_params", jarr(tps))]))
                }
            }
        }
        return tb
    }

    // 정본: 준비단형표채우기
    static func tableFill(_ base: MonoTable, _ stmts: [J]) -> MonoTable {
        var tb = base
        for ls in stmts {
            let node = lineNode(ls)
            if astKind(node) == "FunctionDef" {
                let tps = astField(node, "type_params").arrayValue
                // 사용자구조있나가 거짓이면 미결구조인가는 늘 거짓이다.
                if tps.count == 0 {
                    let name = astStrField(node, "name")
                    tb.funcIndex[name, default: []].append(tb.funcNames.count)
                    tb.funcNames.append(name)
                    tb.funcParamCounts.append(astField(node, "params").arrayValue.count)
                    tb.funcReturns.append(functionReturnSurface(node))
                    tb.funcNodes.append(node)
                }
            }
        }
        return tb
    }

    // 정본: 준비단형호출있는가
    static func hasCall(_ v: J, _ names: Set<BStr>) -> Bool {
        switch v {
        case .array(let a): return a.contains { hasCall($0, names) }
        case .object(_, let vs):
            if astKind(v) == "CallExpr" && names.contains(astStrField(v, "name")) { return true }
            return vs.contains { hasCall($0, names) }
        default: return false
        }
    }

    // 정본: 준비단형구조필드
    static func structField(_ structs: [J], _ sname: BStr, _ fname: BStr) -> BStr {
        for s in structs where astStrField(s, "name") == sname {
            let f = astField(s, "fields")
            let ks = f.objectKeys, vs = f.objectValues
            for i in 0..<ks.count where ks[i] == fname { return astStr(vs[i]) }
            return ""
        }
        return ""
    }

    // 정본: 준비단형식타입
    static func exprType(_ e: J, _ st: MonoState, _ tb: MonoTable) -> BStr {
        let k = astKind(e)
        switch k {
        case "NameExpr": return Generic.symbolType(astStrField(e, "name"), st.symNames, st.symTypes)
        case "CastExpr": return astStrField(e, "type_name")
        case "StructInitExpr": return astStrField(e, "name")
        case "StringLiteral": return "문자열"
        case "BoolLiteral": return "참거짓"
        case "FloatLiteral": return "실수64"
        case "IntLiteral": return "정수64"
        case "OptionalUnwrapExpr":
            let t = exprType(astField(e, "expr"), st, tb)
            if t.hasSuffix("?") { return t.sub(0, t.count - 1) }
            return ""
        case "IndexAccessExpr":
            let t = exprType(astField(e, "base"), st, tb)
            if t.hasSuffix("의 배열") { return t.sub(0, t.count - BStr("의 배열").count) }
            return ""
        case "FieldAccessExpr":
            let fname = astStrField(e, "field")
            let bt = exprType(astField(e, "base"), st, tb)
            if fname == "길이" && bt.hasSuffix("의 배열") { return "자연수64" }
            return structField(tb.structs, bt, fname)
        case "ArrayLiteral":
            let els = astField(e, "elements").arrayValue
            if els.count == 0 { return "" }
            let t = exprType(els[0], st, tb)
            if t == "" { return "" }
            return t + "의 배열"
        case "CallExpr":
            let name = astStrField(e, "name")
            if name == "같은지" || name == "작은지" || name == "큰지" { return "참거짓" }
            let argc = astField(e, "args").arrayValue.count
            for i in 0..<st.specNames.count where st.specNames[i] == name { return st.specRets[i] }
            var found: BStr = "", cnt = 0, ambiguous = false
            for i in tb.funcIndex[name] ?? [] where tb.funcParamCounts[i] == argc {
                if cnt == 0 { found = tb.funcReturns[i]; cnt = 1 } else if found != tb.funcReturns[i] { ambiguous = true }
            }
            if ambiguous { return "" }
            return found
        default: return ""
        }
    }

    // 정본: 준비단형패턴잎
    static func patternLeaf(_ p: BStr) -> BStr {
        if p.hasSuffix("의 배열") { return patternLeaf(p.sub(0, p.count - BStr("의 배열").count)) }
        if p.hasSuffix("?") { return patternLeaf(p.sub(0, p.count - 1)) }
        return p
    }

    // 정본: 준비단형매개찾기
    static func findParam(_ ps: [BStr], _ n: BStr) -> Int {
        for i in 0..<ps.count where ps[i] == n { return i }
        return ps.count
    }

    // 정본: 준비단형맞추기
    static func match(_ pattern: BStr, _ actual: BStr, _ params: [BStr], _ binds: [BStr], _ tb: MonoTable) -> (Bool, [BStr]) {
        var b = binds
        let pi = findParam(params, pattern)
        if pi < params.count {
            let ai = internalType(actual, tb)
            if ai == "" { return (false, b) }
            if b[pi] == "" { b[pi] = ai; return (true, b) }
            if b[pi] == ai { return (true, b) }
            return (false, b)
        }
        if actual == "" {
            if findParam(params, patternLeaf(pattern)) < params.count { return (false, b) }
            return (true, b)
        }
        let arr = BStr("의 배열")
        if pattern.hasSuffix(arr) && actual.hasSuffix(arr) {
            return match(pattern.sub(0, pattern.count - arr.count), actual.sub(0, actual.count - arr.count), params, b, tb)
        }
        if pattern.hasSuffix("?") && actual.hasSuffix("?") {
            return match(pattern.sub(0, pattern.count - 1), actual.sub(0, actual.count - 1), params, b, tb)
        }
        if pattern == actual { return (true, b) }
        let pint = internalType(pattern, tb), aint = internalType(actual, tb)
        if pint != "" && pint == aint { return (true, b) }
        return (false, b)
    }

    // 정본: 준비단형리터럴인가
    static func isLiteral(_ k: BStr) -> Bool {
        k == "IntLiteral" || k == "FloatLiteral" || k == "StringLiteral" || k == "BoolLiteral" || k == "ArrayLiteral"
    }

    // 정본: 준비단형후보결속
    static func candidateBind(_ fn: J, _ args: J, _ st: MonoState, _ tb: MonoTable) -> (Bool, [BStr]) {
        let ps = astField(fn, "params").arrayValue
        let tparams = astField(fn, "type_params").arrayValue.map(astStr)
        var binds = [BStr](repeating: "", count: tparams.count)
        let as_ = args.arrayValue
        for i in 0..<ps.count {
            let pattern = astStrField(ps[i], "type_name")
            let arg = i < as_.count ? as_[i] : J.null
            if !isLiteral(astKind(arg)) {
                let actual = exprType(arg, st, tb)
                // 정본: 준비구조매개맞추기 — 사용자 구조체가 없으면 준비단형맞추기
                let (ok, nb) = match(pattern, actual, tparams, binds, tb)
                if !ok { return (false, nb) }
                binds = nb
            }
        }
        for i in 0..<ps.count {
            let pattern = astStrField(ps[i], "type_name")
            let arg = i < as_.count ? as_[i] : J.null
            if isLiteral(astKind(arg)) {
                let li = findParam(tparams, patternLeaf(pattern))
                if li < tparams.count && binds[li] == "" {
                    let lt = exprType(arg, st, tb)
                    if lt != "" {
                        let (ok, nb) = match(pattern, lt, tparams, binds, tb)
                        if ok { binds = nb }
                    }
                }
            }
        }
        return (!binds.contains(""), binds)
    }

    // 정본: AST모듈정의허용
    static func definitionAllowed(_ def: J, _ useFile: BStr, _ useOwner: BStr, _ direct: BStr) -> Bool {
        let declFile = astStrField(def, "source_path")
        if useFile == "" || useFile == declFile { return true }
        let vv = astField(def, "visibility")
        var vis = astStr(vv)
        if vv.isObject { vis = astStr(objField(vv, "value")) }
        if vis == "file" || vis == "type" { return false }
        let declOwner = astStrField(def, "access_owner")
        if declOwner == "" { return true }
        if declOwner == useOwner { return true }
        let fileKey = "\n@file:" + declFile + "\n"
        if direct.find("\n" + declOwner + "\n") == nil && direct.find(fileKey) == nil { return false }
        if vis == "public" { return true }
        if vis == "project" && useOwner != "" {
            return useOwner.splitFast("\t")[0] == declOwner.splitFast("\t")[0]
        }
        return false
    }

    static func allowedIn(_ fn: J, _ ctx: J) -> Bool {
        definitionAllowed(fn, astStrField(ctx, "source_path"), astStrField(ctx, "access_owner"), astStrField(ctx, "access_imports"))
    }

    // 정본: 준비단형구체오버로드있는가
    static func concreteOverloadExists(_ callName: BStr, _ genParams: J, _ tparams: [BStr], _ surfArgs: [BStr], _ tb: MonoTable, _ ctx: J) -> Bool {
        for i in tb.funcIndex[callName] ?? [] {
            let fn = tb.funcNodes[i]
            if allowedIn(fn, ctx) {
                let ps = astField(fn, "params").arrayValue
                let gps = genParams.arrayValue
                if ps.count == gps.count {
                    var ok = true
                    for j in 0..<ps.count {
                        let ci = internalType(astStrField(ps[j], "type_name"), tb)
                        let sub = Generic.fieldType(astStrField(gps[j], "type_name"), tparams, surfArgs)
                        if ci != internalType(sub, tb) { ok = false }
                    }
                    if ok { return true }
                }
            }
        }
        return false
    }

    struct CallResolution {
        var ok: Bool
        var funcIdx: Int
        var specName: BStr
        var retSurface: BStr
        var surfArgs: [BStr]
        var tparams: [BStr]
    }

    // 정본: 준비단형호출풀기
    static func resolveCall(_ call: J, _ st: MonoState, _ tb: MonoTable, _ ctx: J) -> CallResolution {
        let name = astStrField(call, "name")
        let args = astField(call, "args")
        var count = 0, fidx = 0
        var spec: BStr = "", ret: BStr = ""
        var surf: [BStr] = [], tps: [BStr] = []
        var candParams = J.array([])
        for i in 0..<tb.genNames.count where tb.genNames[i] == name {
            let fn = lineNode(tb.genNodes[i])
            let pj = astField(fn, "params")
            if pj.arrayValue.count == args.arrayValue.count && allowedIn(fn, ctx) {
                let (ok, binds) = candidateBind(fn, args, st, tb)
                if ok {
                    count += 1
                    fidx = i
                    candParams = pj
                    let newSurf = binds.map(display)
                    let newTps = astField(fn, "type_params").arrayValue.map(astStr)
                    surf = newSurf
                    tps = newTps
                    var base = astStrField(fn, "emit_name")
                    if base == "" { base = name }
                    spec = specName(base, binds)
                    ret = Generic.fieldType(functionReturnSurface(fn), newTps, newSurf)
                }
            }
        }
        var ok = false
        if count == 1 {
            ok = true
            if concreteOverloadExists(name, candParams, tps, surf, tb, ctx) { ok = false }
        }
        return CallResolution(ok: ok, funcIdx: fidx, specName: spec, retSurface: ret, surfArgs: surf, tparams: tps)
    }

    // 정본: 준비단형함수특수화
    static func specializeFunction(_ ls: J, _ spec: BStr, _ tps: [BStr], _ surf: [BStr], _ tb: MonoTable) -> J {
        let node = lineNode(ls)
        var n = Generic.substValue(node, tps, surf, "", "", false)
        n = nodeReplace(n, "name", jstr(spec))
        if astStrField(node, "emit_name") != "" { n = nodeReplace(n, "emit_name", jstr(spec)) }
        n = nodeReplace(n, "external_name", .null)
        n = nodeReplace(n, "specialization_parameters", jarr(tps.map(jstr)))
        n = nodeReplace(n, "specialization_arguments", jarr(surf.map(jstr)))
        n = nodeReplace(n, "specialization_constraints", astField(node, "type_constraints"))
        n = nodeReplace(n, "type_params", jarr([]))
        n = nodeReplace(n, "type_constraints", jarr([]))
        return jarr([ls.arrayValue[0], n])
    }

    // 정본: 준비단형인자강제
    static func coerceArgs(_ call: J, _ fn: J, _ tps: [BStr], _ surf: [BStr]) -> J {
        let ps = astField(fn, "params").arrayValue
        var na = astField(call, "args").arrayValue
        if ps.count != na.count { return call }
        for i in 0..<na.count {
            let k = astKind(na[i])
            if k == "IntLiteral" || k == "FloatLiteral" || k == "StringLiteral" {
                let target = Generic.fieldType(astStrField(ps[i], "type_name"), tps, surf)
                if primInternal(target) != "" {
                    na[i] = astNode("CastExpr", ["type_name", "expr", "compiler_generated"], [jstr(target), na[i], jbool(false)])
                }
            }
        }
        return nodeReplace(call, "args", jarr(na))
    }

    // 정본: 준비단형값재작성
    static func rewrite(_ v: J, _ st: inout MonoState, _ tb: MonoTable, _ ctxIn: J) -> J {
        var ctx = ctxIn
        if astStrField(v, "source_path") != "" { ctx = v }
        switch v {
        case .array(let a):
            var out: [J] = []
            out.reserveCapacity(a.count)
            for x in a { out.append(rewrite(x, &st, tb, ctx)) }
            return .array(out)
        case .object(let ks, let vs):
            var out: [J] = []
            out.reserveCapacity(vs.count)
            for x in vs { out.append(rewrite(x, &st, tb, ctx)) }
            var nv = J.object(keys: ks, values: out)
            let kind = astKind(nv)
            // 정본: 준비구조표넓히기 — 사용자 구조체가 없으면 표 그대로.
            if kind == "Define" || kind == "GlobalDefine" || kind == "Parameter" {
                let dname = astStrField(nv, "name")
                var dtype = astStrField(nv, "type_name")
                if kind != "Parameter" {
                    if dtype == "" || !userGenericStruct(dtype, tb.structs).isNull {
                        let inferred = exprType(astField(nv, "expr"), st, tb)
                        if inferred != "" {
                            dtype = inferred
                            nv = nodeReplace(nv, "type_name", jstr(dtype))
                        }
                    }
                }
                if dname != "" && dtype != "" { st.symNames.append(dname); st.symTypes.append(dtype) }
            }
            if kind == "Return" {
                let rt = astStrField(nv, "type_name")
                if rt == "" || !userGenericStruct(rt, tb.structs).isNull {
                    let inferred = exprType(astField(nv, "expr"), st, tb)
                    if inferred != "" { nv = nodeReplace(nv, "type_name", jstr(inferred)) }
                }
            }
            if kind == "CallExpr" {
                let r = resolveCall(nv, st, tb, ctx)
                if r.ok {
                    let origLine = tb.genNodes[r.funcIdx]
                    if !st.specNames.contains(r.specName) {
                        let idx = st.specNames.count
                        st.specNames.append(r.specName)
                        st.specFuncs.append(.null)
                        st.specRets.append(r.retSurface)
                        let specLine = specializeFunction(origLine, r.specName, r.tparams, r.surfArgs, tb)
                        let savedN = st.symNames, savedT = st.symTypes
                        st.symNames = []; st.symTypes = []
                        let sub = rewrite(specLine, &st, tb, lineNode(origLine))
                        st.symNames = savedN; st.symTypes = savedT
                        st.specFuncs[idx] = sub
                        st.specRets[idx] = functionReturnSurface(lineNode(sub))
                    }
                    nv = nodeReplace(nv, "name", jstr(r.specName))
                    nv = coerceArgs(nv, lineNode(origLine), r.tparams, r.surfArgs)
                }
            }
            return nv
        default:
            return v
        }
    }

    // 정본: 준비단형문서낮추기
    static func lowerDocument(_ doc: J) -> J {
        guard let stmtsJ = doc.field("statements") else { return doc }
        let stmts = stmtsJ.arrayValue
        let base = tableBase(stmts)
        if base.genNames.count == 0 && !base.hasUserStruct { return doc }
        if !base.hasUserStruct && !hasCall(stmtsJ, Set(base.genNames)) { return doc }
        let tb = tableFill(base, stmts)
        var st = MonoState()
        var results: [J] = []
        for ls in stmts {
            let node = lineNode(ls)
            var isGeneric = false
            if astKind(node) == "FunctionDef" {
                let tp = astField(node, "type_params")
                if tp.isArray && tp.arrayValue.count > 0 { isGeneric = true }
            }
            if isGeneric {
                results.append(ls)
            } else {
                let savedN = st.symNames, savedT = st.symTypes
                results.append(rewrite(ls, &st, tb, node))
                if astKind(node) == "FunctionDef" { st.symNames = savedN; st.symTypes = savedT }
            }
        }
        if st.specFuncs.count == 0 { return doc }
        results.append(contentsOf: st.specFuncs)
        return objReplace(doc, "statements", .array(results))
    }
}
