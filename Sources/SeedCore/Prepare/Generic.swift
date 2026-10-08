// 정본: 준비/제네릭.hmje (+ 준비/구조단형.hmje 중 사용자 제네릭 구조체가 없을 때의 갈래).
// 준비제네릭기본정리 = 준비단형문서낮추기(임의 타입 함수 단형화) → 사전·집합 컨테이너 특수화
// → 미룬 기본값 풀기 → 리터럴 강제 → 준비특성문서검증(검증만 — 문서를 바꾸지 않으므로 생략).

enum Generic {
    // MARK: 이름·해시

    // 정본: 준비제네릭SHA1첫말 (SHA-1의 첫 32비트 단어)
    static func sha1FirstWord(_ s: BStr) -> UInt32 {
        let msg = s.bytes
        let origLen = msg.count
        var padLen = origLen + 1
        while padLen % 64 != 56 { padLen += 1 }
        let total = padLen + 8
        var h0: UInt32 = 0x67452301, h1: UInt32 = 0xefcdab89, h2: UInt32 = 0x98badcfe, h3: UInt32 = 0x10325476, h4: UInt32 = 0xc3d2e1f0
        let bitLen = UInt64(origLen) &* 8
        var block = 0
        var w = [UInt32](repeating: 0, count: 80)
        while block < total {
            for i in 0..<80 { w[i] = 0 }
            for i in 0..<64 {
                let g = block + i
                var byte: UInt32 = 0
                if g < origLen { byte = UInt32(msg[g]) } else if g == origLen { byte = 0x80 } else if g >= total - 8 {
                    let shift = UInt64((total - 1 - g) * 8)
                    byte = UInt32((bitLen >> shift) & 0xff)
                }
                w[i / 4] = (w[i / 4] << 8) | byte
            }
            for i in 16..<80 {
                let x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (x << 1) | (x >> 31)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                var f: UInt32, k: UInt32
                if i < 20 { f = (b & c) | (~b & d); k = 0x5a827999 } else if i < 40 { f = b ^ c ^ d; k = 0x6ed9eba1 } else if i < 60 { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc } else { f = b ^ c ^ d; k = 0xca62c1d6 }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = (b << 30) | (b >> 2); b = a; a = temp
            }
            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d; h4 = h4 &+ e
            block += 64
        }
        return h0
    }

    // 정본: 준비제네릭해시8
    static func hash8(_ s: BStr) -> BStr {
        let v = sha1FirstWord(s)
        let hex: [UInt8] = Array("0123456789abcdef".utf8)
        var out: [UInt8] = []
        for i in 0..<8 { out.append(hex[Int((v >> UInt32((7 - i) * 4)) & 15)]) }
        return BStr(out)
    }

    // 정본: 준비제네릭함수타입인가
    static func isFunctionType(_ t: BStr) -> Bool {
        if !(t.hasSuffix("반환") || t.hasSuffix("반환하지 않음")) { return false }
        return t.find(" 받아 ") != nil || t.find("받지 않고") != nil
    }

    // 정본: 준비제네릭함수타입접두
    static func functionTypePrefix(_ t: BStr) -> BStr { "함수값" + BStr(t.bytes.filter { $0 != 32 }) }

    // 정본: 준비제네릭타입내부
    static func typeInternal(_ s: BStr) -> BStr {
        if s == "문자열" || s == "글" || s == "string" || s == "text" { return "text" }
        if s == "자연수64" || s == "큰자연수" || s == "자연수" { return "u64" }
        if s == "정수64" || s == "큰정수" || s == "정수" { return "i64" }
        return s
    }

    // 정본: 준비제네릭타입표시
    static func typeDisplay(_ s: BStr) -> BStr {
        if s.hasSuffix("?") { return typeDisplay(s.sub(0, s.count - 1)) + "?" }
        if s.hasSuffix("의 배열") {
            let l = BStr("의 배열").count
            return typeDisplay(s.sub(0, s.count - l)) + "의 배열"
        }
        if s == "자연수64" || s == "자연수" { return "큰자연수" }
        if s == "정수64" || s == "정수" { return "큰정수" }
        return s
    }

