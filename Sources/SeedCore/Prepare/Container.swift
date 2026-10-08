// 정본: 준비/컨테이너.hmje (준비선택값주입, 준비기본동적배열주입)와 준비/배열리터럴.hmje.

/// 준비기본기원찾기의 결과를 한 번의 순회로 모은 색인.
/// 정본은 질의마다 문서 전체를 훑는다: 줄 문장 쌍이 현재 줄을 정하고, 일치한 자리의
/// 현재 줄 중 0보다 큰 최솟값을 돌려준다(없으면 0). `배열선언만`이면 타입이 같은
/// Define에서 멈추고(그 아래는 보지 않는다), 아니면 모든 문자열 값을 본다.
final class OriginIndex {
    var strMin: [BStr: Int] = [:]
    var defMin: [BStr: Int] = [:]

    init(_ stmts: J) { walk(stmts, 0, []) }

    private func note(_ d: inout [BStr: Int], _ k: BStr, _ line: Int) {
        if line <= 0 { return }
        if let o = d[k], o <= line { return }
        d[k] = line
    }

    private func walk(_ v: J, _ lineIn: Int, _ suppressed: Set<BStr>) {
        var line = lineIn
        switch v {
        case .string(let s): note(&strMin, s, line)
        case .array(let a):
            if a.count == 2, objField(a[0], "integer").stringValue != "", astKind(a[1]) != "" {
                if let n = Int(objField(a[0], "integer").stringValue.string) { line = n }
            }
            for x in a { walk(x, line, suppressed) }
        case .object(_, let vs):
            var sup = suppressed
            if astKind(v) == "Define" {
                let t = astStrField(v, "type_name")
                if !suppressed.contains(t) { note(&defMin, t, line) }
                sup.insert(t)
            }
            for x in vs { walk(x, line, sup) }
        default: break
        }
    }

    // 정본: 준비기본기원찾기(문장들, 타입, 0, 배열선언만)
    func find(_ t: BStr, _ declOnly: Bool) -> Int { (declOnly ? defMin[t] : strMin[t]) ?? 0 }
}

final class ContainerCtx {
    let stmts: J
    lazy var all: OriginIndex = OriginIndex(stmts)
    lazy var plainIdx: OriginIndex = OriginIndex(Container.plainStatements(stmts))
    var structByName: [BStr: J] = [:]

    init(_ stmts: J) {
        self.stmts = stmts
        for ls in stmts.arrayValue {
            let n = lineNode(ls)
            if astKind(n) == "StructDef" {
                let name = astStrField(n, "name")
                if structByName[name] == nil { structByName[name] = n }
            }
        }
    }

    // 정본: 준비구조체찾기
    func findStruct(_ name: BStr) -> J { structByName[name] ?? .null }

    // 정본: 준비기본기원줄
    func originLine(_ prefix: BStr) -> Int {
        let idx = prefix == "자연수64" ? plainIdx : all
        var o = idx.find(prefix + "의 배열", true)
        if o == 0 { o = idx.find(prefix + "의 배열", false) }
        if prefix == "자연수64" {
            let s = idx.find("큰자연수의 배열", true)
            if s > 0 && (o == 0 || s < o) { o = s }
        }
        if o > 0 { return o }
        return all.find(prefix + "?", false)
    }
}

enum Container {
    static let prefixes14: [BStr] = ["자연수8", "자연수16", "자연수32", "자연수64", "정수8", "정수16", "정수32", "정수64", "실수32", "실수64", "문자", "참거짓", "주소", "문자열"]

    // 정본: 준비기본보통문장들
    static func plainStatements(_ stmts: J) -> J {
        .array(stmts.arrayValue.filter { ls in
            let n = lineNode(ls)
            return !(astKind(n) == "FunctionDef" && astStrField(n, "name").find("__") != nil)
        })
    }

    // 정본: 준비JSON문자열포함
    static func containsString(_ v: J, _ s: BStr) -> Bool {
        switch v {
        case .string(let x): return x == s
        case .array(let a): return a.contains { containsString($0, s) }
        case .object(_, let vs): return vs.contains { containsString($0, s) }
        default: return false
        }
    }

