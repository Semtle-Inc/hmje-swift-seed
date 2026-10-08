#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation

// 준비 단계 공통 도우미. 정본의 AST/접근.hmje, 파싱모형.hmje, 타입검사/JSON도구.hmje,
// 표준 string.hmje 중 준비 단계가 쓰는 것들을 1:1로 옮긴다.

typealias J = JSONValue

// MARK: - JSON 생성 (파싱모형.hmje)

@inline(__always) func jstr(_ s: BStr) -> J { .string(s) }
@inline(__always) func jbool(_ b: Bool) -> J { .bool(b) }
@inline(__always) func jarr(_ a: [J]) -> J { .array(a) }
@inline(__always) func jobj(_ ks: [BStr], _ vs: [J]) -> J { .object(keys: ks, values: vs) }

/// 파싱AST노드
func astNode(_ kind: BStr, _ keys: [BStr], _ vals: [J]) -> J {
    jobj(["kind", "fields"], [jstr(kind), jobj(keys, vals)])
}
/// 파싱정수태그
func intTag(_ v: Int) -> J { jobj(["integer"], [jstr(BStr(decimal: v))]) }
/// 파싱줄문장
func lineStmt(_ line: Int, _ node: J) -> J { jarr([intTag(line), node]) }
/// 파싱열거값
func enumValue(_ kind: BStr, _ value: BStr) -> J { jobj(["enum", "value"], [jstr(kind), jstr(value)]) }

// MARK: - 접근 (AST/접근.hmje)

extension JSONValue {
    var isObject: Bool { if case .object = self { return true }; return false }
    var isArray: Bool { if case .array = self { return true }; return false }
    var isString: Bool { if case .string = self { return true }; return false }
}

/// AST객체필드
@inline(__always) func objField(_ v: J, _ name: BStr) -> J { v.field(name) ?? .null }
/// AST필드
@inline(__always) func astField(_ node: J, _ name: BStr) -> J { objField(objField(node, "fields"), name) }
/// AST문자열값
@inline(__always) func astStr(_ v: J) -> BStr { v.stringValue }
/// AST문자열필드
@inline(__always) func astStrField(_ node: J, _ name: BStr) -> BStr { astField(node, name).stringValue }
/// AST참거짓필드
@inline(__always) func astBoolField(_ node: J, _ name: BStr) -> Bool { astField(node, name).boolValue }
/// AST종류 (= 파싱AST종류)
@inline(__always) func astKind(_ node: J) -> BStr { objField(node, "kind").stringValue }
/// AST널인가
@inline(__always) func astIsNull(_ v: J) -> Bool { v.isNull }

/// 모듈줄문장노드
func lineNode(_ ls: J) -> J {
    if case .array(let a) = ls, a.count == 2 { return a[1] }
    return .null
}

/// JSON객체필드교체: 같은 키를 모두 바꾸고, 없으면 끝에 붙인다.
func objReplace(_ obj: J, _ name: BStr, _ value: J) -> J {
    let ks = obj.objectKeys, vs = obj.objectValues
    var nv: [J] = []
    nv.reserveCapacity(vs.count + 1)
    var found = false
    for i in 0..<ks.count {
        if ks[i] == name { nv.append(value); found = true } else { nv.append(vs[i]) }
    }
    var nk = ks
    if !found { nk.append(name); nv.append(value) }
    return .object(keys: nk, values: nv)
}

/// JSON노드필드교체
func nodeReplace(_ node: J, _ name: BStr, _ value: J) -> J {
    guard let fs = node.field("fields") else { return node }
    return objReplace(node, "fields", objReplace(fs, name, value))
}

// MARK: - 문자열 (표준 string.hmje)

extension BStr {
    /// 문자열찾기: 첫 위치 또는 nil
    func find(_ s: BStr) -> Int? {
        withBytes { a in s.withBytes { b in
            if b.count == 0 { return 0 }
            if b.count > a.count { return nil }
            var i = 0
            let last = a.count - b.count
            let first = b[0]
            while i <= last {
                if a[i] == first && memcmp(a.baseAddress! + i, b.baseAddress!, b.count) == 0 { return i }
                i += 1
            }
            return nil
        } }
    }

