#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// HMJE 문자열은 바이트열이다. 자립 파서의 모든 문자열 연산(끝나는가, 부분, 길이)은
// UTF-8 바이트 단위이므로 Swift String의 정준 동치 비교 대신 바이트 비교를 쓴다.
// 리터럴은 정적 저장소를 가리켜 비교마다 할당하지 않는다.

public struct BStr: Hashable, ExpressibleByStringLiteral, CustomStringConvertible, Comparable {
    @usableFromInline enum Storage {
        case literal(UnsafeBufferPointer<UInt8>)
        case heap([UInt8])
    }
    @usableFromInline var storage: Storage

    public init(stringLiteral value: StaticString) {
        if value.hasPointerRepresentation {
            storage = .literal(UnsafeBufferPointer(start: value.utf8Start, count: value.utf8CodeUnitCount))
        } else {
            storage = .heap(value.withUTF8Buffer { Array($0) })
        }
    }
    public init(_ bytes: [UInt8]) { storage = .heap(bytes) }
    public init<S: Sequence>(bytes: S) where S.Element == UInt8 { storage = .heap(Array(bytes)) }
    public init(_ s: String) { storage = .heap(Array(s.utf8)) }

    @inlinable public func withBytes<R>(_ f: (UnsafeBufferPointer<UInt8>) -> R) -> R {
        switch storage {
        case .literal(let p): return f(p)
        case .heap(let a): return a.withUnsafeBufferPointer(f)
        }
    }

    public var bytes: [UInt8] {
        switch storage {
        case .literal(let p): return Array(p)
        case .heap(let a): return a
        }
    }

    @inlinable public var count: Int {
        switch storage {
        case .literal(let p): return p.count
        case .heap(let a): return a.count
        }
    }

    public var isEmpty: Bool { count == 0 }

    @inlinable public subscript(i: Int) -> UInt8 {
        switch storage {
        case .literal(let p): return p[i]
        case .heap(let a): return a[i]
        }
    }

    public static func == (l: BStr, r: BStr) -> Bool {
        l.withBytes { a in r.withBytes { b in
            a.count == b.count && (a.count == 0 || memcmp(a.baseAddress!, b.baseAddress!, a.count) == 0)
        } }
    }

    public static func < (l: BStr, r: BStr) -> Bool {
        l.withBytes { a in r.withBytes { b in a.lexicographicallyPrecedes(b) } }
    }

    public func hash(into h: inout Hasher) {
        withBytes { h.combine(bytes: UnsafeRawBufferPointer($0)) }
    }

    /// 문자열끝나는가
    public func hasSuffix(_ s: BStr) -> Bool {
        withBytes { a in s.withBytes { b in
            if b.count > a.count { return false }
            if b.count == 0 { return true }
            return memcmp(a.baseAddress! + (a.count - b.count), b.baseAddress!, b.count) == 0
        } }
    }

    /// 문자열시작하는가
    public func hasPrefix(_ s: BStr) -> Bool {
        withBytes { a in s.withBytes { b in
            if b.count > a.count { return false }
            if b.count == 0 { return true }
            return memcmp(a.baseAddress!, b.baseAddress!, b.count) == 0
        } }
    }

    /// 문자열부분(본문, 시작, 길이)
    public func sub(_ start: Int, _ len: Int) -> BStr {
        withBytes { a in
            let s = max(0, min(start, a.count))
            let e = max(s, min(s + max(0, len), a.count))
            return BStr(bytes: a[s..<e])
        }
    }

    /// 문자열찾기(본문, 찾을것)이 있는가
    public func contains(_ s: BStr) -> Bool {
        withBytes { a in s.withBytes { b in
            if b.count == 0 { return true }
            if b.count > a.count { return false }
            var i = 0
            while i + b.count <= a.count {
                if memcmp(a.baseAddress! + i, b.baseAddress!, b.count) == 0 { return true }
                i += 1
            }
            return false
        } }
    }

    /// 문자열나누기(본문, 구분자)
    public func split(_ sep: BStr) -> [BStr] {
        let a = bytes, b = sep.bytes
        var out: [BStr] = []
        if b.isEmpty { return [self] }
        var start = 0, i = 0
        while i + b.count <= a.count {
            if Array(a[i..<(i + b.count)]) == b {
                out.append(BStr(bytes: a[start..<i]))
                i += b.count
                start = i
            } else {
                i += 1
            }
        }
        out.append(BStr(bytes: a[start..<a.count]))
        return out
    }

    public static func + (l: BStr, r: BStr) -> BStr {
        var a = l.bytes
        r.withBytes { a.append(contentsOf: $0) }
        return BStr(a)
    }

    public var string: String { withBytes { String(decoding: $0, as: UTF8.self) } }
    public var description: String { string }
}


public extension BStr {
    init(decimal v: UInt64) { self.init(String(v)) }
    init(decimal v: Int) { self.init(String(v)) }
}