    // 정본: 준비선택값구조체
    static func optionalStruct(_ line: Int, _ name: BStr, _ valueType: BStr) -> J {
        let vis = enumValue("Visibility", "module")
        let m1 = astNode("StructFieldMetadata", ["name", "type_name", "visibility"], [jstr("있음"), jstr("참거짓"), vis])
        let m2 = astNode("StructFieldMetadata", ["name", "type_name", "visibility"], [jstr("값"), jstr(valueType), vis])
        let node = astNode("StructDef", ["name", "fields", "packed", "endian", "type_params", "type_constraints", "visibility", "field_metadata", "initializers", "member_functions", "compiler_generated", "compiler_generated_fields"],
                           [jstr(name), jobj(["있음", "값"], [jstr("참거짓"), jstr(valueType)]), jbool(false), .null, jarr([]), jarr([]), vis, jarr([m1, m2]), jarr([]), jarr([]), jbool(false), jarr([])])
        return lineStmt(line, node)
    }

    // 정본: 준비선택값후보수집
    static func collectOptionalCandidates(_ v: J, _ out: inout [BStr], _ seen: inout Set<BStr>) {
        switch v {
        case .string(let s):
            if s.hasSuffix("?") {
                let b = s.sub(0, s.count - 1)
                if !seen.contains(b) { seen.insert(b); out.append(b) }
            }
        case .array(let a): for x in a { collectOptionalCandidates(x, &out, &seen) }
        case .object(_, let vs): for x in vs { collectOptionalCandidates(x, &out, &seen) }
        default: break
        }
    }

    // 정본: 준비고정배열원소타입
    static func fixedArrayElement(_ t: BStr) -> BStr {
        if let sp = t.find(" "), t.find("개의 고정배열") != nil { return t.sub(0, sp) }
        return ""
    }

    // 정본: 준비고정배열길이
    static func fixedArrayLength(_ t: BStr) -> Int {
        if let sp = t.find(" "), let mk = t.find("개의 고정배열") {
            let start = sp + 1
            if let n = UInt64(t.sub(start, mk - start).string) { return Int(n) }
        }
        return 0
    }

    // 정본: 준비선택값구조이름
    static func optionalStructName(_ b: BStr) -> BStr {
        if Generic.isFunctionType(b) { return Generic.functionTypePrefix(b) + "선택값" }
        if fixedArrayElement(b).count > 0 { return "고정배열" + Generic.hash8(b) + "선택값" }
        if b.hasSuffix("의 배열") {
            var e = b.sub(0, b.count - BStr("의 배열").count)
            if e == "큰자연수" { e = "자연수64" } else if e == "큰정수" { e = "정수64" }
            return e + "배열" + "선택값"
        }
        if b == "큰자연수" { return "자연수64선택값" }
        if b == "큰정수" { return "정수64선택값" }
        return b + "선택값"
    }

    // 정본: 준비선택값별칭수집
    static func collectOptionalAliases(_ v: J, _ out: inout [BStr], _ seen: inout Set<BStr>) {
        switch v {
        case .string(let s):
            var cand = false
            if s.hasSuffix("의 배열") { cand = true }
            if fixedArrayElement(s).count > 0 { cand = true }
            if Generic.isFunctionType(s) { cand = true }
            if cand && !seen.contains(s) { seen.insert(s); out.append(s) }
        case .array(let a): for x in a { collectOptionalAliases(x, &out, &seen) }
        case .object(_, let vs): for x in vs { collectOptionalAliases(x, &out, &seen) }
        default: break
        }
    }

    // 정본: 준비생성함수있는가
    static func hasGeneratedFunction(_ list: [J], _ name: BStr) -> Bool {
        list.contains { ls in let n = lineNode(ls); return astKind(n) == "FunctionDef" && astStrField(n, "name") == name }
    }