    /// 문자열나누기 (빠른 판)
    func splitFast(_ sep: BStr) -> [BStr] {
        withBytes { a in sep.withBytes { b in
            if b.count == 0 { return [self] }
            var out: [BStr] = []
            var start = 0, i = 0
            let first = b[0]
            while i + b.count <= a.count {
                if a[i] == first && (b.count == 1 || memcmp(a.baseAddress! + i, b.baseAddress!, b.count) == 0) {
                    out.append(BStr(bytes: UnsafeBufferPointer(rebasing: a[start..<i])))
                    i += b.count
                    start = i
                } else {
                    i += 1
                }
            }
            out.append(BStr(bytes: UnsafeBufferPointer(rebasing: a[start..<a.count])))
            return out
        } }
    }

    /// 문자열다듬기
    func trimmed() -> BStr {
        withBytes { a in
            var h = 0
            while h < a.count, a[h] == 32 || a[h] == 9 || a[h] == 13 || a[h] == 10 { h += 1 }
            var t = a.count
            while t > h, a[t - 1] == 32 || a[t - 1] == 9 || a[t - 1] == 13 || a[t - 1] == 10 { t -= 1 }
            return BStr(bytes: UnsafeBufferPointer(rebasing: a[h..<t]))
        }
    }
}

// MARK: - 파일 (AST/다리.hmje 타입AST파일전체읽기 등)

/// 적재 중에 만든 집계 파일. 정본은 표준 모듈 집계를 임시 디렉터리에 게시하고 다시
/// 읽는다. 씨앗은 같은 내용을 메모리에 두고, 경로만 가상 경로를 쓴다(내용·줄 수가
/// 같으면 문서가 같다 — 집계 경로 자체는 문서에 나오지 않는다).
final class PrepFS {
    var virtual: [BStr: BStr] = [:]
    var cache: [BStr: BStr] = [:]

    /// 타입AST파일전체읽기: 없거나 비면 "".
    func read(_ path: BStr) -> BStr {
        if let v = virtual[path] { return v }
        if let c = cache[path] { return c }
        var out = BStr("")
        if path.count > 0, let d = FileManager.default.contents(atPath: path.string) {
            out = BStr([UInt8](d))
        }
        cache[path] = out
        return out
    }
}

/// hmje_posix_realpath 기반 모듈실제경로/포직스절대경로: 실패하면 모듈경로정규화.
func realPathOrNormalize(_ path: BStr) -> BStr {
    if let r = realPathRaw(path) { return r }
    return normalizePath(path)
}

/// hmje_posix_realpath: 실패(빈 입력 포함) nil.
func realPathRaw(_ path: BStr) -> BStr? {
    if path.count == 0 || path.count >= 65536 { return nil }
    guard let r = realpath(path.string, nil) else { return nil }
    defer { free(r) }
    return BStr(String(cString: r))
}

/// 모듈경로정규화
func normalizePath(_ path: BStr) -> BStr {
    let absolute = path.hasPrefix("/")
    let parts = path.splitFast("/")
    var stack: [BStr] = []
    for p in parts {
        if p == "" || p == "." { continue }
        if p == ".." {
            if stack.count > 0 && stack[stack.count - 1] != ".." {
                stack.removeLast()
            } else if !absolute {
                stack.append(p)
            }
        } else {
            stack.append(p)
        }
    }
    var out: [UInt8] = absolute ? [47] : []
    for p in stack {
        if out.count > 0 && out.last! != 47 { out.append(47) }
        out.append(contentsOf: p.bytes)
    }
    return BStr(out)
}

/// 모듈부모경로
func parentPath(_ path: BStr) -> BStr {
    var last = path.count
    for i in 0..<path.count where path[i] == 47 { last = i }
    if last == path.count { return "" }
    if last == 0 { return "/" }
    return path.sub(0, last)
}

