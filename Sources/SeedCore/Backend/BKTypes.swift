// 정본: LLVM/타입.hmje, LLVM/ABI.hmje, LLVM/이름맹글링.hmje

extension BKL {
    // 정본: 내부타입
    func 내부타입(_ 표기: BStr) -> BStr {
        switch 표기 {
        case "큰자연수", "자연수", "자연수64", "u64": return "u64"
        case "큰정수", "정수", "정수64", "i64": return "i64"
        case "주소", "원시주소", "address": return "address"
        case "문자열", "글": return "text"
        case "참거짓", "불리언", "불": return "bool"
        case "문자", "글자": return "char"
        case "작은자연수", "자연수8", "u8": return "u8"
        case "중간자연수", "자연수16", "u16": return "u16"
        case "자연수32", "u32": return "u32"
        case "작은정수", "정수8", "i8": return "i8"
        case "중간정수", "정수16", "i16": return "i16"
        case "정수32", "i32": return "i32"
        case "실수", "실수64", "float", "float64", "f64": return "f64"
        case "실수32", "float32", "f32": return "f32"
        case "void": return "void"
        default: return ""
        }
    }

    // 정본: 스칼라LLVM타입
    func 스칼라LLVM타입(_ 내부: BStr) -> BStr {
        switch 내부 {
        case "bool": return "i1"
        case "char", "u8", "i8": return "i8"
        case "u16", "i16": return "i16"
        case "u32", "i32": return "i32"
        case "u64", "i64", "address": return "i64"
        case "f32": return "float"
        case "f64": return "double"
        case "text": return "{ i64, i64, i64, i64 }"
        case "void": return "void"
        default: return ""
        }
    }

    // 정본: 동적배열접두
    func 동적배열접두(_ 원소내부: BStr) -> BStr {
        switch 원소내부 {
        case "u8": return "자연수8"
        case "u16": return "자연수16"
        case "u32": return "자연수32"
        case "u64": return "자연수64"
        case "i8": return "정수8"
        case "i16": return "정수16"
        case "i32": return "정수32"
        case "i64": return "정수64"
        case "f32": return "실수32"
        case "f64": return "실수64"
        case "char": return "문자"
        case "bool": return "참거짓"
        case "address": return "주소"
        case "text": return "문자열배열"
        default: break
        }
        if 원소내부.hasPrefix("struct:") {
            let 구조이름8 = sub(원소내부, 7, 원소내부.count - 7)
            let 꼬리: BStr = "동적배열형"
            if 구조이름8.hasSuffix(꼬리) {
                return cat(sub(구조이름8, 0, 구조이름8.count - 꼬리.count), "배열")
            }
            return 구조이름8
        }
        return ""
    }

    // 정본: 함수인자내부표기
    func 함수인자내부표기(_ 표기: BStr) -> BStr {
        var 남음 = trim(표기)
        var 결과: BStr = ""
        while 남음.count > 0 {
            let 와 = fnd(남음, "와 ")
            let 과 = fnd(남음, "과 ")
            var 나눔 = 남음.count
            if let w = 와 { 나눔 = w }
            if let g = 과 { if g < 나눔 { 나눔 = g } }
            var 조각 = 남음
            if 나눔 < 남음.count { 조각 = sub(남음, 0, 나눔) }
            if 결과.count > 0 { 결과 = cat(결과, ",") }
            결과 = cat(결과, 내부해석(trim(조각)))
            if 나눔 >= 남음.count {
                남음 = ""
            } else {
                let 다음 = 나눔 + 4 // 문자열바이트길이("와 ")
                남음 = sub(남음, 다음, 남음.count - 다음)
            }
        }
        return 결과
    }

    // 정본: 내부해석
    func 내부해석(_ 표기: BStr) -> BStr {
        if cacheOn {
            cacheCheck()
            if let v = c내부해석[표기] { return v }
            let v = 내부해석계산(표기)
            c내부해석[표기] = v
            return v
        }
        return 내부해석계산(표기)
    }