    // 정본: 준비선택값주입
    static func injectOptionals(_ doc: J) -> J {
        guard let stmtsJ = doc.field("statements") else { return doc }
        let stmts = stmtsJ.arrayValue
        let cx = ContainerCtx(stmtsJ)
        let surfaces: [BStr] = ["자연수8", "자연수16", "자연수32", "큰자연수", "정수8", "정수16", "정수32", "큰정수", "실수32", "실수64", "문자", "참거짓", "주소", "문자열"]
        var topStructs: Set<BStr> = []
        for ls in stmts { let n = lineNode(ls); if astKind(n) == "StructDef" { topStructs.insert(astStrField(n, "name")) } }
        var gens: [J] = []
        for (i, p) in prefixes14.enumerated() {
            let origin = cx.originLine(p)
            if !topStructs.contains(p + "선택값") { gens.append(optionalStruct(origin, p + "선택값", surfaces[i])) }
        }
        var cands: [BStr] = [], seen: Set<BStr> = []
        collectOptionalCandidates(stmtsJ, &cands, &seen)
        var aliases: [BStr] = [], aseen: Set<BStr> = []
        collectOptionalAliases(stmtsJ, &aliases, &aseen)
        var aliasNames: [BStr: BStr] = [:]
        for a in aliases { let n = optionalStructName(a); if aliasNames[n] == nil { aliasNames[n] = a } }
        for b in cands {
            let sname = optionalStructName(b)
            if !topStructs.contains(sname) && !hasGeneratedFunction(gens, sname) {
                var need = false
                if !cx.findStruct(b).isNull { need = true }
                if b.hasSuffix("의 배열") { need = true }
                if fixedArrayElement(b).count > 0 { need = true }
                if Generic.isFunctionType(b) { need = true }
                var valueType = b
                if !need, let alias = aliasNames[sname], alias.count > 0 {
                    valueType = alias
                    need = true
                }
                if need {
                    let origin = cx.all.find(b + "?", false)
                    gens.append(optionalStruct(origin, sname, valueType))
                }
            }
        }
        var insertAt = 0
        for (i, ls) in stmts.enumerated() where astKind(lineNode(ls)) == "StructDef" { insertAt = i + 1 }
        var out: [J] = []
        out.reserveCapacity(stmts.count + gens.count)
        for (i, ls) in stmts.enumerated() {
            if i == insertAt { out.append(contentsOf: gens) }
            out.append(ls)
        }
        if insertAt == stmts.count { out.append(contentsOf: gens) }
        var r = objReplace(doc, "format", jstr("hmje-prepared-ast-v1"))
        r = objReplace(r, "statements", .array(out))
        return r
    }

    // 정본: 준비생성줄재배치
    static func relocateLines(_ v: J, _ line: Int) -> J {
        switch v {
        case .array(let a):
            var r = a.map { relocateLines($0, line) }
            if r.count == 2 && objField(r[0], "integer").stringValue != "" && astKind(r[1]) != "" { r[0] = intTag(line) }
            return .array(r)
        case .object(let ks, let vs): return .object(keys: ks, values: vs.map { relocateLines($0, line) })
        default: return v
        }
    }

    // 정본: 준비타입정렬
    static func typeAlign(_ cx: ContainerCtx, _ t: BStr) -> Int {
        if t.hasSuffix("?") { return typeAlign(cx, t.sub(0, t.count - 1)) }
        if t == "자연수8" || t == "정수8" || t == "문자" || t == "참거짓" { return 1 }
        if t == "자연수16" || t == "정수16" { return 2 }
        if t == "자연수32" || t == "정수32" || t == "실수32" { return 4 }
        if t == "문자열" || t == "주소" || t == "자연수64" || t == "큰자연수" || t == "정수64" || t == "큰정수" || t == "실수64" || t.hasSuffix("의 배열") { return 8 }
        let fe = fixedArrayElement(t)
        if fe.count > 0 { return typeAlign(cx, fe) }
        let s = cx.findStruct(t)
        if s.isNull { return 8 }
        var r = 1
        for f in astField(s, "fields").objectValues { let a = typeAlign(cx, astStr(f)); if a > r { r = a } }
        return r
    }

    // 정본: 준비정렬올림
    static func alignUp(_ v: Int, _ a: Int) -> Int { a <= 1 ? v : ((v + a) - 1) / a * a }

    // 정본: 준비타입크기
    static func typeSize(_ cx: ContainerCtx, _ t: BStr) -> Int {
        if t.hasSuffix("?") {
            let b = t.sub(0, t.count - 1)
            let a = typeAlign(cx, b)
            return alignUp(alignUp(1, a) + typeSize(cx, b), a)
        }
        if Generic.isFunctionType(t) { return 24 }
        if t == "자연수8" || t == "정수8" || t == "문자" || t == "참거짓" { return 1 }
        if t == "자연수16" || t == "정수16" { return 2 }
        if t == "자연수32" || t == "정수32" || t == "실수32" { return 4 }
        if t == "문자열" { return 32 }
        if t.hasSuffix("의 배열") { return 24 }
        let fe = fixedArrayElement(t)
        if fe.count > 0 { return alignUp(typeSize(cx, fe), typeAlign(cx, fe)) * fixedArrayLength(t) }
        if t == "주소" || t == "자연수64" || t == "큰자연수" || t == "정수64" || t == "큰정수" || t == "실수64" { return 8 }
        if t == "버퍼뷰" { return 16 }
        let s = cx.findStruct(t)
        if s.isNull { return 8 }
        var size = 0, maxA = 1
        for f in astField(s, "fields").objectValues {
            let ft = astStr(f)
            let a = typeAlign(cx, ft)
            size = alignUp(size, a)
            size += typeSize(cx, ft)
            if a > maxA { maxA = a }
        }
        return alignUp(size, maxA)
    }

