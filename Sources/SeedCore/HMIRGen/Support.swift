// HMIR 생성 단계 공용 도구: 정본 문자열 연산(자연수64 의미), AST 접근자(AST/접근.hmje),
// 정본 공유 추가(문자열배열동적배열공유추가)의 별칭 의미를 그대로 옮긴 버퍼.

extension HMIRGenerator {

// MARK: - 문자열 (library 표준/string.hmje 의미)

/// 문자열부분(문구, 시작, 길이). 정본 인자는 자연수64라 음수 계산 결과는 순환해 거대한 값이 된다:
/// 시작이 음수면 빈 문자열, 길이가 음수면 끝까지.
@inline(__always)
func hSub(_ s: BStr, _ start: Int, _ len: Int) -> BStr {
    let n = s.count
    if start < 0 || start >= n { return "" }
    var l = len
    if l < 0 || l > n - start { l = n - start }
    if l == 0 { return "" }
    return s.withBytes { BStr(bytes: $0[start..<(start + l)]) }
}

/// 문자열찾기 — 첫 위치(빈 조각은 0)
func hFind(_ s: BStr, _ p: BStr) -> Int? {
    let n = s.count, m = p.count
    if m == 0 { return 0 }
    if m > n { return nil }
    return s.withBytes { a in p.withBytes { b in
        var i = 0
        let first = b[0]
        while i <= n - m {
            if a[i] == first {
                var k = 1
                while k < m && a[i + k] == b[k] { k += 1 }
                if k == m { return i }
            }
            i += 1
        }
        return nil
    } }
}

@inline(__always) func hHas(_ s: BStr, _ p: BStr) -> Bool { hFind(s, p) != nil }

/// 문자열다듬기 — 앞뒤 공백(스페이스·탭·CR·LF)
func hTrim(_ s: BStr) -> BStr {
    s.withBytes { a in
        var h = 0, t = a.count
        while h < t, a[h] == 32 || a[h] == 9 || a[h] == 13 || a[h] == 10 { h += 1 }
        while t > h, a[t - 1] == 32 || a[t - 1] == 9 || a[t - 1] == 13 || a[t - 1] == 10 { t -= 1 }
        if h == 0 && t == a.count { return s }
        return BStr(bytes: a[h..<t])
    }
}

@inline(__always) func hByte(_ s: BStr, _ i: Int) -> Int {
    if i < 0 || i >= s.count { return 0 }
    return Int(s[i])
}

/// 문자열붙인값 사슬
func hcat(_ parts: BStr...) -> BStr {
    var out: [UInt8] = []
    var total = 0
    for p in parts { total += p.count }
    out.reserveCapacity(total)
    for p in parts { p.withBytes { out.append(contentsOf: $0) } }
    return BStr(out)
}

func hDec(_ v: Int) -> BStr { BStr(String(v)) }
func hDecU(_ v: UInt64) -> BStr { BStr(String(v)) }

func hIsSpaceParse(_ b: UInt8) -> Bool { b == 32 || b == 9 || b == 13 }

/// 자연수64파싱
func hParseU64(_ s: BStr) -> UInt64? {
    let a = s.bytes
    var i = 0, e = a.count
    while i < e, hIsSpaceParse(a[i]) { i += 1 }
    while e > i, hIsSpaceParse(a[e - 1]) { e -= 1 }
    if i == e { return nil }
    var v: UInt64 = 0
    while i < e {
        let b = a[i]
        if b < 48 || b > 57 { return nil }
        let d = UInt64(b - 48)
        if v > 1844674407370955161 { return nil }
        if v == 1844674407370955161 && d > 5 { return nil }
        v = v * 10 + d
        i += 1
    }
    return v
}

/// 정수64파싱
func hParseI64(_ s: BStr) -> Int64? {
    let a = s.bytes
    var i = 0, e = a.count
    while i < e, hIsSpaceParse(a[i]) { i += 1 }
    while e > i, hIsSpaceParse(a[e - 1]) { e -= 1 }
    if i == e { return nil }
    var neg = false
    if a[i] == 45 { neg = true; i += 1 }
    if i == e { return nil }
    var m: UInt64 = 0
    while i < e {
        let b = a[i]
        if b < 48 || b > 57 { return nil }
        let d = UInt64(b - 48)
        if m > 922337203685477580 { return nil }
        if m == 922337203685477580 && d > 7 { return nil }
        m = m * 10 + d
        i += 1
    }
    var v = Int64(m)
    if neg { v = 0 &- v }
    return v
}

/// AST/조사.hmje 목적격조사
func hObjParticle(_ s: BStr) -> BStr {
    let n = s.count
    if n == 0 { return "를" }
    let last = Int(s[n - 1])
    if last < 128 {
        if last >= 48 && last <= 57 { return "를" }
        if last >= 65 && last <= 90 { return "을" }
        if last >= 97 && last <= 122 { return "을" }
        return "를"
    }
    if n >= 3 {
        let f = Int(s[n - 3])
        if f >= 224 && f < 240 {
            let sec = Int(s[n - 2])
            let code = (f - 224) * 4096 + (sec - 128) * 64 + (last - 128)
            if code >= 44032 && code <= 55203 {
                let d = code - 44032
                if d % 28 == 0 { return "를" }
                return "을"
            }
        }
    }
    return "을"
}

// MARK: - AST 접근 (AST/접근.hmje)

@inline(__always) func astObjField(_ v: J, _ name: BStr) -> J { v.field(name) ?? .null }
@inline(__always) func astFields(_ n: J) -> J { astObjField(n, "fields") }
@inline(__always) func astField(_ n: J, _ name: BStr) -> J { astObjField(astFields(n), name) }
@inline(__always) func astStr(_ v: J) -> BStr { if case .string(let s) = v { return s }; return "" }
@inline(__always) func astStrField(_ n: J, _ name: BStr) -> BStr { astStr(astField(n, name)) }
@inline(__always) func astBoolField(_ n: J, _ name: BStr) -> Bool { if case .bool(let b) = astField(n, name) { return b }; return false }
@inline(__always) func astKind(_ n: J) -> BStr { astStr(astObjField(n, "kind")) }
@inline(__always) func astTagStr(_ v: J, _ tag: BStr) -> BStr { astStr(astObjField(v, tag)) }
@inline(__always) func astIsNull(_ v: J) -> Bool { v.isNull }
@inline(__always) func jIsArray(_ v: J) -> Bool { if case .array = v { return true }; return false }
@inline(__always) func jIsObject(_ v: J) -> Bool { if case .object = v { return true }; return false }
/// JSON값배열길이
@inline(__always) func jLen(_ v: J) -> Int { if case .array(let a) = v { return a.count }; return 0 }
/// JSON값배열원소(값, i)! — 없으면 기본 JSON값(널)
@inline(__always) func jAt(_ v: J, _ i: Int) -> J {
    if case .array(let a) = v, i >= 0, i < a.count { return a[i] }
    return .null
}
/// JSON값배열원소(값, i)가 있는가
@inline(__always) func jHas(_ v: J, _ i: Int) -> Bool {
    if case .array(let a) = v, i >= 0, i < a.count { return true }
    return false
}
@inline(__always) func jStr(_ s: BStr) -> J { .string(s) }
@inline(__always) func jObj(_ ks: [BStr], _ vs: [J]) -> J { .object(keys: ks, values: vs) }
/// {"kind": k, "fields": {...}}
func jNode(_ kind: BStr, _ ks: [BStr], _ vs: [J]) -> J {
    .object(keys: ["kind", "fields"], values: [.string(kind), .object(keys: ks, values: vs)])
}

/// 타입검사/JSON도구.hmje JSON객체필드교체 — 일치하는 키는 **모두** 바꾸고, 없으면 끝에 붙인다.
func jReplaceAll(_ obj: J, _ name: BStr, _ v: J) -> J {
    var ks = obj.objectKeys
    var vs = obj.objectValues
    var found = false
    for i in 0..<ks.count where ks[i] == name { vs[i] = v; found = true }
    if !found { ks.append(name); vs.append(v) }
    return .object(keys: ks, values: vs)
}

/// JSON노드필드교체
func jNodeReplaceField(_ node: J, _ name: BStr, _ v: J) -> J {
    guard let f = node.field("fields") else { return node }
    return jReplaceAll(node, "fields", jReplaceAll(f, name, v))
}

/// JSON문자열필드값
func jStrFieldValue(_ obj: J, _ name: BStr) -> BStr {
    guard let v = obj.field(name) else { return "" }
    return astStr(v)
}

// MARK: - AST/객체속성.hmje, AST/모듈접근.hmje

func astObjectAttrField(_ call: BStr) -> BStr {
    switch call {
    case "객체ID": return "식별자"
    case "객체크기": return "크기"
    case "객체권한": return "권한"
    case "객체특징": return "특징"
    case "객체연결대상수": return "연결 대상 수"
    case "객체확장자종류": return "확장자 종류"
    case "객체이름": return "이름"
    case "객체형식": return "형식"
    default: return ""
    }
}

/// 정본: AST모듈정의허용
func astModuleDefAllowed(_ def: J, _ useFile: BStr, _ useOwner: BStr, _ direct: BStr) -> Bool {
    let declFile = astStrField(def, "source_path")
    if useFile == "" || useFile == declFile { return true }
    let visV = astField(def, "visibility")
    var vis = astStr(visV)
    if jIsObject(visV) { vis = astStr(astObjField(visV, "value")) }
    if vis == "file" || vis == "type" { return false }
    let declOwner = astStrField(def, "access_owner")
    if declOwner == "" { return true }
    if declOwner == useOwner { return true }
    let fileKey = hcat("\n@file:", declFile, "\n")
    if !hHas(direct, hcat("\n", declOwner, "\n")) {
        if !hHas(direct, fileKey) { return false }
    }
    if vis == "public" { return true }
    if vis == "project" && useOwner != "" {
        let u = useOwner.split("\t"), d = declOwner.split("\t")
        return u[0] == d[0]
    }
    return false
}

// MARK: - 정본 공유 추가의 별칭 의미

/// 표준 dynamic_array.hmje 동적배열추가후용량(원소 크기 검사는 이 규모에서 늘 통과)
@inline(__always) static func dynGrowCap(_ len: Int, _ cap: Int) -> Int {
    let need = len + 1
    if cap >= need { return cap }
    var n = need
    if cap > 0 { n = cap * 2 }
    if n < need { n = need }
    return n
}

/// 정본 문자열 배열 버퍼 하나(데이터 주소 하나). 상태는 (버퍼, 길이)를 들고,
/// 공유 추가는 용량이 남으면 이 버퍼의 `길이` 자리에 제자리로 쓴다 — 같은 버퍼를 보는
/// 다른 상태 사본이 그 칸을 본다(정본과 같은 별칭). 용량이 늘 때만 새 버퍼로 복사한다.
final class LineBuf {
    var items: [BStr] = []
    var cap: Int
    init(cap: Int) { self.cap = cap }
}

struct LineVec {
    var buf: LineBuf
    var len: Int
    static func empty() -> LineVec { LineVec(buf: LineBuf(cap: 0), len: 0) }

