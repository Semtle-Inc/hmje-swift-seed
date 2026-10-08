// 자립 컴파일러의 `JSON값`(library/Sources/기반/codec/json.hmje)에 대응하는 공통 값 타입.
// 준비·타입검사·HMIR 생성은 AST를 이 값으로 다루므로, 모든 이식 단계가 같은 타입을 쓴다.
//
// - 문자열은 바이트열(`BStr`)이다. 정본 문자열 연산이 전부 UTF-8 바이트 단위이기 때문이다.
// - 객체는 키 순서를 보존한다(`객체키들`/`객체값들` 병렬 배열과 같다). 중복 키도 허용한다.
// - 직렬화는 `JSON직렬화`와 바이트 단위로 같다: 공백 없음, 비ASCII는 UTF-8 그대로,
//   이스케이프는 `" \ \n \r \t \b \f`와 32 미만 바이트의 `\u00XX`(소문자 16진)뿐.

public indirect enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(BStr)
    case array([JSONValue])
    case object(keys: [BStr], values: [JSONValue])

    // MARK: 정본 접근자 (이름은 json.hmje의 공개 함수를 따른다)

    public var isNull: Bool { if case .null = self { return true }; return false }

    /// `JSON값객체필드(값, 키)` — 첫 번째로 일치하는 키의 값. 없으면 nil.
    public func field(_ key: BStr) -> JSONValue? {
        guard case .object(let ks, let vs) = self else { return nil }
        for i in 0..<ks.count where ks[i] == key { return vs[i] }
        return nil
    }

    public var arrayValue: [JSONValue] {
        if case .array(let a) = self { return a }
        return []
    }

    public var stringValue: BStr {
        if case .string(let s) = self { return s }
        return ""
    }

    public var boolValue: Bool {
        if case .bool(let b) = self { return b }
        return false
    }

    public var objectKeys: [BStr] {
        if case .object(let ks, _) = self { return ks }
        return []
    }

    public var objectValues: [JSONValue] {
        if case .object(_, let vs) = self { return vs }
        return []
    }

    /// `JSON객체필드교체(문서, 키, 값)` — 키가 있으면 첫 번째 것을 바꾸고, 없으면 끝에 붙인다.
    public func replacingField(_ key: BStr, with value: JSONValue) -> JSONValue {
        guard case .object(var ks, var vs) = self else { return self }
        for i in 0..<ks.count where ks[i] == key {
            vs[i] = value
            return .object(keys: ks, values: vs)
        }
        ks.append(key)
        vs.append(value)
        return .object(keys: ks, values: vs)
    }
}

// MARK: - 직렬화 (JSON값직렬화배열에추가 / JSON문자열이스케이프배열에추가)

public enum JSONWriter {
    public static func serialize(_ v: JSONValue) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(1 << 16)
        write(v, &out)
        return out
    }

    static let hex: [UInt8] = Array("0123456789abcdef".utf8)

    public static func writeString(_ s: BStr, _ out: inout [UInt8]) {
        out.append(34)
        s.withBytes { p in
            for b in p {
                switch b {
                case 34: out.append(92); out.append(34)
                case 92: out.append(92); out.append(92)
                case 10: out.append(92); out.append(110)
                case 13: out.append(92); out.append(114)
                case 9: out.append(92); out.append(116)
                case 8: out.append(92); out.append(98)
                case 12: out.append(92); out.append(102)
                case 0..<32:
                    out.append(92); out.append(117); out.append(48); out.append(48)
                    out.append(hex[Int(b >> 4)]); out.append(hex[Int(b & 15)])
                default: out.append(b)
                }
            }
        }
        out.append(34)
    }

    public static func write(_ v: JSONValue, _ out: inout [UInt8]) {
        switch v {
        case .null: out.append(contentsOf: Array("null".utf8))
        case .bool(let b): out.append(contentsOf: Array((b ? "true" : "false").utf8))
        case .number:
            // 컴파일러 AST는 숫자를 {"integer": "..."} 문자열로 싣는다. 숫자 노드가
            // 필요해지면 JSON숫자를배열에추가를 그대로 옮긴다.
            fatalError("JSONWriter: 숫자 직렬화는 아직 이식하지 않았다")
        case .string(let s): writeString(s, &out)
        case .array(let a):
            out.append(91)
            for (i, e) in a.enumerated() {
                if i > 0 { out.append(44) }
                write(e, &out)
            }
            out.append(93)
        case .object(let ks, let vs):
            precondition(ks.count == vs.count)
            out.append(123)
            for i in 0..<ks.count {
                if i > 0 { out.append(44) }
                writeString(ks[i], &out)
                out.append(58)
                write(vs[i], &out)
            }
            out.append(125)
        }
    }
}

// MARK: - 파싱 (오라클 JSON 읽기용; 표준 JSON)

public enum JSONReadError: Error { case syntax(Int) }