    // 정본: 준비제네릭후보인가
    static func isCandidate(_ t: BStr) -> Bool {
        if t.hasSuffix("를 찾는 사전") && t.find("로 ") != nil { return true }
        if t.hasSuffix("을 찾는 사전") && t.find("로 ") != nil { return true }
        return t.hasSuffix("의 집합")
    }

    // 정본: 준비제네릭후보수집
    static func collectCandidates(_ v: J, _ out: inout [BStr], _ seen: inout Set<BStr>) {
        switch v {
        case .string(let s):
            if isCandidate(s) && !seen.contains(s) { out.append(s); seen.insert(s) }
        case .array(let a): for x in a { collectCandidates(x, &out, &seen) }
        case .object(_, let vs): for x in vs { collectCandidates(x, &out, &seen) }
        default: break
        }
    }

    // 정본: 준비제네릭후보풀기
    static func unpackCandidate(_ c: BStr) -> [BStr] {
        if c.hasSuffix("의 집합") {
            return ["집합", c.sub(0, c.count - BStr("의 집합").count)]
        }
        guard let split = c.find("로 ") else { return [] }
        let backStart = split + BStr("로 ").count
        var tail: BStr = "를 찾는 사전"
        if c.hasSuffix("을 찾는 사전") { tail = "을 찾는 사전" }
        return ["사전", c.sub(0, split), c.sub(backStart, c.count - backStart - tail.count)]
    }

    // 정본: 준비제네릭특수이름
    static func specName(_ unpacked: [BStr]) -> BStr {
        var name = unpacked[0]
        var hashIn: BStr = ""
        for i in 1..<max(1, unpacked.count) {
            name = name + "__" + typeDisplay(unpacked[i])
            if i > 1 { hashIn = hashIn + "|" }
            hashIn = hashIn + typeInternal(unpacked[i])
        }
        return name + "_" + hash8(hashIn)
    }

    // 정본: 준비제네릭필드타입
    static func fieldType(_ t: BStr, _ params: [BStr], _ args: [BStr]) -> BStr {
        for i in 0..<params.count where t == params[i] { return typeDisplay(args[i]) }
        if t.hasSuffix("의 배열") {
            let l = BStr("의 배열").count
            return fieldType(t.sub(0, t.count - l), params, args) + "의 배열"
        }
        if t.hasSuffix("?") { return fieldType(t.sub(0, t.count - 1), params, args) + "?" }
        return typeDisplay(t)
    }

    // 정본: 준비제네릭동적배열접두
    static func dynArrayPrefix(_ elem: BStr) -> BStr {
        let d = typeDisplay(elem)
        if d.hasSuffix("의 배열") { return dynArrayPrefix(d.sub(0, d.count - BStr("의 배열").count)) + "배열" }
        if isFunctionType(d) { return functionTypePrefix(d) }
        if d == "문자열" { return "문자열배열" }
        if d == "큰자연수" { return "자연수64" }
        if d == "큰정수" { return "정수64" }
        return d
    }

    // MARK: 문맥

    final class Ctx {
        var candidates: [BStr] = []
        var unpacked: [[BStr]] = []
        var specNames: [BStr] = []
        var declStructMap: [BStr: BStr] = [:]

        init(_ cands: [BStr]) {
            candidates = cands
            for c in cands {
                let u = unpackCandidate(c)
                unpacked.append(u)
                let s = u.count > 0 ? specName(u) : BStr("")
                specNames.append(s)
                // 정본: 준비제네릭선언구조 — 앞 후보부터, 후보 자체 또는 특수이름이 맞으면 그 특수이름.
                if declStructMap[c] == nil { declStructMap[c] = s }
                if declStructMap[s] == nil { declStructMap[s] = s }
            }
        }