    func 내부해석계산(_ 표기: BStr) -> BStr {
        var 이미내부임 = 표기.hasPrefix("struct:")
        if 표기.hasPrefix("fn<") || 표기.hasPrefix("asyncfn<") || 표기.hasPrefix("array<") { 이미내부임 = true }
        if 이미내부임 { return 표기 }
        if 표기.hasSuffix("의 배열") {
            let 선배열원소 = sub(표기, 0, 표기.count - BStr("의 배열").count)
            let 선배열접두 = 구조체들.bkg(cat("dynamic-display:", 선배열원소))
            if 선배열접두.count > 0 { return cat("struct:", 선배열접두, "동적배열형") }
        }
        let 채널구조 = 구조체들.bkg(cat("channel:", 맹글이름(표기)))
        if 채널구조.count > 0 { return cat("struct:", 채널구조) }
        if 표기 == "아무것도 받지 않고 비동기로 반환하지 않음" { return "asyncfn<void|>" }
        if 표기 == "아무것도 받지 않고 반환하지 않음" { return "fn<void|>" }
        let 무인비동기머리: BStr = "아무것도 받지 않고 "
        let 비동기반환꼬리: BStr = " 비동기로 반환"
        if 표기.hasPrefix(무인비동기머리) && 표기.hasSuffix(비동기반환꼬리) {
            let 무인반표기 = sub(표기, 무인비동기머리.count, 표기.count - 무인비동기머리.count - 비동기반환꼬리.count)
            return cat("asyncfn<", 내부해석(무인반표기), "|>")
        }
        if 표기.hasPrefix(무인비동기머리) {
            var 무인동기꼬리: BStr = ""
            if 표기.hasSuffix("를 반환") { 무인동기꼬리 = "를 반환" }
            else if 표기.hasSuffix("을 반환") { 무인동기꼬리 = "을 반환" }
            if 무인동기꼬리.count > 0 {
                let 무인동기반환표기 = sub(표기, 무인비동기머리.count, 표기.count - 무인비동기머리.count - 무인동기꼬리.count)
                return cat("fn<", 내부해석(무인동기반환표기), "|>")
            }
        }
        let 받아를 = fnd(표기, "를 받아 ")
        let 받아을 = fnd(표기, "을 받아 ")
        var 받아자리 = 0
        var 받아표시: BStr = ""
        var 함수표기임 = false
        if let p = 받아를 { 받아자리 = p; 받아표시 = "를 받아 "; 함수표기임 = true }
        else if let p = 받아을 { 받아자리 = p; 받아표시 = "을 받아 "; 함수표기임 = true }
        if 함수표기임 {
            let 함인표기 = trim(sub(표기, 0, 받아자리))
            let 함뒤시작 = 받아자리 + 받아표시.count
            let 함뒤표기 = trim(sub(표기, 함뒤시작, 표기.count - 함뒤시작))
            let 공반함인내부 = 함수인자내부표기(함인표기)
            if 함뒤표기 == "반환하지 않음" { return cat("fn<void|", 공반함인내부, ">") }
            if 함뒤표기 == "비동기로 반환하지 않음" { return cat("asyncfn<void|", 공반함인내부, ">") }
            var 함반표기: BStr = ""
            var 함반유효함 = false
            var 를반환: BStr = "를 반환"
            var 을반환: BStr = "을 반환"
            var 비동기함수표기임 = false
            if 함뒤표기.hasSuffix("를 비동기로 반환") { 를반환 = "를 비동기로 반환"; 비동기함수표기임 = true }
            if 함뒤표기.hasSuffix("을 비동기로 반환") { 을반환 = "을 비동기로 반환"; 비동기함수표기임 = true }
            if 함뒤표기.hasSuffix(를반환) {
                함반표기 = trim(sub(함뒤표기, 0, 함뒤표기.count - 를반환.count)); 함반유효함 = true
            } else if 함뒤표기.hasSuffix(을반환) {
                함반표기 = trim(sub(함뒤표기, 0, 함뒤표기.count - 을반환.count)); 함반유효함 = true
            }
            if 함반유효함 {
                let 함인내부 = 함수인자내부표기(함인표기)
                let 함반내부 = 내부해석(함반표기)
                if 비동기함수표기임 { return cat("asyncfn<", 함반내부, "|", 함인내부, ">") }
                return cat("fn<", 함반내부, "|", 함인내부, ">")
            }
        }
        if 표기.hasPrefix("overlay_array:") { return "struct:버퍼뷰" }
        if 표기.hasPrefix("overlay:") { return "u64" }
        if 표기.hasSuffix("에 놓인 뷰") { return "u64" }
        if 표기.hasSuffix("?") {
            let 속표기9 = sub(표기, 0, 표기.count - 1)
            var 표기선택구: BStr = ""
            if 속표기9.hasSuffix("개의 고정배열") { 표기선택구 = 구조체들.bkg(속표기9) }
            if 표기선택구.count == 0 { 표기선택구 = 구조체들.bkg(cat("optional-display:", 속표기9)) }
            if 표기선택구.count > 0 { return cat("struct:", 표기선택구) }
            let 속내부9 = 내부해석(속표기9)
            let 등록선택구 = 구조체들.bkg(cat("optional:", 속내부9))
            if 등록선택구.count > 0 { return cat("struct:", 등록선택구) }
            var 선접두9: BStr = ""
            if 속내부9 == "text" { 선접두9 = "문자열" }
            else if 속내부9.hasPrefix("struct:") { 선접두9 = sub(속내부9, 7, 속내부9.count - 7) }
            else { 선접두9 = 동적배열접두(속내부9) }
            if 선접두9.count == 0 {
                if 속내부9.hasPrefix("fn<") { 선접두9 = 구조체들.bkg("optional-function") }
            }
            if 선접두9.count > 0 { return cat("struct:", 선접두9, "선택값") }
        }
        let 배열꼬리: BStr = "의 배열"
        if 표기.hasSuffix(배열꼬리) {
            let 원소몸 = sub(표기, 0, 표기.count - 배열꼬리.count)
            let 원소내부8 = 내부해석(원소몸)
            var 접두8 = 구조체들.bkg(cat("dynamic:", 원소내부8))
            if 접두8.count == 0 { 접두8 = 동적배열접두(원소내부8) }
            if 접두8.count == 0 {
                if 원소내부8.hasPrefix("fn<") { 접두8 = 구조체들.bkg("dynamic-function") }
            }
            if 접두8.count > 0 { return cat("struct:", 접두8, "동적배열형") }
        }
        let 고정꼬리: BStr = "개의 고정배열"
        if 표기.hasSuffix(고정꼬리) {
            let 몸길이 = 표기.count - 고정꼬리.count
            let 몸만 = sub(표기, 0, 몸길이)
            if let 공백자리9 = fnd(몸만, " ") {
                let 원소표기 = sub(몸만, 0, 공백자리9)
                let 개수표기 = trim(sub(몸만, 공백자리9 + 1, 몸길이 - (공백자리9 + 1)))
                let 원소내부 = 내부해석(원소표기)
                return cat("array<", 원소내부, ",", 개수표기, ">")
            }
        }
        let 별칭 = 내부타입(표기)
        if 별칭.count > 0 { return 별칭 }
        let 기반 = 종류기반.bkg(표기)
        if 기반.count > 0 { return cat("enum:", 표기) }
        return cat("struct:", 표기)
    }