    /// 문자열배열동적배열공유추가
    mutating func sharedAppend(_ s: BStr) {
        let nc = HMIRGenerator.dynGrowCap(len, buf.cap)
        if nc != buf.cap {
            let nb = LineBuf(cap: nc)
            nb.items.reserveCapacity(nc)
            nb.items.append(contentsOf: buf.items[0..<len])
            buf = nb
        }
        if len < buf.items.count { buf.items[len] = s } else { buf.items.append(s) }
        len += 1
    }
    subscript(i: Int) -> BStr { buf.items[i] }
    var array: [BStr] { Array(buf.items[0..<len]) }
}

/// 심볼 이름·타입 병렬 배열 버퍼. 이름별 위치 색인으로 뒤에서부터 찾기를 대신한다.
final class SymBuf {
    var names: [BStr] = []
    var types: [BStr] = []
    var cap: Int
    var index: [BStr: [Int]] = [:]
    init(cap: Int) { self.cap = cap }

    func indexInsert(_ name: BStr, _ p: Int) {
        if var ps = index[name] {
            index[name] = nil
            if ps.isEmpty || ps[ps.count - 1] < p {
                ps.append(p)
            } else {
                var lo = 0, hi = ps.count
                while lo < hi { let m = (lo + hi) >> 1; if ps[m] < p { lo = m + 1 } else { hi = m } }
                ps.insert(p, at: lo)
            }
            index[name] = ps
        } else {
            index[name] = [p]
        }
    }