        // 정본: 준비제네릭선언구조
        func declStruct(_ t: BStr) -> BStr { declStructMap[t] ?? "" }
    }

    static func lineNodeOf(_ ls: J) -> J { lineNode(ls) }

    // 정본: 준비제네릭구조특수화
    static func specializeStruct(_ ls: J, _ unpacked: [BStr]) -> J {
        let node = lineNode(ls)
        let orig = astField(node, "fields")
        let pj = astField(node, "type_params").arrayValue
        var params: [BStr] = [], args: [BStr] = []
        for i in 0..<pj.count { params.append(astStr(pj[i])); args.append(i + 1 < unpacked.count ? unpacked[i + 1] : "") }
        let newVals = orig.objectValues.map { jstr(fieldType(astStr($0), params, args)) }
        var n = nodeReplace(node, "name", jstr(specName(unpacked)))
        n = nodeReplace(n, "fields", jobj(orig.objectKeys, newVals))
        n = nodeReplace(n, "type_params", jarr([]))
        n = nodeReplace(n, "type_constraints", jarr([]))
        n = nodeReplace(n, "field_metadata", jarr([]))
        return jarr([ls.arrayValue[0], n])
    }

    // 정본: 준비제네릭함수기반
    static func functionBase(_ fn: J, _ genStructs: [J]) -> BStr {
        for p in astField(fn, "params").arrayValue {
            let t = astStrField(p, "type_name")
            for gs in genStructs where t == astStrField(lineNode(gs), "name") { return t }
        }
        return ""
    }

    // 정본: 준비제네릭함수매개들
    static func functionParams(_ fn: J, _ base: BStr, _ genStructs: [J]) -> [BStr] {
        let explicit = astField(fn, "type_params")
        if case .array(let a) = explicit, a.count > 0 { return a.map(astStr) }
        for gs in genStructs {
            let sn = lineNode(gs)
            if astStrField(sn, "name") == base { return astField(sn, "type_params").arrayValue.map(astStr) }
        }
        return []
    }

    // 정본: 준비제네릭타입치환
    static func substType(_ t: BStr, _ params: [BStr], _ args: [BStr], _ base: BStr, _ specStruct: BStr) -> BStr {
        if t == base { return specStruct }
        return fieldType(t, params, args)
    }

    // 정본: 준비제네릭값치환
    static func substValue(_ v: J, _ params: [BStr], _ args: [BStr], _ base: BStr, _ spec: BStr, _ typePos: Bool) -> J {
        switch v {
        case .string(let s):
            if typePos { return jstr(substType(s, params, args, base, spec)) }
            return v
        case .array(let a): return .array(a.map { substValue($0, params, args, base, spec, false) })
        case .object(let ks, let vs):
            let kind = astKind(v)
            var nv: [J] = []
            nv.reserveCapacity(vs.count)
            for i in 0..<ks.count {
                let k = ks[i]
                var nextType = false
                if k == "type_name" || k == "return_type" || k == "value_type" || k == "struct_name" { nextType = true }
                if kind == "StructDef" && k == "fields" { nextType = true }
                if kind == "StructInitExpr" && k == "name" && astStr(vs[i]) == base {
                    nv.append(jstr(spec))
                } else {
                    nv.append(substValue(vs[i], params, args, base, spec, nextType))
                }
            }
            var r = J.object(keys: ks, values: nv)
            if astKind(r) == "StructInitExpr" && astStrField(r, "name") == base { r = nodeReplace(r, "name", jstr(spec)) }
            return r
        default: return v
        }
    }