    // 정본: 타입LLVM
    func 타입LLVM(_ 내부: BStr) -> BStr {
        if cacheOn {
            cacheCheck()
            if let v = c타입LLVM[내부] { return v }
            let v = 타입LLVM계산(내부)
            c타입LLVM[내부] = v
            return v
        }
        return 타입LLVM계산(내부)
    }

    func 타입LLVM계산(_ 내부: BStr) -> BStr {
        if 내부.hasPrefix("fn<") || 내부.hasPrefix("asyncfn<") { return "{ i64, i64, i64 }" }
        if 내부.hasPrefix("enum:") {
            let 종기반 = 구조체들.bkg(내부)
            if 종기반.count > 0 { return 타입LLVM(종기반) }
            return ""
        }
        if 내부.hasPrefix("array<") {
            let 속 = sub(내부, 6, 내부.count - 7)
            if let 쉼자리8 = fnd(속, ",") {
                let 원소부 = sub(속, 0, 쉼자리8)
                let 개수부 = sub(속, 쉼자리8 + 1, 속.count - (쉼자리8 + 1))
                let 원소LL8 = 타입LLVM(원소부)
                if 원소LL8.count > 0 { return cat("[", 개수부, " x ", 원소LL8, "]") }
            }
            return ""
        }
        let 스칼라 = 스칼라LLVM타입(내부)
        if 스칼라.count > 0 { return 스칼라 }
        if 내부.hasPrefix("struct:") {
            let 구이름 = sub(내부, 7, 내부.count - 7)
            let 필드직렬 = 구조체들.bkg(구이름)
            if 필드직렬.count == 0 { return "" }
            let 필드들 = 세미나누기(필드직렬)
            var parts: [BStr] = ["{ "]
            var 번 = 0
            for 필드 in 필드들 {
                if let 콜론자리 = fnd(필드, ":") {
                    let 필타입 = sub(필드, 콜론자리 + 1, 필드.count - (콜론자리 + 1))
                    let 필LLVM = 타입LLVM(필타입)
                    if 번 > 0 { parts.append(", ") }
                    parts.append(필LLVM)
                }
                번 += 1
            }
            parts.append(" }")
            return catArr(parts)
        }
        return ""
    }