    // 정본: 준비구조기본값
    static func structDefault(_ cx: ContainerCtx, _ t: BStr) -> J {
        if Generic.isFunctionType(t) { fatalError("미이식: 준비구조기본값(함수 타입 원소)") }
        if t.hasSuffix("의 배열") {
            let e = t.sub(0, t.count - BStr("의 배열").count)
            return astNode("CallExpr", ["name", "args", "compiler_generated"], [jstr(Generic.dynArrayPrefix(e) + "동적배열생성"), jarr([]), jbool(false)])
        }
        if t == "문자열" { return astNode("StringLiteral", ["value"], [jstr("")]) }
        if t == "참거짓" { return astNode("BoolLiteral", ["value"], [jbool(false)]) }
        if t == "버퍼뷰" {
            return astNode("StructInitExpr", ["name", "fields", "unsafe", "base", "compiler_generated"], [jstr("버퍼뷰"), jobj(["기준주소", "길이"], [structDefault(cx, "주소"), structDefault(cx, "자연수64")]), jbool(false), .null, jbool(false)])
        }
        // 정본: 준비채널타입분해 — 끝점 표면 표기
        let tails: [BStr] = ["를 보내는 채널", "을 보내는 채널", "를 받는 채널", "을 받는 채널"]
        for tl in tails where t.hasSuffix(tl) { fatalError("미이식: 준비구조기본값(채널 끝점 \(t))") }
        let s = cx.findStruct(t)
        if !s.isNull {
            let f = astField(s, "fields")
            let defs = f.objectValues.map { structDefault(cx, astStr($0)) }
            return astNode("StructInitExpr", ["name", "fields", "unsafe", "base", "compiler_generated"], [jstr(t), jobj(f.objectKeys, defs), jbool(false), .null, jbool(false)])
        }
        return astNode("CastExpr", ["type_name", "expr", "compiler_generated"], [jstr(t), astNode("IntLiteral", ["value"], [jobj(["integer"], [jstr("0")])]), jbool(false)])
    }

    // 정본: 준비문자열모두치환
    static func replaceAll(_ s: BStr, _ find: BStr, _ repl: BStr) -> BStr {
        guard s.find(find) != nil else { return s }
        var out: [UInt8] = []
        var rest = s
        while let p = rest.find(find) {
            out.append(contentsOf: rest.sub(0, p).bytes)
            out.append(contentsOf: repl.bytes)
            let n = p + find.count
            rest = rest.sub(n, rest.count - n)
        }
        out.append(contentsOf: rest.bytes)
        return BStr(out)
    }

    // 정본: 준비구조배열형판치환
    static func templateSubst(_ v: J, _ cx: ContainerCtx, _ prefix: BStr, _ t: BStr, _ size: Int) -> J {
        if case .object(let ks, let vs) = v {
            if astKind(v) == "StructInitExpr" && astStrField(v, "name") == "JSON값" { return structDefault(cx, t) }
            return .object(keys: ks, values: vs.map { templateSubst($0, cx, prefix, t, size) })
        }
        if case .string(let s0) = v {
            var s = s0
            if s == "128" { s = BStr(decimal: size) }
            if s == "JSON값" { return jstr(t) }
            s = replaceAll(s, "JSON값", prefix)
            return jstr(s)
        }
        if case .array(let a) = v { return .array(a.map { templateSubst($0, cx, prefix, t, size) }) }
        return v
    }

    // 정본: 준비구조배열후보수집
    static func collectStructArrayCandidates(_ v: J, _ out: inout [BStr], _ seen: inout Set<BStr>) {
        switch v {
        case .string(let s):
            if s.hasSuffix("의 배열") {
                let e = s.sub(0, s.count - BStr("의 배열").count)
                if e.hasSuffix("의 배열") { collectStructArrayCandidates(jstr(e), &out, &seen) }
                if !seen.contains(e) { seen.insert(e); out.append(e) }
            } else if s.hasSuffix("동적배열형") {
                let e = s.sub(0, s.count - BStr("동적배열형").count)
                if !seen.contains(e) { seen.insert(e); out.append(e) }
            }
        case .array(let a): for x in a { collectStructArrayCandidates(x, &out, &seen) }
        case .object(_, let vs): for x in vs { collectStructArrayCandidates(x, &out, &seen) }
        default: break
        }
    }