    // 정본: 준비제네릭함수특수화
    static func specializeFunction(_ ls: J, _ unpacked: [BStr], _ base: BStr, _ genStructs: [J]) -> J {
        let node = lineNode(ls)
        let params = functionParams(node, base, genStructs)
        let args = Array(unpacked.dropFirst())
        let specStruct = specName(unpacked)
        var n = substValue(node, params, args, base, specStruct, false)
        let fnUnpacked = [astStrField(node, "name")] + args
        n = nodeReplace(n, "name", jstr(specName(fnUnpacked)))
        n = nodeReplace(n, "external_name", .null)
        n = nodeReplace(n, "type_params", jarr([]))
        n = nodeReplace(n, "type_constraints", jarr([]))
        let newParams = astField(n, "params").arrayValue.map { nodeReplace($0, "compiler_generated", jbool(false)) }
        n = nodeReplace(n, "params", jarr(newParams))
        return jarr([ls.arrayValue[0], n])
    }

    // MARK: 사전·집합 재작성

    // 정본: 준비제네릭심볼타입
    static func symbolType(_ name: BStr, _ names: [BStr], _ types: [BStr]) -> BStr {
        var i = names.count
        while i > 0 { i -= 1; if names[i] == name { return types[i] } }
        return ""
    }

    // 정본: 준비제네릭식구조
    static func exprStruct(_ e: J, _ names: [BStr], _ types: [BStr], _ ctx: Ctx) -> BStr {
        let k = astKind(e)
        if k == "NameExpr" { return symbolType(astStrField(e, "name"), names, types) }
        if k == "StructInitExpr" { return ctx.declStruct(astStrField(e, "name")) }
        return ""
    }

    // 정본: 준비제네릭심볼수집
    static func collectSymbols(_ v: J, _ ctx: Ctx, _ names: inout [BStr], _ types: inout [BStr]) {
        switch v {
        case .object(_, let vs):
            let k = astKind(v)
            if k == "Define" || k == "GlobalDefine" || k == "Parameter" {
                let name = astStrField(v, "name")
                let st = ctx.declStruct(astStrField(v, "type_name"))
                if name != "" && st != "" { names.append(name); types.append(st) }
            }
            for x in vs { collectSymbols(x, ctx, &names, &types) }
        case .array(let a): for x in a { collectSymbols(x, ctx, &names, &types) }
        default: break
        }
    }

    // 정본: 준비제네릭호출특수이름
    static func callSpecName(_ callName: BStr, _ args: J, _ names: [BStr], _ types: [BStr], _ ctx: Ctx, _ genFuncs: [J], _ genFuncNames: [BStr], _ genStructs: [J]) -> BStr {
        for fi in 0..<genFuncs.count where genFuncNames[fi] == callName {
            let fn = lineNode(genFuncs[fi])
            let base = functionBase(fn, genStructs)
            let ps = astField(fn, "params").arrayValue
            let as_ = args.arrayValue
            var pi = 0
            while pi < ps.count && pi < as_.count {
                if astStrField(ps[pi], "type_name") == base {
                    let actual = exprStruct(as_[pi], names, types, ctx)
                    for ci in 0..<ctx.candidates.count {
                        let u = ctx.unpacked[ci]
                        if u.count > 0 && u[0] == base && ctx.specNames[ci] == actual {
                            return specName([callName] + u.dropFirst())
                        }
                    }
                }
                pi += 1
            }
        }
        return ""
    }

    struct Requests {
        var names: [BStr] = []
        var nameSet: Set<BStr> = []
        var lines: [Int] = []
        mutating func add(_ n: BStr, _ line: Int) {
            if !nameSet.contains(n) { names.append(n); nameSet.insert(n); lines.append(line) }
        }
    }