    // 정본: 함수타입반환
    func 함수타입반환(_ 내부: BStr) -> BStr {
        if let 세로자리 = fnd(내부, "|") {
            var 함수안시작 = 3
            if 내부.hasPrefix("asyncfn<") { 함수안시작 = 8 }
            return sub(내부, 함수안시작, 세로자리 - 함수안시작)
        }
        return ""
    }

    // 정본: 함수타입인자들
    func 함수타입인자들(_ 내부: BStr) -> [BStr] {
        if let 세로자리2 = fnd(내부, "|") {
            let 인자부분2 = sub(내부, 세로자리2 + 1, 내부.count - (세로자리2 + 2))
            return commaSplit(인자부분2)
        }
        return []
    }

    // 정본: 종류풀기
    func 종류풀기(_ 내부: BStr) -> BStr {
        if 내부.hasPrefix("enum:") {
            let 기반 = 구조체들.bkg(내부)
            if 기반.count > 0 { return 기반 }
        }
        return 내부
    }

    // 정본: LLVM등록선택값인가
    func LLVM등록선택값인가(_ 내부: BStr) -> Bool {
        if !내부.hasPrefix("struct:") { return false }
        let 이름 = sub(내부, 7, 내부.count - 7)
        let 필드들 = 세미나누기(구조체들.bkg(이름))
        if 필드들.count != 2 { return false }
        if 필드들[0] != "있음:bool" || !필드들[1].hasPrefix("값:") { return false }
        let 머리길이 = BStr("값:").count
        let 속내부 = sub(필드들[1], 머리길이, 필드들[1].count - 머리길이)
        return 구조체들.bkg(cat("optional:", 속내부)) == 이름
    }

    // ── ABI ──

    // 정본: ABI정렬
    func ABI정렬(_ 내부: BStr) -> Int {
        switch 내부 {
        case "u8", "i8", "char", "bool": return 1
        case "u16", "i16": return 2
        case "u32", "i32", "f32": return 4
        default: break
        }
        if 내부.hasPrefix("struct:") {
            let 구이름7 = sub(내부, 7, 내부.count - 7)
            let 구필드7 = 세미나누기(구조체들.bkg(구이름7))
            var 최대정렬 = 1
            for 항목7 in 구필드7 {
                let 콜자리7 = fnd(항목7, ":") ?? 0
                let 필내부7 = sub(항목7, 콜자리7 + 1, 항목7.count - (콜자리7 + 1))
                let 필정렬7 = ABI정렬(필내부7)
                if 필정렬7 > 최대정렬 { 최대정렬 = 필정렬7 }
            }
            return 최대정렬
        }
        if 내부.hasPrefix("array<") {
            let 속7 = sub(내부, 6, 내부.count - 7)
            let 쉼자리7 = fnd(속7, ",") ?? 0
            return ABI정렬(sub(속7, 0, 쉼자리7))
        }
        return 8
    }

    // 정본: ABI크기
    func ABI크기(_ 내부: BStr) -> Int {
        if cacheOn {
            cacheCheck()
            if let v = cABI크기[내부] { return v }
            let v = ABI크기계산(내부)
            cABI크기[내부] = v
            return v
        }
        return ABI크기계산(내부)
    }

