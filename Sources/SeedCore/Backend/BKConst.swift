// 정본: LLVM/상수접기.hmje (+ HMIR/파서.hmje의 참조모으기·라벨이름)

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension BKL {
    // 정본: 세미나누기
    func 세미나누기(_ 텍스트: BStr) -> [BStr] {
        let t = trim(텍스트)
        if t.count == 0 { return [] }
        var out: [BStr] = []
        for p in splitS(t, ";") {
            let q = trim(p)
            if q.count > 0 { out.append(q) }
        }
        return out
    }

    // 정본: 참조모으기 (HMIR/파서.hmje)
    func 참조모으기(_ 텍스트: BStr) -> [BStr] {
        var 결과: [BStr] = []
        let 길이 = 텍스트.count
        var 위치 = 0
        while 위치 < 길이 {
            if 텍스트[위치] == 37 {
                var 끝 = 위치 + 1
                while 끝 < 길이 && 텍스트[끝] >= 48 && 텍스트[끝] <= 57 { 끝 += 1 }
                if 끝 > 위치 + 1 {
                    결과.append(sub(텍스트, 위치, 끝 - 위치))
                    위치 = 끝
                } else { 위치 += 1 }
            } else { 위치 += 1 }
        }
        return 결과
    }

    // 정본: 라벨이름 (HMIR/파서.hmje)
    func 라벨이름(_ 텍스트: BStr) -> BStr {
        var 몸 = trim(텍스트)
        if 몸.hasPrefix(".") { 몸 = sub(몸, 1, 몸.count - 1) }
        if 몸.hasSuffix(":") { 몸 = sub(몸, 0, 몸.count - 1) }
        return cat("hmir_", 맹글이름(몸))
    }

    // 정본: 정수상수텍스트
    func 정수상수텍스트(_ 리터럴: BStr, _ 내부: BStr) -> BStr {
        if 리터럴.hasPrefix("-") { return 리터럴 }
        guard let 값 = parseU64(리터럴) else { return 리터럴 }
        var 비트: UInt64 = 64
        if 내부 == "u8" || 내부 == "i8" || 내부 == "char" { 비트 = 8 }
        if 내부 == "u16" || 내부 == "i16" { 비트 = 16 }
        if 내부 == "u32" || 내부 == "i32" { 비트 = 32 }
        if 비트 == 64 {
            if 값 > 9223372036854775807 {
                let 반전 = 값 &- 9223372036854775808
                let 음수부 = 9223372036854775808 &- 반전
                return cat("-", numU(음수부))
            }
            return 리터럴
        }
        let 최대: UInt64 = (1 << (비트 - 1)) - 1
        if 값 > 최대 {
            let 전체: UInt64 = 1 << 비트
            return cat("-", numU(전체 &- 값))
        }
        return 리터럴
    }

    // 정본: 바이트16진
    func 바이트16진(_ 값: Int) -> BStr {
        let 표: [UInt8] = Array("0123456789ABCDEF".utf8)
        let hi = 값 >> 4, lo = 값 & 15
        var out: [UInt8] = []
        if hi < 16 { out.append(표[hi]) }
        out.append(표[lo])
        return BStr(out)
    }

    // 정본: 리터럴길이
    func 리터럴길이(_ 리터럴: BStr) -> Int {
        let 전체 = 리터럴.count
        if 전체 < 2 { return 999999999 }
        var 위치 = 1
        let 끝 = 전체 - 1
        var 개수 = 0
        while 위치 < 끝 {
            if byteAt(리터럴, 위치) == 92 { 위치 += 2 } else { 위치 += 1 }
            개수 += 1
        }
        return 개수
    }

    // 정본: 리터럴이스케이프
    func 리터럴이스케이프(_ 리터럴: BStr) -> BStr {
        let 전체 = 리터럴.count
        if 전체 < 2 { return "" }
        var 위치 = 1
        let 끝 = 전체 - 1
        var out: [UInt8] = []
        var 유효함 = true
        let 표: [UInt8] = Array("0123456789ABCDEF".utf8)
        while 위치 < 끝 {
            let 바이트 = Int(byteAt(리터럴, 위치))
            var 낼 = 바이트
            if 바이트 == 92 {
                let 다음 = Int(byteAt(리터럴, 위치 + 1))
                if 다음 == 110 { 낼 = 10 }
                else if 다음 == 116 { 낼 = 9 }
                else if 다음 == 114 { 낼 = 13 }
                else if 다음 == 48 { 낼 = 0 }
                else if 다음 == 92 || 다음 == 39 || 다음 == 34 { 낼 = 다음 }
                else { 유효함 = false }
                위치 += 2
            } else { 위치 += 1 }
            out.append(92); out.append(표[낼 >> 4]); out.append(표[낼 & 15])
        }
        if !유효함 { return "" }
        if out.isEmpty { return "\\00" }
        return BStr(out)
    }

    /// 정본 외부 함수 hmje_format_f64_literal_e16 (compiler/runtime/host_support.c)
    func 실수리터럴e16(_ 입력: BStr, _ 비트폭: Int) -> BStr? {
        if 입력.count == 0 || 입력.count >= 128 { return nil }
        var buf = 입력.bytes
        buf.append(0)
        var value: Double = 0
        var ok = false
        buf.withUnsafeMutableBufferPointer { p in
            let base = UnsafeMutableRawPointer(p.baseAddress!).assumingMemoryBound(to: CChar.self)
            var end: UnsafeMutablePointer<CChar>? = nil
            errno = 0
            value = strtod(base, &end)
            ok = (end == base + 입력.count) && errno != ERANGE
        }
        if !ok { return nil }
        if 비트폭 == 32 { value = Double(Float(value)) }
        return 포맷e16(value)
    }

    func 포맷e16(_ v: Double) -> BStr? {
        var out = [CChar](repeating: 0, count: 64)
        let n = withVaList([v]) { vsnprintf(&out, 64, "%.16e", $0) }
        if n < 0 || n >= 64 { return nil }
        return BStr(out[0..<Int(n)].map { UInt8(bitPattern: $0) })
    }

    /// 정본 외부 함수 hmje_format_float_binary_e16
    func 실수이항e16(_ 왼: BStr, _ 오른: BStr, _ 연산: Int, _ 비트폭: Int) -> BStr? {
        if 왼.count == 0 || 왼.count >= 128 || 오른.count == 0 || 오른.count >= 128 { return nil }
        func parse(_ s: BStr) -> Double? {
            var buf = s.bytes; buf.append(0)
            var v: Double = 0; var ok = false
            buf.withUnsafeMutableBufferPointer { p in
                let base = UnsafeMutableRawPointer(p.baseAddress!).assumingMemoryBound(to: CChar.self)
                var end: UnsafeMutablePointer<CChar>? = nil
                v = strtod(base, &end)
                ok = end == base + s.count
            }
            return ok ? v : nil
        }
        guard let l = parse(왼), let r = parse(오른) else { return nil }
        var result: Double
        if 비트폭 == 32 {
            let a = Float(l), b = Float(r)
            var value: Float
            if 연산 == 0 { value = a + b }
            else if 연산 == 1 { value = a - b }
            else if 연산 == 2 { value = a * b }
            else if 연산 == 3 && b != 0 { value = a / b }
            else { return nil }
            result = Double(value)
        } else if 비트폭 == 64 {
            if 연산 == 0 { result = l + r }
            else if 연산 == 1 { result = l - r }
            else if 연산 == 2 { result = l * r }
            else if 연산 == 3 && r != 0 { result = l / r }
            else { return nil }
        } else { return nil }
        return 포맷e16(result)
    }

    // 정본: 실수지수표기
    func 실수지수표기(_ 리터럴: BStr, _ 내부: BStr) -> BStr {
        var 실수비트폭 = 64
        if 내부 == "f32" { 실수비트폭 = 32 }
        if let s = 실수리터럴e16(리터럴, 실수비트폭), s.count > 0 { return s }
        // 정본의 이하 폴백 경로는 strtod가 실패한 리터럴에서만 닿는다.
        fatalError("미이식: 실수지수표기 폴백 (\(리터럴))")
    }

    // 정본: 전역문자열데이터모으기
    func 전역문자열데이터모으기(_ 뿌리들: [BStr]) -> [BStr] {
        var 대기 = 뿌리들
        var 방문: Set<BStr> = []
        var 데이터들: [BStr] = []
        var 번 = 0
        while 번 < 대기.count {
            let 참조 = 대기[번]
            번 += 1
            if 방문.contains(참조) { continue }
            방문.insert(참조)
            guard let 지표 = 결과색인[참조] else { continue }
            let 몸통 = 몸통들[지표]
            if 몸통.hasPrefix("상수값 ") {
                let 리터럴 = trim(sub(몸통, 10, 몸통.count - 10))
                if 리터럴.hasPrefix("'") || 리터럴.hasPrefix("\"") {
                    let 바이트들 = 리터럴이스케이프(리터럴)
                    if 바이트들.count > 0 {
                        var 길이 = 리터럴길이(리터럴)
                        if 길이 == 0 { 길이 = 1 }
                        데이터들.append(cat("@hmje.global.str.ref.", num(지표), " = private unnamed_addr constant [", num(길이), " x i8] c\"", 바이트들, "\""))
                    }
                }
            } else {
                대기.append(contentsOf: 참조모으기(몸통))
            }
        }
        return 데이터들
    }

    // 정본: 비트로읽기
    func 비트로읽기(_ 표기: BStr) -> UInt64 {
        if 표기.hasPrefix("-") {
            guard let a = parseU64(sub(표기, 1, 표기.count - 1)) else { return 0 }
            return 0 &- a
        }
        return parseU64(표기) ?? 0
    }

    // 정본: 비트로쓰기
    func 비트로쓰기(_ 비트: UInt64, _ 내부: BStr) -> BStr {
        var 폭: UInt64 = 64
        if 내부 == "u8" || 내부 == "i8" || 내부 == "char" { 폭 = 8 }
        if 내부 == "u16" || 내부 == "i16" { 폭 = 16 }
        if 내부 == "u32" || 내부 == "i32" { 폭 = 32 }
        if 폭 == 64 {
            if 비트 > 9223372036854775807 { return cat("-", numU(0 &- 비트)) }
            return numU(비트)
        }
        let 전체: UInt64 = 1 << 폭
        let 자른값 = 비트 & (전체 - 1)
        if 자른값 > (전체 >> 1) - 1 { return cat("-", numU(전체 - 자른값)) }
        return numU(자른값)
    }

    static let 상수접기0나눔: BStr = "!0나눔!"

    // 정본: 상수접기
    func 상수접기(_ 참조: BStr, _ 내부: BStr, _ 깊이: Int) -> BStr {
        let Z = BKL.상수접기0나눔
        if 깊이 > 32 { return "" }
        guard let 지표 = 결과색인[참조] else { return "" }
        let 몸통 = 몸통들[지표]
        if 몸통.hasPrefix("상수값 ") {
            let 리터럴 = trim(sub(몸통, 10, 몸통.count - 10))
            if 리터럴 == "없음" {
                if LLVM등록선택값인가(내부) { return "zeroinitializer" }
                return ""
            }
            if 내부 == "text" {
                if !리터럴.hasPrefix("'") && !리터럴.hasPrefix("\"") { return "" }
                if 리터럴이스케이프(리터럴).count == 0 { return "" }
                let 길이 = 리터럴길이(리터럴)
                return cat("{ i64 ptrtoint (ptr @hmje.global.str.ref.", num(지표), " to i64), i64 ", num(길이), ", i64 ", num(길이), ", i64 1 }")
            }
            if 내부 == "bool" { return 리터럴 == "참" ? "1" : "0" }
            if 내부.hasPrefix("f") { return 실수지수표기(리터럴, 내부) }
            return 정수상수텍스트(리터럴, 내부)
        }
        if 몸통.hasPrefix("변환 ") {
            let 변인자들2 = commaSplit(sub(몸통, 7, 몸통.count - 7))
            if 변인자들2.count == 2 {
                let 변목표2 = 종류풀기(내부해석(변인자들2[1]))
                return 상수접기(변인자들2[0], 변목표2, 깊이 + 1)
            }
            return ""
        }
        if 몸통.hasPrefix("단항 - ") {
            let 단참조2 = trim(sub(몸통, 9, 몸통.count - 9))
            let 단속 = 상수접기(단참조2, 내부, 깊이 + 1)
            if 단속 == Z { return Z }
            if 단속.count == 0 { return "" }
            if 내부.hasPrefix("f") {
                if 단속.hasPrefix("-") { return sub(단속, 1, 단속.count - 1) }
                return cat("-", 단속)
            }
            return 비트로쓰기(0 &- 비트로읽기(단속), 내부)
        }
        if 몸통.hasPrefix("비트반전 ") {
            let 반참조2 = trim(sub(몸통, 13, 몸통.count - 13))
            let 반속 = 상수접기(반참조2, 내부, 깊이 + 1)
            if 반속 == Z { return Z }
            if 반속.count == 0 { return "" }
            return 비트로쓰기(0 &- 비트로읽기(반속) &- 1, 내부)
        }
        if 몸통.hasPrefix("구조체값 ") {
            guard let 구여는자리 = fnd(몸통, "(") else { return "" }
            if !몸통.hasSuffix(")") { return "" }
            let 구이름 = trim(sub(몸통, 13, 구여는자리 - 13))
            let 구인자부 = sub(몸통, 구여는자리 + 1, 몸통.count - (구여는자리 + 2))
            if 구조체들[구이름] == nil { return "" }
            let 구필드조각들 = 세미나누기(구조체들.bkg(구이름))
            let 구제공들 = commaSplit(구인자부)
            var parts: [BStr] = ["{ "]
            var 구번 = 0
            while 구번 < 구필드조각들.count {
                let 구필조각 = 구필드조각들[구번]
                guard let 구필콜론자리 = fnd(구필조각, ":") else { return "" }
                let 구필이름 = sub(구필조각, 0, 구필콜론자리)
                let 구필내부 = sub(구필조각, 구필콜론자리 + 1, 구필조각.count - (구필콜론자리 + 1))
                var 구필참조: BStr = ""
                let 머리 = cat(구필이름, ": ")
                for 구제공 in 구제공들 {
                    if 구제공.hasPrefix(머리) {
                        let 구제머리길이 = 구필이름.count + 2
                        구필참조 = trim(sub(구제공, 구제머리길이, 구제공.count - 구제머리길이))
                    }
                }
                if 구필참조.count == 0 { return "" }
                let 구필LL = 타입LLVM(구필내부)
                if 구필LL.count == 0 { return "" }
                let 구필값 = 상수접기(구필참조, 종류풀기(구필내부), 깊이 + 1)
                if 구필값 == Z { return Z }
                if 구필값.count == 0 { return "" }
                if 구번 > 0 { parts.append(", ") }
                parts.append(cat(구필LL, " ", 구필값))
                구번 += 1
            }
            parts.append(" }")
            return catArr(parts)
        }
        if 몸통.hasPrefix("배열값 [") {
            if !내부.hasPrefix("array<") { return "" }
            guard let 배쉼자리 = fnd(내부, ",") else { return "" }
            let 배원내부 = sub(내부, 6, 배쉼자리 - 6)
            let 배길이표기 = sub(내부, 배쉼자리 + 1, 내부.count - (배쉼자리 + 2))
            guard let 배길이 = parseU64(배길이표기) else { return "" }
            let 배원LL = 타입LLVM(배원내부)
            if 배원LL.count == 0 { return "" }
            let 배참조들 = 참조모으기(몸통)
            if UInt64(배참조들.count) != 배길이 { return "" }
            var parts: [BStr] = ["["]
            var 배번 = 0
            for r in 배참조들 {
                let 배원값 = 상수접기(r, 배원내부, 깊이 + 1)
                if 배원값 == Z { return Z }
                if 배원값.count == 0 { return "" }
                if 배번 > 0 { parts.append(", ") }
                parts.append(cat(배원LL, " ", 배원값))
                배번 += 1
            }
            parts.append("]")
            return catArr(parts)
        }
        guard let 공백자리2 = fnd(몸통, " ") else { return "" }
        let 연산이름 = sub(몸통, 0, 공백자리2)
        var 이항인가 = false
        switch 연산이름 {
        case "더하기", "빼기", "곱하기", "나누기", "나머지", "비트곱", "비트합", "비트배타합", "왼쪽이동", "오른쪽이동": 이항인가 = true
        default: break
        }
        let 논리이항인가 = 연산이름 == "논리곱" || 연산이름 == "논리합"
        if 논리이항인가 {
            if 내부 != "bool" { return "" }
            이항인가 = true
        }
        if !이항인가 { return "" }
        let 이항인자들 = commaSplit(sub(몸통, 공백자리2 + 1, 몸통.count - (공백자리2 + 1)))
        if 이항인자들.count != 2 { return "" }
        let 왼속 = 상수접기(이항인자들[0], 내부, 깊이 + 1)
        let 오른속 = 상수접기(이항인자들[1], 내부, 깊이 + 1)
        if 왼속 == Z || 오른속 == Z { return Z }
        if 왼속.count == 0 || 오른속.count == 0 { return "" }
        if 논리이항인가 {
            if (왼속 != "0" && 왼속 != "1") || (오른속 != "0" && 오른속 != "1") { return "" }
            if 연산이름 == "논리곱" {
                if 왼속 == "1" && 오른속 == "1" { return "1" }
            } else {
                if 왼속 == "1" || 오른속 == "1" { return "1" }
            }
            return "0"
        }
        if 내부.hasPrefix("f") {
            var 실산번호 = 99
            if 연산이름 == "더하기" { 실산번호 = 0 }
            if 연산이름 == "빼기" { 실산번호 = 1 }
            if 연산이름 == "곱하기" { 실산번호 = 2 }
            if 연산이름 == "나누기" { 실산번호 = 3 }
            if 실산번호 > 3 { return "" }
            let 폭 = 내부 == "f32" ? 32 : 64
            if let s = 실수이항e16(왼속, 오른속, 실산번호, 폭), s.count > 0 { return s }
            return ""
        }
        let 왼비트 = 비트로읽기(왼속)
        let 오른비트 = 비트로읽기(오른속)
        let 무부호2 = 내부.hasPrefix("u") || 내부 == "address"
        switch 연산이름 {
        case "더하기": return 비트로쓰기(왼비트 &+ 오른비트, 내부)
        case "빼기": return 비트로쓰기(왼비트 &- 오른비트, 내부)
        case "곱하기": return 비트로쓰기(왼비트 &* 오른비트, 내부)
        case "비트곱": return 비트로쓰기(왼비트 & 오른비트, 내부)
        case "비트합": return 비트로쓰기(왼비트 | 오른비트, 내부)
        case "비트배타합": return 비트로쓰기(왼비트 ^ 오른비트, 내부)
        case "왼쪽이동": return 비트로쓰기(왼비트 &<< 오른비트, 내부)
        default: break
        }
        if 오른비트 == 0 {
            if 연산이름 == "나누기" || 연산이름 == "나머지" { return Z }
            return ""
        }
        if 무부호2 {
            if 연산이름 == "나누기" { return 비트로쓰기(왼비트 / 오른비트, 내부) }
            if 연산이름 == "나머지" { return 비트로쓰기(왼비트 % 오른비트, 내부) }
            if 연산이름 == "오른쪽이동" { return 비트로쓰기(왼비트 &>> 오른비트, 내부) }
        }
        var 왼음수 = false, 오른음수 = false
        var 왼크기 = 왼비트, 오른크기 = 오른비트
        if 왼비트 > 9223372036854775807 { 왼음수 = true; 왼크기 = 0 &- 왼비트 }
        if 오른비트 > 9223372036854775807 { 오른음수 = true; 오른크기 = 0 &- 오른비트 }
        if 연산이름 == "나누기" {
            var 몫 = 왼크기 / 오른크기
            if 왼음수 != 오른음수 { 몫 = 0 &- 몫 }
            return 비트로쓰기(몫, 내부)
        }
        if 연산이름 == "나머지" {
            var r = 왼크기 % 오른크기
            if 왼음수 { r = 0 &- r }
            return 비트로쓰기(r, 내부)
        }
        if 연산이름 == "오른쪽이동" {
            var 이동 = 왼비트 &>> 오른비트
            if 왼음수 && 오른비트 > 0 && 오른비트 < 64 { 이동 = 이동 | (UInt64.max << (64 - 오른비트)) }
            return 비트로쓰기(이동, 내부)
        }
        return ""
    }

    // 정본: 바이트이스케이프
    func 바이트이스케이프(_ 데이터: BStr) -> BStr {
        if 데이터.count == 0 { return "" }
        let 표: [UInt8] = Array("0123456789ABCDEF".utf8)
        var out: [UInt8] = []
        out.reserveCapacity(데이터.count * 3)
        데이터.withBytes { for b in $0 { out.append(92); out.append(표[Int(b >> 4)]); out.append(표[Int(b & 15)]) } }
        return BStr(out)
    }
}