    // 정본: 준비제네릭값재작성
    static func rewriteValue(_ v: J, _ curLine: Int, _ names: [BStr], _ types: [BStr], _ ctx: Ctx, _ genFuncs: [J], _ genFuncNames: [BStr], _ genStructs: [J], _ req: inout Requests) -> J {
        switch v {
        case .string, .number, .bool, .null: return v
        case .array(let a):
            var next = curLine
            if a.count == 2, objField(a[0], "integer").stringValue != "", astKind(a[1]) != "" {
                if let n = Int(objField(a[0], "integer").stringValue.string) { next = n }
            }
            var out: [J] = []
            out.reserveCapacity(a.count)
            for x in a { out.append(rewriteValue(x, next, names, types, ctx, genFuncs, genFuncNames, genStructs, &req)) }
            return .array(out)
        case .object(let ks, let vs):
            let kind = astKind(v)
            var out: [J] = []
            out.reserveCapacity(vs.count)
            for i in 0..<ks.count {
                let k = ks[i]
                var input = vs[i]
                let typeKey = k == "type_name" || k == "return_type" || k == "value_type" || k == "struct_name"
                if typeKey, case .string(let s) = input {
                    let c = ctx.declStruct(s)
                    if c != "" { input = jstr(c) }
                }
                if kind == "StructDef" && k == "fields", case .object(let fk, var fv) = input {
                    for j in 0..<fv.count {
                        if case .string(let s) = fv[j] {
                            let c = ctx.declStruct(s)
                            if c != "" { fv[j] = jstr(c) }
                        }
                    }
                    input = .object(keys: fk, values: fv)
                }
                out.append(rewriteValue(input, curLine, names, types, ctx, genFuncs, genFuncNames, genStructs, &req))
            }
            var nv = J.object(keys: ks, values: out)
            if astKind(nv) == "StructDef" {
                let sf = astField(nv, "fields")
                var fv = sf.objectValues
                for j in 0..<fv.count {
                    if case .string(let s) = fv[j] {
                        let c = ctx.declStruct(s)
                        if c != "" { fv[j] = jstr(c) }
                    }
                }
                nv = nodeReplace(nv, "fields", jobj(sf.objectKeys, fv))
            }
            if astKind(nv) == "CallExpr" {
                let sn = callSpecName(astStrField(nv, "name"), astField(nv, "args"), names, types, ctx, genFuncs, genFuncNames, genStructs)
                if sn != "" {
                    nv = nodeReplace(nv, "name", jstr(sn))
                    req.add(sn, curLine)
                }
            }
            return lowerEmptyDynArray(nv)
        }
    }

    // 정본: 준비제네릭빈동적배열낮추기
    static func lowerEmptyDynArray(_ v: J) -> J {
        guard v.isObject, astKind(v) == "Define", astBoolField(v, "mutable") else { return v }
        let t = astStrField(v, "type_name")
        let e = astField(v, "expr")
        if t.hasSuffix("의 배열") && astKind(e) == "ArrayLiteral" && astField(e, "elements").arrayValue.count == 0 {
            let elem = t.sub(0, t.count - BStr("의 배열").count)
            let call = astNode("CallExpr", ["name", "args", "compiler_generated"], [jstr(dynArrayPrefix(elem) + "동적배열생성"), jarr([]), jbool(false)])
            var r = nodeReplace(v, "expr", call)
            r = nodeReplace(r, "type_name", jstr(typeDisplay(elem) + "의 배열"))
            return r
        }
        return v
    }

    // 정본: 준비제네릭함수정의수집
    static func collectFunctionDefs(_ v: J, _ out: inout [J]) {
        switch v {
        case .object(_, let vs):
            if astKind(v) == "FunctionDef" { out.append(v) }
            for x in vs { collectFunctionDefs(x, &out) }
        case .array(let a): for x in a { collectFunctionDefs(x, &out) }
        default: break
        }
    }

    // 정본: 준비제네릭구조정의수집
    static func collectStructDefs(_ v: J, _ out: inout [J]) {
        switch v {
        case .object(_, let vs):
            if astKind(v) == "StructDef" { out.append(v) }
            for x in vs { collectStructDefs(x, &out) }
        case .array(let a): for x in a { collectStructDefs(x, &out) }
        default: break
        }
    }

    // 정본: 준비제네릭영정수
    static func zeroInt() -> J { astNode("IntLiteral", ["value"], [jobj(["integer"], [jstr("0")])]) }