    func ABI크기계산(_ 내부: BStr) -> Int {
        if 내부.hasPrefix("fn<") { return 24 }
        switch 내부 {
        case "text": return 32
        case "u8", "i8", "char", "bool": return 1
        case "u16", "i16": return 2
        case "u32", "i32", "f32": return 4
        case "u64", "i64", "f64", "address": return 8
        default: break
        }
        if 내부.hasPrefix("struct:") {
            let 구이름6 = sub(내부, 7, 내부.count - 7)
            let 구정의6 = 구조체들.bkg(구이름6)
            if 구정의6.count == 0 { return 999999 }
            let 구필드6 = 세미나누기(구정의6)
            var 자리6 = 0
            var 정렬6 = 1
            for 항목6 in 구필드6 {
                let 콜자리6 = fnd(항목6, ":") ?? 0
                let 필내부6 = sub(항목6, 콜자리6 + 1, 항목6.count - (콜자리6 + 1))
                let 필정렬6 = ABI정렬(필내부6)
                if 필정렬6 > 정렬6 { 정렬6 = 필정렬6 }
                let 나머지6 = 자리6 % 필정렬6
                if 나머지6 > 0 { 자리6 = 자리6 + (필정렬6 - 나머지6) }
                자리6 = 자리6 &+ ABI크기(필내부6)
            }
            let 끝나머지6 = 자리6 % 정렬6
            if 끝나머지6 > 0 { 자리6 = 자리6 + (정렬6 - 끝나머지6) }
            return 자리6
        }
        if 내부.hasPrefix("array<") {
            let 속6 = sub(내부, 6, 내부.count - 7)
            let 쉼자리6 = fnd(속6, ",") ?? 0
            let 원소내부6 = sub(속6, 0, 쉼자리6)
            guard let 개수6 = parseU64(sub(속6, 쉼자리6 + 1, 속6.count - (쉼자리6 + 1))) else { return 999999 }
            let 원크기6 = ABI크기(원소내부6)
            let 원정렬6 = ABI정렬(원소내부6)
            var 낱6 = 원크기6
            let 낱나머지6 = 낱6 % 원정렬6
            if 낱나머지6 > 0 { 낱6 = 낱6 + (원정렬6 - 낱나머지6) }
            return 낱6 &* Int(truncatingIfNeeded: 개수6)
        }
        if 내부 == "void" { return 0 }
        return 999999
    }

    // 정본: ABI간접
    func ABI간접(_ 내부: BStr) -> Bool {
        if !내부.hasPrefix("struct:") && !내부.hasPrefix("array<") { return false }
        return ABI크기(내부) > 16
    }

    // 정본: ABI매개LLVM
    func ABI매개LLVM(_ 내부: BStr) -> BStr {
        let 매개LL = 타입LLVM(내부)
        if ABI간접(내부) { return cat(매개LL, "*") }
        return 매개LL
    }

    // ── 이름 맹글링 ──

    // 정본: 십육진문자열
    func 십육진문자열(_ 값: UInt64) -> BStr {
        if 값 == 0 { return "0" }
        return BStr(String(값, radix: 16))
    }

    // 정본: 맹글이름 (코드포인트읽기 포함)
    func 맹글이름(_ 이름: BStr) -> BStr {
        if let v = c맹글[이름] { return v }
        let v = 맹글이름계산(이름)
        c맹글[이름] = v
        return v
    }

    func 맹글이름계산(_ 이름: BStr) -> BStr {
        let 길이 = 이름.count
        if 길이 == 0 { return "_" }
        var out: [UInt8] = []
        var 위치 = 0
        var 첫 = true
        while 위치 < 길이 {
            let b0 = UInt64(byteAt(이름, 위치))
            var 코드: UInt64
            var 바이트수: Int
            if b0 < 128 { 코드 = b0; 바이트수 = 1 }
            else if b0 < 224 {
                코드 = ((b0 & 31) << 6) | (UInt64(byteAt(이름, 위치 + 1)) & 63); 바이트수 = 2
            } else if b0 < 240 {
                코드 = ((b0 & 15) << 12) | ((UInt64(byteAt(이름, 위치 + 1)) & 63) << 6) | (UInt64(byteAt(이름, 위치 + 2)) & 63); 바이트수 = 3
            } else {
                코드 = ((b0 & 7) << 18) | ((UInt64(byteAt(이름, 위치 + 1)) & 63) << 12) | ((UInt64(byteAt(이름, 위치 + 2)) & 63) << 6) | (UInt64(byteAt(이름, 위치 + 3)) & 63); 바이트수 = 4
            }
            if !첫 { out.append(95) }
            첫 = false
            if (코드 >= 48 && 코드 <= 57) || (코드 >= 65 && 코드 <= 90) || (코드 >= 97 && 코드 <= 122) || 코드 == 95 {
                out.append(byteAt(이름, 위치))
            } else {
                out.append(117) // u
                out.append(contentsOf: Array(String(코드, radix: 16).utf8))
            }
            위치 += 바이트수
        }
        return BStr(out)
    }

    // 정본: 전역심볼이름
    func 전역심볼이름(_ 이름: BStr) -> BStr {
        if 전역타입[cat("외부전역:", 이름)] != nil { return cat("@", 이름) }
        if 이름.hasPrefix("limine_") { return cat("@", 이름) }
        return cat("@hmje_global_", 맹글이름(이름))
    }
}