    // 정본: 준비선택값이름인가
    static func isOptionalName(_ n: BStr) -> Bool { prefixes14.contains { n == $0 + "선택값" } }

    // 정본: 준비기본동적배열주입
    static func injectDynamicArrays(_ doc: J, _ templateSource: BStr) -> J {
        guard let stmtsJ = doc.field("statements") else { return doc }
        let stmts = stmtsJ.arrayValue
        let parsed = parseSource(bytes: templateSource.bytes)
        if !parsed.ok { return doc }
        let tmpl = parsed.statements.map(jsonFromLine)
        let cx = ContainerCtx(stmtsJ)
        let prefixes: [BStr] = Array(prefixes14.prefix(13))
        let needStrArr = containsString(stmtsJ, "문자열의 배열")
        let needToken = containsString(stmtsJ, "소스토큰")
        let needJSON = containsString(stmtsJ, "JSON값")
        let origins = prefixes.map { cx.originLine($0) }
        let strOrigin = cx.originLine("문자열")
        var gens: [J] = [], strGens: [J] = []
        for ls in tmpl {
            let name = astStrField(lineNode(ls), "name")
            var origin = 0
            var userNeed = true
            if name.hasPrefix("소스토큰") { userNeed = needToken } else if name.hasPrefix("JSON값") { userNeed = needJSON }
            var match: BStr = ""
            if name.hasPrefix("문자열배열") {
                origin = strOrigin
            } else {
                for (i, p) in prefixes.enumerated() where name.hasPrefix(p) { origin = origins[i]; match = p; break }
            }
            var allow = true
            if name.hasPrefix("문자열배열") && !needStrArr { allow = false }
            if match.count > 0 && cx.findStruct(match + "동적배열형").isNull { allow = false }
            if userNeed && allow {
                if name.hasPrefix("문자열배열") { strGens.append(relocateLines(ls, origin)) } else { gens.append(relocateLines(ls, origin)) }
            }
        }
        var cands: [BStr] = [], seen: Set<BStr> = []
        collectStructArrayCandidates(stmtsJ, &cands, &seen)
        var topFuncNames: Set<BStr> = []
        for ls in stmts { let n = lineNode(ls); if astKind(n) == "FunctionDef" { topFuncNames.insert(astStrField(n, "name")) } }
        var genFuncNames: Set<BStr> = []
        for g in gens { let n = lineNode(g); if astKind(n) == "FunctionDef" { genFuncNames.insert(astStrField(n, "name")) } }
        for elem in cands {
            let es = cx.findStruct(elem)
            let isFn = Generic.isFunctionType(elem)
            let prefix = Generic.dynArrayPrefix(elem)
            let seeded = genFuncNames.contains(prefix + "동적배열가져오기")
            var target = false
            if !es.isNull { target = true }
            if isFn { target = true }
            if elem.hasSuffix("의 배열") { target = true }
            if seeded { target = false }
            if target {
                let size = typeSize(cx, elem)
                let origin = cx.originLine(elem)
                if isFn { fatalError("미이식: 준비기본동적배열주입(함수값 원소 \(elem))") }
                for ts in tmpl {
                    let tn = lineNode(ts)
                    if astStrField(tn, "name").hasPrefix("JSON값") {
                        let sp = templateSubst(ts, cx, prefix, elem, size)
                        let sn = lineNode(sp)
                        let sname = astStrField(sn, "name")
                        var defined = topFuncNames.contains(sname)
                        if astKind(sn) == "StructDef" && !cx.findStruct(sname).isNull { defined = true }
                        if !defined {
                            let g = relocateLines(sp, origin)
                            gens.append(g)
                            if astKind(sn) == "FunctionDef" { genFuncNames.insert(sname) }
                        }
                    }
                }
            }
        }
        for elem in cands {
            let es = cx.findStruct(elem)
            if !es.isNull {
                for f in astField(es, "fields").objectValues where Generic.isFunctionType(astStr(f)) {
                    fatalError("미이식: 준비기본동적배열주입(함수값 필드 빈 함수)")
                }
            }
        }
        var ordered: [J] = []
        ordered.append(contentsOf: strGens.prefix(14))
        ordered.append(contentsOf: gens)
        if strGens.count > 14 { ordered.append(contentsOf: strGens[14...]) }
        var insertAt = stmts.count
        for (i, ls) in stmts.enumerated() {
            let n = lineNode(ls)
            if astKind(n) == "StructDef" && isOptionalName(astStrField(n, "name")) { insertAt = i; break }
        }
        var out: [J] = []
        out.reserveCapacity(stmts.count + ordered.count)
        for (i, ls) in stmts.enumerated() {
            if i == insertAt { out.append(contentsOf: ordered) }
            out.append(ls)
        }
        if insertAt == stmts.count { out.append(contentsOf: ordered) }
        return objReplace(doc, "statements", .array(out))
    }