    // 정본: 준비제네릭기본식
    static func defaultExpr(_ t: BStr, _ structs: [J]) -> J {
        let d = typeDisplay(t)
        if d.hasSuffix("의 배열") {
            let elem = d.sub(0, d.count - BStr("의 배열").count)
            return astNode("CallExpr", ["name", "args", "compiler_generated"], [jstr(dynArrayPrefix(elem) + "동적배열생성"), jarr([]), jbool(false)])
        }
        if d == "문자열" { return astNode("StringLiteral", ["value"], [jstr("")]) }
        if d == "참거짓" { return astNode("BoolLiteral", ["value"], [jbool(false)]) }
        for s in structs where astStrField(s, "name") == d {
            let f = astField(s, "fields")
            let defs = f.objectValues.map { defaultExpr(astStr($0), structs) }
            return astNode("StructInitExpr", ["name", "fields", "unsafe", "base", "compiler_generated"], [jstr(d), jobj(f.objectKeys, defs), jbool(false), .null, jbool(false)])
        }
        return astNode("CastExpr", ["type_name", "expr", "compiler_generated"], [jstr(d), zeroInt(), jbool(false)])
    }

    // 정본: 준비제네릭미룬기본값풀기
    static func resolveDeferredDefaults(_ v: J, _ structs: [J], _ byName: [BStr: J]) -> J {
        switch v {
        case .array(let a): return .array(a.map { resolveDeferredDefaults($0, structs, byName) })
        case .object(let ks, let vs):
            var n = J.object(keys: ks, values: vs.map { resolveDeferredDefaults($0, structs, byName) })
            let k = astKind(n)
            if (k == "Define" || k == "GlobalDefine") && astKind(astField(n, "expr")) == "DeferredDefaultExpr" {
                n = nodeReplace(n, "expr", defaultExpr(astStrField(n, "type_name"), structs))
            }
            if astKind(n) == "StructInitExpr" && astStrField(n, "name").find("__") != nil {
                if let s = byName[astStrField(n, "name")] {
                    let declF = astField(s, "fields")
                    let initF = astField(n, "fields")
                    var iv = initF.objectValues
                    let dk = declF.objectKeys, dv = declF.objectValues
                    for (fi, key) in initF.objectKeys.enumerated() {
                        for di in 0..<dk.count where dk[di] == key {
                            let ek = astKind(iv[fi])
                            if ek == "IntLiteral" || ek == "FloatLiteral" || ek == "StringLiteral" {
                                iv[fi] = astNode("CastExpr", ["type_name", "expr", "compiler_generated"], [jstr(typeDisplay(astStr(dv[di]))), iv[fi], jbool(false)])
                            }
                            break
                        }
                    }
                    n = nodeReplace(n, "fields", jobj(initF.objectKeys, iv))
                }
            }
            return n
        default: return v
        }
    }

    // MARK: 리터럴 강제

    struct LiteralIndex {
        var heads: [BStr: Int] = [:]
        var names: [BStr] = []
        var params: [J] = []
        var nexts: [Int] = []
        var specIdx: [Int] = []
    }

    // 정본: 준비리터럴색인만들기
    static func makeLiteralIndex(_ funcs: [J]) -> LiteralIndex {
        var ix = LiteralIndex()
        for (i, f) in funcs.enumerated() {
            let name = astStrField(f, "name")
            ix.names.append(name)
            ix.params.append(astField(f, "params"))
            ix.nexts.append(0)
            if name.find("__") != nil { ix.specIdx.append(i) }
        }
        var i = funcs.count
        while i > 0 {
            i -= 1
            ix.nexts[i] = ix.heads[ix.names[i]] ?? 0
            ix.heads[ix.names[i]] = i + 1
        }
        return ix
    }