    func indexRemove(_ name: BStr, _ p: Int) {
        guard var ps = index[name] else { return }
        index[name] = nil
        if let k = ps.lastIndex(of: p) { ps.remove(at: k) }
        if !ps.isEmpty { index[name] = ps }
    }

    func write(_ p: Int, _ name: BStr, _ type: BStr) {
        if p < names.count {
            let old = names[p]
            if old != name {
                indexRemove(old, p)
                names[p] = name
                indexInsert(name, p)
            }
            types[p] = type
        } else {
            names.append(name)
            types.append(type)
            indexInsert(name, p)
        }
    }
}

struct SymTab {
    var buf: SymBuf
    var len: Int
    static func empty() -> SymTab { SymTab(buf: SymBuf(cap: 0), len: 0) }

    /// 일반 `추가한다`로 만든 새 배열(용량은 0에서 두 배씩)
    static func fresh(_ names: [BStr], _ types: [BStr]) -> SymTab {
        var cap = 0
        for i in 0..<names.count { cap = HMIRGenerator.dynGrowCap(i, cap) }
        let b = SymBuf(cap: cap)
        for i in 0..<names.count { b.write(i, names[i], types[i]) }
        return SymTab(buf: b, len: names.count)
    }

    /// HMIR심볼추가 = 두 배열에 공유 추가
    mutating func sharedAppend(_ name: BStr, _ type: BStr) {
        let nc = HMIRGenerator.dynGrowCap(len, buf.cap)
        if nc != buf.cap {
            let nb = SymBuf(cap: nc)
            nb.names.reserveCapacity(nc)
            nb.types.reserveCapacity(nc)
            for i in 0..<len { nb.write(i, buf.names[i], buf.types[i]) }
            buf = nb
        }
        buf.write(len, name, type)
        len += 1
    }

    /// HMIR심볼타입 — 뒤에서부터 첫 일치
    func lookup(_ name: BStr) -> BStr {
        guard let ps = buf.index[name] else { return "" }
        // 길이보다 작은 가장 큰 위치
        var lo = 0, hi = ps.count
        while lo < hi { let m = (lo + hi) >> 1; if ps[m] < len { lo = m + 1 } else { hi = m } }
        if lo == 0 { return "" }
        return buf.types[ps[lo - 1]]
    }

    @inline(__always) func name(_ i: Int) -> BStr { buf.names[i] }
    @inline(__always) func type(_ i: Int) -> BStr { buf.types[i] }
}

}