    // MARK: 배열 리터럴 (준비/배열리터럴.hmje)

    // 정본: 준비배열리터럴원소타입확정인가
    static func elementTypeSettled(_ cx: ContainerCtx, _ e: BStr) -> Bool {
        let prims: Set<BStr> = ["문자열", "참거짓", "주소", "문자", "자연수8", "자연수16", "자연수32", "자연수64", "정수8", "정수16", "정수32", "정수64", "실수32", "실수64", "큰자연수", "큰정수"]
        if prims.contains(e) { return true }
        return !cx.findStruct(e).isNull
    }

    // 정본: 준비배열리터럴선언인가
    static func isArrayLiteralDecl(_ cx: ContainerCtx, _ n: J) -> Bool {
        if astKind(n) != "Define" || !astBoolField(n, "mutable") { return false }
        let e = astField(n, "expr")
        if e.isNull || astKind(e) != "ArrayLiteral" { return false }
        let t = astStrField(n, "type_name")
        if t.count == 0 { return true }
        if !t.hasSuffix("의 배열") { return false }
        return elementTypeSettled(cx, t.sub(0, t.count - BStr("의 배열").count))
    }

    // 정본: 준비배열리터럴펼치기
    static func expandArrayLiteral(_ lineV: J, _ n: J, _ out: inout [J]) {
        let name = astStrField(n, "name")
        let written = astStrField(n, "type_name")
        var type: BStr = "자연수64의 배열", elem: BStr = "자연수64"
        if written.count > 0 { type = written; elem = written.sub(0, written.count - BStr("의 배열").count) }
        let prefix = Generic.dynArrayPrefix(elem)
        let create = astNode("CallExpr", ["name", "args", "compiler_generated"], [jstr(prefix + "동적배열생성"), jarr([]), jbool(false)])
        out.append(jarr([lineV, astNode("Define", ["mutable", "name", "type_name", "expr", "retain_borrowed_owner", "compiler_generated"], [jbool(true), jstr(name), jstr(type), create, jbool(false), jbool(false)])]))
        for el in astField(astField(n, "expr"), "elements").arrayValue {
            let nameE = astNode("NameExpr", ["name", "compiler_generated"], [jstr(name), jbool(false)])
            let cast = astNode("CastExpr", ["type_name", "expr", "compiler_generated"], [jstr(elem), el, jbool(false)])
            let call = astNode("CallExpr", ["name", "args", "compiler_generated"], [jstr(prefix + "동적배열추가"), jarr([nameE, cast]), jbool(false)])
            let assign = astNode("Assign", ["target", "expr"], [astNode("NameTarget", ["name"], [jstr(name)]), call])
            out.append(jarr([lineV, assign]))
        }
    }

    // 정본: 준비배열리터럴값
    static func arrayLiteralValue(_ v: J, _ cx: ContainerCtx) -> J {
        switch v {
        case .array(let a):
            var out: [J] = []
            out.reserveCapacity(a.count)
            for x in a {
                let el = arrayLiteralValue(x, cx)
                var expanded = false
                if case .array(let pair) = el, pair.count == 2, pair[1].isObject, isArrayLiteralDecl(cx, pair[1]) {
                    expandArrayLiteral(pair[0], pair[1], &out)
                    expanded = true
                }
                if !expanded { out.append(el) }
            }
            return .array(out)
        case .object(let ks, let vs): return .object(keys: ks, values: vs.map { arrayLiteralValue($0, cx) })
        default: return v
        }
    }

    // 정본: 준비배열리터럴문서낮추기
    static func lowerArrayLiterals(_ doc: J) -> J {
        guard let stmts = doc.field("statements") else { return doc }
        let cx = ContainerCtx(stmts)
        return objReplace(doc, "statements", arrayLiteralValue(stmts, cx))
    }
}