    // 정본: 준비제네릭호출후보이름
    static func callCandidateName(_ callName: BStr, _ args: J, _ ix: LiteralIndex) -> BStr {
        var candName: BStr = "", count = 0
        let prefix = callName + "__"
        let as_ = args.arrayValue
        for idx in ix.specIdx {
            let name = ix.names[idx]
            let ps = ix.params[idx].arrayValue
            var ok = name.hasPrefix(prefix)
            if ps.count != as_.count { ok = false }
            var ai = 0
            while ai < as_.count && ok {
                let ak = astKind(as_[ai])
                let pt = typeDisplay(astStrField(ps[ai], "type_name"))
                if ak == "CastExpr" && typeDisplay(astStrField(as_[ai], "type_name")) != pt { ok = false }
                if ak == "StringLiteral" && pt != "문자열" { ok = false }
                ai += 1
            }
            if ok { count += 1; candName = name }
        }
        return count == 1 ? candName : callName
    }

    // 정본: 준비제네릭리터럴강제색인
    static func coerceLiterals(_ v: J, _ ix: LiteralIndex) -> J {
        switch v {
        case .array(let a): return .array(a.map { coerceLiterals($0, ix) })
        case .object(let ks, let vs):
            var n = J.object(keys: ks, values: vs.map { coerceLiterals($0, ix) })
            guard astKind(n) == "CallExpr" else { return n }
            var callName = astStrField(n, "name")
            let argJ = astField(n, "args")
            let cand = callCandidateName(callName, argJ, ix)
            if cand != callName { callName = cand; n = nodeReplace(n, "name", jstr(callName)) }
            var fi = ix.heads[callName] ?? 0
            var c = fi, same = 0
            while c > 0 {
                if ix.params[c - 1].arrayValue.count == argJ.arrayValue.count { same += 1 }
                c = ix.nexts[c - 1]
            }
            if same != 1 { return n }
            while fi > 0 {
                let pj = ix.params[fi - 1].arrayValue
                if pj.count == argJ.arrayValue.count {
                    var na = argJ.arrayValue
                    for ai in 0..<na.count {
                        let ak = astKind(na[ai])
                        if ak == "StringLiteral" || ak == "IntLiteral" || ak == "FloatLiteral" {
                            var force = true
                            if callName == "쓰기조각" && ak == "StringLiteral" {
                                let sv = astStrField(na[ai], "value")
                                if sv == "-" || sv == "." || sv == "0" || sv == "참" || sv == "\n" { force = false }
                            }
                            if ak == "StringLiteral" && astStrField(na[ai], "value") == "\n" {
                                if callName == "출력조각" || callName == "오류출력조각" { force = false }
                            }
                            if force {
                                let target = typeDisplay(astStrField(pj[ai], "type_name"))
                                let ti = Mono.primInternal(target)
                                var compat = false
                                if ak == "StringLiteral" { if ti == "text" || ti == "char" { compat = true } }
                                if ak == "IntLiteral" { if ti.hasPrefix("i") || ti.hasPrefix("u") || ti.hasPrefix("f") || ti == "address" { compat = true } }
                                if ak == "FloatLiteral" { compat = ti.hasPrefix("f") }
                                if compat {
                                    na[ai] = astNode("CastExpr", ["type_name", "expr", "compiler_generated"], [jstr(target), na[ai], jbool(false)])
                                }
                            }
                        }
                    }
                    n = nodeReplace(n, "args", jarr(na))
                    fi = 0
                } else {
                    fi = ix.nexts[fi - 1]
                }
            }
            return n
        default: return v
        }
    }

    // MARK: 진입

