// 오라클 대조용 최소 JSON 파서와 의미 비교기. 객체 키 순서는 무시하고,
// 배열 순서·문자열·숫자 원문은 정확히 비교한다. 첫 차이의 경로를 돌려준다.

public indirect enum JV: Equatable {
    case null
    case bool(Bool)
    case number(String)
    case string([UInt8])
    case array([JV])
    case object([(String, JV)])

    public static func == (a: JV, b: JV) -> Bool { JSONCheck.firstDifference(a, b, "") == nil }
}

public enum JSONCheck {
    public struct ParseError: Error, CustomStringConvertible {
        public let offset: Int
        public let message: String
        public var description: String { "JSON 오류 @\(offset): \(message)" }
    }

    public static func parse(_ bytes: [UInt8]) throws -> JV {
        var p = Parser(a: bytes, i: 0)
        p.ws()
        let v = try p.value()
        p.ws()
        if p.i != bytes.count { throw ParseError(offset: p.i, message: "뒤에 남은 문자") }
        return v
    }

    struct Parser {
        let a: [UInt8]
        var i: Int

        mutating func ws() { while i < a.count && (a[i] == 32 || a[i] == 9 || a[i] == 10 || a[i] == 13) { i += 1 } }

        mutating func value() throws -> JV {
            guard i < a.count else { throw ParseError(offset: i, message: "값이 필요합니다") }
            switch a[i] {
            case 123:
                i += 1
                var kv: [(String, JV)] = []
                ws()
                if i < a.count && a[i] == 125 { i += 1; return .object(kv) }
                while true {
                    ws()
                    guard i < a.count, a[i] == 34 else { throw ParseError(offset: i, message: "키가 필요합니다") }
                    let k = try string()
                    ws()
                    guard i < a.count, a[i] == 58 else { throw ParseError(offset: i, message: ": 필요") }
                    i += 1
                    ws()
                    kv.append((String(decoding: k, as: UTF8.self), try value()))
                    ws()
                    if i < a.count && a[i] == 44 { i += 1; continue }
                    if i < a.count && a[i] == 125 { i += 1; return .object(kv) }
                    throw ParseError(offset: i, message: "객체가 닫히지 않았습니다")
                }
            case 91:
                i += 1
                var arr: [JV] = []
                ws()
                if i < a.count && a[i] == 93 { i += 1; return .array(arr) }
                while true {
                    ws()
                    arr.append(try value())
                    ws()
                    if i < a.count && a[i] == 44 { i += 1; continue }
                    if i < a.count && a[i] == 93 { i += 1; return .array(arr) }
                    throw ParseError(offset: i, message: "배열이 닫히지 않았습니다")
                }
            case 34:
                return .string(try string())
            case 116:
                if a.count - i >= 4 && Array(a[i..<(i + 4)]) == Array("true".utf8) { i += 4; return .bool(true) }
            case 102:
                if a.count - i >= 5 && Array(a[i..<(i + 5)]) == Array("false".utf8) { i += 5; return .bool(false) }
            case 110:
                if a.count - i >= 4 && Array(a[i..<(i + 4)]) == Array("null".utf8) { i += 4; return .null }
            default:
                let s = i
                while i < a.count && (a[i] == 45 || a[i] == 43 || a[i] == 46 || a[i] == 101 || a[i] == 69 || (a[i] >= 48 && a[i] <= 57)) { i += 1 }
                if i > s { return .number(String(decoding: a[s..<i], as: UTF8.self)) }
            }
            throw ParseError(offset: i, message: "알 수 없는 값")
        }

        mutating func string() throws -> [UInt8] {
            i += 1
            var out: [UInt8] = []
            while i < a.count {
                let c = a[i]
                if c == 34 { i += 1; return out }
                if c != 92 { out.append(c); i += 1; continue }
                guard i + 1 < a.count else { break }
                let e = a[i + 1]
                i += 2
                switch e {
                case 34: out.append(34)
                case 92: out.append(92)
                case 47: out.append(47)
                case 98: out.append(8)
                case 102: out.append(12)
                case 110: out.append(10)
                case 114: out.append(13)
                case 116: out.append(9)
                case 117:
                    func hex4() throws -> Int {
                        guard i + 4 <= a.count, let v = Int(String(decoding: a[i..<(i + 4)], as: UTF8.self), radix: 16) else {
                            throw ParseError(offset: i, message: "\\u")
                        }
                        i += 4
                        return v
                    }
                    var cp = try hex4()
                    if cp >= 0xD800 && cp <= 0xDBFF && i + 1 < a.count && a[i] == 92 && a[i + 1] == 117 {
                        i += 2
                        let lo = try hex4()
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
                    }
                    if let sc = Unicode.Scalar(cp) { out.append(contentsOf: Array(String(Character(sc)).utf8)) }
                    else { out.append(contentsOf: [0xEF, 0xBF, 0xBD]) }
                default: throw ParseError(offset: i, message: "이스케이프")
                }
            }
            throw ParseError(offset: i, message: "문자열이 닫히지 않았습니다")
        }
    }

    static func describe(_ v: JV) -> String {
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s): return "\"" + String(decoding: s, as: UTF8.self) + "\""
        case .array(let a): return "array(\(a.count))"
        case .object(let kv): return "object{" + kv.map { $0.0 }.joined(separator: ",") + "}"
        }
    }

    /// 첫 차이의 경로와 설명. 같으면 nil.
    public static func firstDifference(_ a: JV, _ b: JV, _ path: String) -> String? {
        switch (a, b) {
        case (.null, .null): return nil
        case (.bool(let x), .bool(let y)): return x == y ? nil : "\(path): \(x) != \(y)"
        case (.number(let x), .number(let y)): return x == y ? nil : "\(path): \(x) != \(y)"
        case (.string(let x), .string(let y)):
            return x == y ? nil : "\(path): \(describe(a)) != \(describe(b))"
        case (.array(let x), .array(let y)):
            for i in 0..<min(x.count, y.count) {
                if let d = firstDifference(x[i], y[i], "\(path)[\(i)]") { return d }
            }
            return x.count == y.count ? nil : "\(path): 배열 길이 \(x.count) != \(y.count)"
        case (.object(let x), .object(let y)):
            var dx: [String: JV] = [:]
            for (k, v) in x { dx[k] = v }
            var dy: [String: JV] = [:]
            for (k, v) in y { dy[k] = v }
            for (k, _) in x where dy[k] == nil { return "\(path).\(k): 오라클에 없음" }
            for (k, _) in y where dx[k] == nil { return "\(path).\(k): 씨앗에 없음" }
            for (k, v) in x {
                if let d = firstDifference(v, dy[k]!, "\(path).\(k)") { return d }
            }
            return nil
        default:
            return "\(path): \(describe(a)) != \(describe(b))"
        }
    }
}
