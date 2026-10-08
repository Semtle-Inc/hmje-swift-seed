// 백엔드(hmir을llvm으로) 이식이 쓰는 문자열 도우미. 정본 표준 라이브러리
// (library/Sources/표준/string.hmje)의 바이트 단위 의미를 그대로 따른다.
// - 문자열부분(문, 시작, 길이): 시작 >= 길이면 "", 길이가 자연수64 순환(음수)이면 끝까지.
// - 문자열찾기: 첫 위치, 빈 조각은 0.
// - 문자열나누기: 파이썬 방식(연속 구분자 = 빈 항목).
// - 문자열다듬기: 앞뒤 스페이스·탭·CR·LF.

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension BKL {
    @inline(__always) func bkIsWS(_ b: UInt8) -> Bool { b == 32 || b == 9 || b == 13 || b == 10 }

    /// 정본: 문자열찾기
    func fnd(_ s: BStr, _ p: BStr) -> Int? {
        s.withBytes { a in p.withBytes { b in
            let n = a.count, m = b.count
            if m == 0 { return 0 }
            if m > n { return nil }
            let first = b[0]
            var i = 0
            let last = n - m
            while i <= last {
                if a[i] == first && (m == 1 || memcmp(a.baseAddress! + i + 1, b.baseAddress! + 1, m - 1) == 0) { return i }
                i += 1
            }
            return nil
        } }
    }

    /// 정본: 문자열부분 (길이 음수 = 자연수64 순환 = 끝까지)
    func sub(_ s: BStr, _ start: Int, _ len: Int) -> BStr {
        s.withBytes { a in
            if start < 0 || start >= a.count { return BStr([]) }
            var l = len
            if l < 0 || l > a.count - start { l = a.count - start }
            if l == 0 { return BStr([]) }
            return BStr(Array(UnsafeBufferPointer(rebasing: a[start..<(start + l)])))
        }
    }

    /// 정본: 문자열다듬기
    func trim(_ s: BStr) -> BStr {
        s.withBytes { a in
            var h = 0, t = a.count
            while h < t && bkIsWS(a[h]) { h += 1 }
            while t > h && bkIsWS(a[t - 1]) { t -= 1 }
            if h == 0 && t == a.count { return s }
            return BStr(Array(UnsafeBufferPointer(rebasing: a[h..<t])))
        }
    }

    /// 정본: 문자열나누기
    func splitS(_ s: BStr, _ sep: BStr) -> [BStr] {
        s.withBytes { a in sep.withBytes { b in
            var out: [BStr] = []
            let m = b.count
            if m == 0 { return [s] }
            var start = 0, i = 0
            while i + m <= a.count {
                if memcmp(a.baseAddress! + i, b.baseAddress!, m) == 0 {
                    out.append(BStr(Array(UnsafeBufferPointer(rebasing: a[start..<i]))))
                    i += m
                    start = i
                } else { i += 1 }
            }
            out.append(BStr(Array(UnsafeBufferPointer(rebasing: a[start..<a.count]))))
            return out
        } }
    }

    /// 정본: 콤마나누기 (HMIR/파서.hmje) — 전체 다듬기 후 "," 분리, 조각 다듬기, 빈 조각 버림
    func commaSplit(_ s: BStr) -> [BStr] {
        let t = trim(s)
        if t.count == 0 { return [] }
        var out: [BStr] = []
        for p in splitS(t, ",") {
            let q = trim(p)
            if q.count > 0 { out.append(q) }
        }
        return out
    }

    /// 정본: 문자열바이트 (범위 밖은 0)
    @inline(__always) func byteAt(_ s: BStr, _ i: Int) -> UInt8 {
        if i < 0 || i >= s.count { return 0 }
        return s[i]
    }

    func cat(_ parts: BStr...) -> BStr {
        var total = 0
        for p in parts { total += p.count }
        var a: [UInt8] = []
        a.reserveCapacity(total)
        for p in parts { p.withBytes { a.append(contentsOf: $0) } }
        return BStr(a)
    }

    func catArr(_ parts: [BStr]) -> BStr {
        var total = 0
        for p in parts { total += p.count }
        var a: [UInt8] = []
        a.reserveCapacity(total)
        for p in parts { p.withBytes { a.append(contentsOf: $0) } }
        return BStr(a)
    }

    /// 정본: 문자열로만들기(자연수64/정수64)
    func num(_ v: Int) -> BStr { BStr(decimal: v) }
    func numU(_ v: UInt64) -> BStr { BStr(decimal: v) }

    /// "%t<n>"
    func tv(_ n: Int) -> BStr { cat("%t", num(n)) }

    /// 정본: 자연수64파싱 (앞뒤 스페이스/탭/CR 허용)
    func parseU64(_ s: BStr) -> UInt64? {
        let n = s.count
        var p = 0
        func ws(_ b: UInt8) -> Bool { b == 32 || b == 9 || b == 13 }
        while p < n && ws(s[p]) { p += 1 }
        var e = n
        while e > p && ws(s[e - 1]) { e -= 1 }
        if p == e { return nil }
        var v: UInt64 = 0
        while p < e {
            let b = s[p]
            if b < 48 || b > 57 { return nil }
            let d = UInt64(b - 48)
            if v > 1844674407370955161 { return nil }
            if v == 1844674407370955161 && d > 5 { return nil }
            v = v * 10 + d
            p += 1
        }
        return v
    }

    /// 정본: 정수64파싱
    func parseI64(_ s: BStr) -> Int64? {
        let n = s.count
        var p = 0
        func ws(_ b: UInt8) -> Bool { b == 32 || b == 9 || b == 13 }
        while p < n && ws(s[p]) { p += 1 }
        var e = n
        while e > p && ws(s[e - 1]) { e -= 1 }
        if p == e { return nil }
        var neg = false
        if s[p] == 45 { neg = true; p += 1 }
        if p == e { return nil }
        var v: UInt64 = 0
        while p < e {
            let b = s[p]
            if b < 48 || b > 57 { return nil }
            let d = UInt64(b - 48)
            if v > 922337203685477580 { return nil }
            if v == 922337203685477580 && d > 7 { return nil }
            v = v * 10 + d
            p += 1
        }
        var r = Int64(v)
        if neg { r = 0 &- r }
        return r
    }

}

extension Dictionary where Key == BStr, Value == BStr {
    @inline(__always) func bkg(_ k: BStr) -> BStr { self[k] ?? BStr([]) }
}