    // 정본: 준비제네릭기본정리
    static func basicCleanup(_ input: J) -> J {
        let doc = Mono.lowerDocument(input)
        guard let stmtsJ = doc.field("statements") else { return doc }
        var cands: [BStr] = []
        var seen: Set<BStr> = []
        collectCandidates(stmtsJ, &cands, &seen)
        let ctx = Ctx(cands)
        let stmts = stmtsJ.arrayValue
        var traits: [J] = [], plain: [J] = [], genStructs: [J] = [], genFuncs: [J] = []
        for ls in stmts {
            let node = lineNode(ls)
            let k = astKind(node)
            let tp = astField(node, "type_params")
            let hasTP = tp.isArray && tp.arrayValue.count > 0
            if k == "TraitDef" {
                traits.append(ls)
            } else if k == "StructDef" && hasTP {
                genStructs.append(ls)
            } else if k == "FunctionDef" && hasTP {
                genFuncs.append(ls)
            } else if k == "FunctionDef" && functionBase(node, genStructs) != "" {
                genFuncs.append(ls)
            } else {
                plain.append(ls)
            }
        }
        var specStructs: [J] = []
        for c in 0..<cands.count {
            let u = ctx.unpacked[c]
            for gs in genStructs {
                if u.count > 0 && astStrField(lineNode(gs), "name") == u[0] {
                    specStructs.append(specializeStruct(gs, u))
                    break
                }
            }
        }
        var specFuncs: [J] = []
        for gf in genFuncs {
            let fn = lineNode(gf)
            let base = functionBase(fn, genStructs)
            if base != "" {
                for c in 0..<cands.count {
                    let u = ctx.unpacked[c]
                    if u.count > 0 && u[0] == base { specFuncs.append(specializeFunction(gf, u, base, genStructs)) }
                }
            }
        }
        let genFuncNames = genFuncs.map { astStrField(lineNode($0), "name") }
        var baseNames: [BStr] = [], baseTypes: [BStr] = []
        collectSymbols(.array(plain), ctx, &baseNames, &baseTypes)
        var req = Requests()
        plain = rewriteValue(.array(plain), 0, baseNames, baseTypes, ctx, genFuncs, genFuncNames, genStructs, &req).arrayValue
        var reached: [J] = []
        var specByName: [BStr: Int] = [:]
        for (i, f) in specFuncs.enumerated() {
            let n = astStrField(lineNode(f), "name")
            if specByName[n] == nil { specByName[n] = i }
        }
        var ri = 0
        while ri < req.names.count {
            if let fi = specByName[req.names[ri]] {
                var sn = baseNames, st = baseTypes
                collectSymbols(specFuncs[fi], ctx, &sn, &st)
                let line = req.lines[ri]
                var fnJ = rewriteValue(specFuncs[fi], line, sn, st, ctx, genFuncs, genFuncNames, genStructs, &req).arrayValue
                fnJ[0] = jobj(["integer"], [jstr(BStr(decimal: line))])
                reached.append(.array(fnJ))
            }
            ri += 1
        }
        specFuncs = reached
        var insertAt = 0
        for (i, ls) in plain.enumerated() {
            let k = astKind(lineNode(ls))
            if k == "StructDef" || k == "EnumDef" || k == "ExternalGlobal" { insertAt = i + 1 }
        }
        var result: [J] = traits
        for (i, ls) in plain.enumerated() {
            if i == insertAt { result.append(contentsOf: specStructs) }
            result.append(ls)
        }
        if insertAt == plain.count { result.append(contentsOf: specStructs) }
        result.append(contentsOf: specFuncs)
        let finalJ = J.array(result)
        var finalStructs: [J] = []
        collectStructDefs(finalJ, &finalStructs)
        var byName: [BStr: J] = [:]
        for s in finalStructs { let n = astStrField(s, "name"); if byName[n] == nil { byName[n] = s } }
        let defJ = resolveDeferredDefaults(finalJ, finalStructs, byName)
        var forced = defJ
        if specFuncs.count > 0 {
            var finalFuncs: [J] = []
            collectFunctionDefs(defJ, &finalFuncs)
            forced = coerceLiterals(defJ, makeLiteralIndex(finalFuncs))
        }
        // 준비특성문서검증은 제약 위반이면 멈출 뿐 문서를 바꾸지 않는다.
        return objReplace(doc, "statements", forced)
    }
}