/// hmje_posix_list_hmje_sources 결과(모듈원본목록/포직스HMJE원본목록): 정렬된 .hmje 경로들.
func listHMJESources(_ path: BStr) -> [BStr] { listProjectPaths(path, sourceOnly: true) }

/// hmje_posix_list_project_files 결과(포직스프로젝트파일목록): 정렬된 일반 파일 경로들.
func listProjectFiles(_ path: BStr) -> [BStr] { listProjectPaths(path, sourceOnly: false) }

/// hmje_posix_list_project_paths: 심볼릭 링크를 만나면 실패(빈 목록).
private func listProjectPaths(_ path: BStr, sourceOnly: Bool) -> [BStr] {
    guard let root = realPathRaw(path) else { return [] }
    var items: [String] = []
    var st = stat()
    if lstat(root.string, &st) != 0 { return [] }
    if (st.st_mode & S_IFMT) == S_IFDIR {
        if !collectPaths(root.string, &items, sourceOnly) { return [] }
    } else if (st.st_mode & S_IFMT) == S_IFREG {
        if !sourceOnly || root.hasSuffix(".hmje") { items.append(root.string) }
    } else {
        return []
    }
    var bs = items.map { BStr($0) }
    bs.sort { a, b in a.withBytes { x in b.withBytes { y in strcmpBytes(x, y) < 0 } } }
    return bs
}

private func strcmpBytes(_ a: UnsafeBufferPointer<UInt8>, _ b: UnsafeBufferPointer<UInt8>) -> Int {
    let n = min(a.count, b.count)
    for i in 0..<n where a[i] != b[i] { return Int(a[i]) - Int(b[i]) }
    return a.count - b.count
}

private func collectPaths(_ dir: String, _ out: inout [String], _ sourceOnly: Bool) -> Bool {
    guard let stream = opendir(dir) else { return false }
    defer { closedir(stream) }
    while let ent = readdir(stream) {
        let name = withUnsafePointer(to: ent.pointee.d_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        if name == "." || name == ".." { continue }
        let p = dir + "/" + name
        var st = stat()
        if lstat(p, &st) != 0 { return false }
        let fmt = st.st_mode & S_IFMT
        if fmt == S_IFLNK { return false }
        if fmt == S_IFDIR {
            if !collectPaths(p, &out, sourceOnly) { return false }
        } else if fmt == S_IFREG && (!sourceOnly || Array(p.utf8.suffix(5)) == Array(".hmje".utf8)) {
            out.append(p)
        }
    }
    return true
}

func envVar(_ name: String) -> BStr? {
    guard let v = getenv(name) else { return nil }
    return BStr(String(cString: v))
}

// MARK: - 파서 AST → JSONValue

func jsonFromAST(_ v: ASTValue) -> J {
    switch v {
    case .null: return .null
    case .bool(let b): return .bool(b)
    case .str(let s): return .string(s)
    case .int(let s): return jobj(["integer"], [.string(s)])
    case .float(let s): return jobj(["float"], [.string(s)])
    case .enumTag(let k, let x): return jobj(["enum", "value"], [.string(BStr(k)), .string(BStr(x))])
    case .array(let a): return .array(a.map(jsonFromAST))
    case .object(let kv): return .object(keys: kv.map { $0.0 }, values: kv.map { jsonFromAST($0.1) })
    case .node(let n): return jsonFromNode(n)
    case .stmts(let s): return .array(s.map(jsonFromLine))
    }
}

func jsonFromNode(_ n: ASTNode) -> J {
    jobj(["kind", "fields"], [.string(BStr(n.kind.rawValue)),
        .object(keys: n.fields.map { BStr($0.0) }, values: n.fields.map { jsonFromAST($0.1) })])
}

func jsonFromLine(_ l: LineStmt) -> J { lineStmt(l.line, jsonFromNode(l.node)) }

func prepFail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}