public struct JSONReader {
    let b: [UInt8]
    var i = 0

    public static func parse(_ bytes: [UInt8]) throws -> JSONValue {
        var r = JSONReader(b: bytes)
        r.ws()
        let v = try r.value()
        r.ws()
        guard r.i == r.b.count else { throw JSONReadError.syntax(r.i) }
        return v
    }

    mutating func ws() {
        while i < b.count, b[i] == 32 || b[i] == 10 || b[i] == 13 || b[i] == 9 { i += 1 }
    }

    mutating func lit(_ s: String) throws {
        for c in s.utf8 {
            guard i < b.count, b[i] == c else { throw JSONReadError.syntax(i) }
            i += 1
        }
    }

    mutating func value() throws -> JSONValue {
        guard i < b.count else { throw JSONReadError.syntax(i) }
        switch b[i] {
        case 110: try lit("null"); return .null
        case 116: try lit("true"); return .bool(true)
        case 102: try lit("false"); return .bool(false)
        case 34: return .string(try str())
        case 91:
            i += 1; ws()
            var a: [JSONValue] = []
            if i < b.count, b[i] == 93 { i += 1; return .array(a) }
            while true {
                ws(); a.append(try value()); ws()
                guard i < b.count else { throw JSONReadError.syntax(i) }
                if b[i] == 44 { i += 1; continue }
                if b[i] == 93 { i += 1; return .array(a) }
                throw JSONReadError.syntax(i)
            }
        case 123:
            i += 1; ws()
            var ks: [BStr] = [], vs: [JSONValue] = []
            if i < b.count, b[i] == 125 { i += 1; return .object(keys: ks, values: vs) }
            while true {
                ws(); ks.append(try str()); ws()
                guard i < b.count, b[i] == 58 else { throw JSONReadError.syntax(i) }
                i += 1; ws(); vs.append(try value()); ws()
                guard i < b.count else { throw JSONReadError.syntax(i) }
                if b[i] == 44 { i += 1; continue }
                if b[i] == 125 { i += 1; return .object(keys: ks, values: vs) }
                throw JSONReadError.syntax(i)
            }
        default:
            let s = i
            while i < b.count, "+-0123456789.eE".utf8.contains(b[i]) { i += 1 }
            guard i > s, let d = Double(String(decoding: b[s..<i], as: UTF8.self)) else { throw JSONReadError.syntax(s) }
            return .number(d)
        }
    }

    mutating func hex4() throws -> UInt32 {
        guard i + 4 <= b.count else { throw JSONReadError.syntax(i) }
        var v: UInt32 = 0
        for _ in 0..<4 {
            let c = b[i]; i += 1
            v <<= 4
            switch c {
            case 48...57: v |= UInt32(c - 48)
            case 97...102: v |= UInt32(c - 87)
            case 65...70: v |= UInt32(c - 55)
            default: throw JSONReadError.syntax(i)
            }
        }
        return v
    }

    mutating func str() throws -> BStr {
        guard i < b.count, b[i] == 34 else { throw JSONReadError.syntax(i) }
        i += 1
        var out: [UInt8] = []
        while true {
            guard i < b.count else { throw JSONReadError.syntax(i) }
            let c = b[i]; i += 1
            if c == 34 { return BStr(out) }
            if c != 92 { out.append(c); continue }
            guard i < b.count else { throw JSONReadError.syntax(i) }
            let e = b[i]; i += 1
            switch e {
            case 34: out.append(34)
            case 92: out.append(92)
            case 47: out.append(47)
            case 110: out.append(10)
            case 114: out.append(13)
            case 116: out.append(9)
            case 98: out.append(8)
            case 102: out.append(12)
            case 117:
                var cp = try hex4()
                if cp >= 0xD800 && cp < 0xDC00, i + 6 <= b.count, b[i] == 92, b[i + 1] == 117 {
                    i += 2
                    let lo = try hex4()
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                }
                appendUTF8(cp, &out)
            default: throw JSONReadError.syntax(i)
            }
        }
    }

    func appendUTF8(_ cp: UInt32, _ out: inout [UInt8]) {
        switch cp {
        case 0..<0x80: out.append(UInt8(cp))
        case 0x80..<0x800:
            out.append(UInt8(0xC0 | (cp >> 6))); out.append(UInt8(0x80 | (cp & 0x3F)))
        case 0x800..<0x10000:
            out.append(UInt8(0xE0 | (cp >> 12))); out.append(UInt8(0x80 | ((cp >> 6) & 0x3F))); out.append(UInt8(0x80 | (cp & 0x3F)))
        default:
            out.append(UInt8(0xF0 | (cp >> 18))); out.append(UInt8(0x80 | ((cp >> 12) & 0x3F)))
            out.append(UInt8(0x80 | ((cp >> 6) & 0x3F))); out.append(UInt8(0x80 | (cp & 0x3F)))
        }
    }
}
