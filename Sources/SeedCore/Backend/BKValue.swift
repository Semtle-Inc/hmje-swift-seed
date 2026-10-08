// 정본: LLVM/값낮추기.hmje

extension BKL {
    @inline(__always) func 새임시() -> BStr { st.임시번호 += 1; return tv(st.임시번호) }
    @inline(__always) func 줄(_ s: BStr) { st.출력줄들.append(s) }
    @inline(__always) func 값설정(_ k: BStr, _ v: BStr, _ t: BStr) { st.값값[k] = v; st.값내부들[k] = t }
    @inline(__always) func 값(_ k: BStr) -> BStr { st.값값.bkg(k) }
    @inline(__always) func 값내부(_ k: BStr) -> BStr { st.값내부들.bkg(k) }

    // 정본: 비교서술어
    func 비교서술어(_ 연산: BStr, _ 내부: BStr) -> BStr {
        let 무부호 = 내부.hasPrefix("u") || 내부 == "address" || 내부 == "char" || 내부 == "bool"
        if 연산 == "==" { return "eq" }
        if 연산 == "!=" { return "ne" }
        if 무부호 {
            if 연산 == ">" { return "ugt" }
            if 연산 == ">=" { return "uge" }
            if 연산 == "<" { return "ult" }
            return "ule"
        }
        if 연산 == ">" { return "sgt" }
        if 연산 == ">=" { return "sge" }
        if 연산 == "<" { return "slt" }
        return "sle"
    }

    // 정본: 형변환연산
    func 형변환연산(_ 원내부: BStr, _ 결내부: BStr) -> BStr {
        let 원LL = 스칼라LLVM타입(원내부)
        let 결LL = 스칼라LLVM타입(결내부)
        if 원LL == 결LL { return "" }
        let 원실수임 = 원LL == "float" || 원LL == "double"
        let 결실수임 = 결LL == "float" || 결LL == "double"
        if 원실수임 && 결실수임 {
            if 원LL == "double" { return "fptrunc" }
            return "fpext"
        }
        if 원실수임 { return 결내부.hasPrefix("i") ? "fptosi" : "fptoui" }
        if 결실수임 { return 원내부.hasPrefix("i") ? "sitofp" : "uitofp" }
        if !원LL.hasPrefix("i") || !결LL.hasPrefix("i") { return "?" }
        guard let 원비트 = parseU64(sub(원LL, 1, 원LL.count - 1)) else { return "?" }
        guard let 결비트 = parseU64(sub(결LL, 1, 결LL.count - 1)) else { return "?" }
        if 원비트 > 결비트 { return "trunc" }
        if 원내부.hasPrefix("i") { return "sext" }
        return "zext"
    }

    /// 자주 나오는 모양: 값이 목표 내부와 다르면 변환 줄을 내고 새 값을 돌려준다(유효성 무시형).
    /// 정본 패턴: `변환 = 형변환연산(a, b); 만약 길이 > 0 그리고 변환 != "?"이면 …`
    func 변환해내기(_ 값: BStr, _ 원: BStr, _ 목표: BStr) -> (BStr, Bool) {
        let 변환 = 형변환연산(원, 목표)
        if 변환.count > 0 && 변환 != "?" {
            let t = 새임시()
            줄(cat("  ", t, " = ", 변환, " ", 스칼라LLVM타입(원), " ", 값, " to ", 스칼라LLVM타입(목표)))
            return (t, true)
        }
        return (값, false)
    }

    // 정본: 값명령낮추기
    func 값명령낮추기(_ 낮결과: BStr, _ 낮타입표시: BStr, _ 낮몸통: BStr, _ 작업머리: BStr, _ 진입색인: Int) -> Bool {
        var 처리됨 = false
        var 논맞음 = false
        if !(낮결과.count > 0) { return false }
        let 결과내부 = 종류풀기(내부해석(낮타입표시))
        let 결과열쇠 = cat(작업머리, 낮결과)
        if 낮몸통.hasPrefix("상수값 ") {
            let 값리터럴 = trim(sub(낮몸통, 10, 낮몸통.count - 10))
            var 값표현: BStr = ""
            var 값됨 = false
            if 값리터럴 == "없음" {
                if LLVM등록선택값인가(결과내부) { 값표현 = "zeroinitializer"; 값됨 = true }
            } else if 결과내부 == "bool" {
                값표현 = 값리터럴 == "참" ? "1" : "0"
                값됨 = true
            } else {
                if 결과내부 == "f32" || 결과내부 == "f64" {
                    let 실표기 = 실수지수표기(값리터럴, 결과내부)
                    if 실표기.count > 0 { 값표현 = 실표기; 값됨 = true }
                } else {
                    if 결과내부.hasPrefix("u") || 결과내부.hasPrefix("i") || 결과내부 == "address" {
                        값표현 = 정수상수텍스트(값리터럴, 결과내부)
                        값됨 = true
                    }
                }
            }
            if !값됨 && 결과내부 == "text" {
                let 문이스케이프 = 리터럴이스케이프(값리터럴)
                if 문이스케이프.count > 0 {
                    let 문길이 = 리터럴길이(값리터럴)
                    var 저장길이 = 문길이
                    if 저장길이 == 0 { 저장길이 = 1 }
                    st.문자열번호 += 1
                    let 문전역 = cat("@str.", num(st.문자열번호))
                    st.전역줄들.append(cat(문전역, " = private unnamed_addr constant [", num(저장길이), " x i8] c\"", 문이스케이프, "\""))
                    let 문포인터 = 새임시(), 문주소 = 새임시(), 문값1 = 새임시(), 문값2 = 새임시(), 문값3 = 새임시(), 문값4 = 새임시()
                    let n = num(저장길이)
                    줄(cat("  ", 문포인터, " = getelementptr inbounds [", n, " x i8], [", n, " x i8]* ", 문전역, ", i64 0, i64 0"))
                    줄(cat("  ", 문주소, " = ptrtoint i8* ", 문포인터, " to i64"))
                    줄(cat("  ", 문값1, " = insertvalue { i64, i64, i64, i64 } undef, i64 ", 문주소, ", 0"))
                    줄(cat("  ", 문값2, " = insertvalue { i64, i64, i64, i64 } ", 문값1, ", i64 ", num(문길이), ", 1"))
                    줄(cat("  ", 문값3, " = insertvalue { i64, i64, i64, i64 } ", 문값2, ", i64 ", num(문길이), ", 2"))
                    줄(cat("  ", 문값4, " = insertvalue { i64, i64, i64, i64 } ", 문값3, ", i64 1, 3"))
                    값설정(결과열쇠, 문값4, "text")
                    처리됨 = true
                }
            }
            if !처리됨 && !값됨 && 결과내부 == "char" {
                let 자이스케이프 = 리터럴이스케이프(값리터럴)
                if 자이스케이프.count == 3 {
                    let 자십육 = sub(자이스케이프, 1, 2)
                    let 표: [UInt8] = Array("0123456789ABCDEF".utf8)
                    var 자값 = 0
                    for 자번 in 0..<16 where byteAt(자십육, 0) == 표[자번] { 자값 = 자번 * 16 }
                    for 자번 in 0..<16 where byteAt(자십육, 1) == 표[자번] { 자값 = 자값 + 자번 }
                    값설정(결과열쇠, num(자값), 결과내부)
                    처리됨 = true
                }
            }
            if !처리됨 && !값됨 && 값리터럴 != "없음" && 결과내부 != "text" && 결과내부 != "char" {
                if !결과내부.hasPrefix("f") {
                    값설정(결과열쇠, 값리터럴, 결과내부)
                    처리됨 = true
                }
            }
            if 값됨 {
                값설정(결과열쇠, 값표현, 결과내부)
                처리됨 = true
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("읽기 ") {
            처리됨 = 읽기낮추기(낮몸통, 결과내부, 결과열쇠, 작업머리)
        }
        if !처리됨 && 낮몸통.hasPrefix("배열값 [") {
            let 배속 = sub(낮몸통, 11, 낮몸통.count - 11 - 1)
            if let 배쉼자리 = fnd(결과내부, ",") {
                let 배원내부 = 종류풀기(sub(결과내부, 6, 배쉼자리 - 6))
                let 배원LL = 타입LLVM(배원내부)
                let 배전체LL = 타입LLVM(결과내부)
                let 배항목들 = commaSplit(배속)
                var 배누적: BStr = "undef"
                var 배유효 = true
                var 배번 = 0
                while 배번 < 배항목들.count {
                    let 배열쇠 = cat(작업머리, 배항목들[배번])
                    var 배값 = 값(배열쇠)
                    let 배값내부 = 값내부(배열쇠)
                    if 배값.count == 0 {
                        배유효 = false
                    } else {
                        if 배값내부 != 배원내부 {
                            let 배변환 = 형변환연산(배값내부, 배원내부)
                            if 배변환 == "?" {
                                배유효 = false
                            } else if 배변환.count > 0 {
                                let t = 새임시()
                                줄(cat("  ", t, " = ", 배변환, " ", 스칼라LLVM타입(배값내부), " ", 배값, " to ", 스칼라LLVM타입(배원내부)))
                                배값 = t
                            }
                        }
                        let 배다음 = 새임시()
                        줄(cat("  ", 배다음, " = insertvalue ", 배전체LL, " ", 배누적, ", ", 배원LL, " ", 배값, ", ", num(배번)))
                        배누적 = 배다음
                    }
                    배번 += 1
                }
                if 배유효 {
                    값설정(결과열쇠, 배누적, 결과내부)
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("구조체값 ") {
            let 굿몸 = sub(낮몸통, 13, 낮몸통.count - 13)
            if let 굿여는자리 = fnd(굿몸, "(") {
                let 굿이름 = sub(굿몸, 0, 굿여는자리)
                let 굿필드부 = sub(굿몸, 굿여는자리 + 1, 굿몸.count - (굿여는자리 + 1) - 1)
                let 굿정의 = 구조체들.bkg(굿이름)
                if 굿정의.count > 0 {
                    let 굿제공들 = commaSplit(굿필드부)
                    var 굿제공이름들: [BStr] = []
                    var 굿제공참조들: [BStr] = []
                    for 굿쌍 in 굿제공들 {
                        if let 굿콜자리 = fnd(굿쌍, ": ") {
                            굿제공이름들.append(sub(굿쌍, 0, 굿콜자리))
                            굿제공참조들.append(trim(sub(굿쌍, 굿콜자리 + 2, 굿쌍.count - (굿콜자리 + 2))))
                        }
                    }
                    let 굿전체LL = 타입LLVM(결과내부)
                    let 굿필드들 = 세미나누기(굿정의)
                    var 굿누적: BStr = "undef"
                    var 굿유효 = true
                    var 굿번 = 0
                    while 굿번 < 굿필드들.count {
                        let 굿필드 = 굿필드들[굿번]
                        let 굿필콜자리 = fnd(굿필드, ":") ?? 0
                        let 굿필이름 = sub(굿필드, 0, 굿필콜자리)
                        let 굿필원내부 = sub(굿필드, 굿필콜자리 + 1, 굿필드.count - (굿필콜자리 + 1))
                        let 굿필내부 = 종류풀기(굿필원내부)
                        var 굿필참조: BStr = ""
                        for i in 0..<굿제공이름들.count where 굿제공이름들[i] == 굿필이름 { 굿필참조 = 굿제공참조들[i] }
                        let 굿값열쇠 = cat(작업머리, 굿필참조)
                        var 굿필값 = 값(굿값열쇠)
                        let 굿필값내부 = 값내부(굿값열쇠)
                        if 굿필값.count == 0 {
                            굿유효 = false
                        } else {
                            if 굿필값내부 != 굿필내부 {
                                let 굿변환 = 형변환연산(굿필값내부, 굿필내부)
                                if 굿변환 == "?" {
                                    굿유효 = false
                                } else if 굿변환.count > 0 {
                                    let t = 새임시()
                                    줄(cat("  ", t, " = ", 굿변환, " ", 스칼라LLVM타입(굿필값내부), " ", 굿필값, " to ", 스칼라LLVM타입(굿필내부)))
                                    굿필값 = t
                                }
                            }
                            if 굿유효 {
                                let 굿다음 = 새임시()
                                줄(cat("  ", 굿다음, " = insertvalue ", 굿전체LL, " ", 굿누적, ", ", 타입LLVM(굿필내부), " ", 굿필값, ", ", num(굿번)))
                                굿누적 = 굿다음
                            }
                        }
                        굿번 += 1
                    }
                    if 굿유효 {
                        값설정(결과열쇠, 굿누적, 결과내부)
                        처리됨 = true
                    }
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("문자열구성 ") {
            let 굼인자들 = commaSplit(sub(낮몸통, 16, 낮몸통.count - 16))
            if 굼인자들.count == 4 {
                var 굼유효 = true
                var 굼네값: [BStr] = []
                for 굼번 in 0..<4 {
                    let 굼열쇠 = cat(작업머리, 굼인자들[굼번])
                    var 굼값 = 값(굼열쇠)
                    let 굼값내부 = 값내부(굼열쇠)
                    if 굼값.count == 0 {
                        굼유효 = false
                    } else {
                        let 굼변환 = 형변환연산(굼값내부, "u64")
                        if 굼변환 == "?" {
                            굼유효 = false
                        } else if 굼변환.count > 0 {
                            let t = 새임시()
                            줄(cat("  ", t, " = ", 굼변환, " ", 스칼라LLVM타입(굼값내부), " ", 굼값, " to i64"))
                            굼값 = t
                        }
                    }
                    굼네값.append(굼값)
                }
                if 굼유효 {
                    let 굼LL = 타입LLVM(결과내부)
                    let 굼값1 = 새임시(), 굼값2 = 새임시(), 굼값3 = 새임시(), 굼값4 = 새임시()
                    줄(cat("  ", 굼값1, " = insertvalue ", 굼LL, " undef, i64 ", 굼네값[0], ", 0"))
                    줄(cat("  ", 굼값2, " = insertvalue ", 굼LL, " ", 굼값1, ", i64 ", 굼네값[1], ", 1"))
                    줄(cat("  ", 굼값3, " = insertvalue ", 굼LL, " ", 굼값2, ", i64 ", 굼네값[2], ", 2"))
                    줄(cat("  ", 굼값4, " = insertvalue ", 굼LL, " ", 굼값3, ", i64 ", 굼네값[3], ", 3"))
                    값설정(결과열쇠, 굼값4, 결과내부)
                    처리됨 = true
                }
            }
        }
        if !처리됨 {
            for 머리 in ["빠른반정밀도풀기 ", "빠른곱더하기32 ", "빠른F16실수32내적8배수 ", "빠른반정밀도접기 ", "포트읽기 ", "포인터읽기 ", "비트반전 "] as [BStr] where 낮몸통.hasPrefix(머리) {
                fatalError("미이식: 값명령낮추기 \(머리)")
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("원자교환64 ") {
            let 교인자들 = commaSplit(sub(낮몸통, 15, 낮몸통.count - 15))
            if 교인자들.count == 2 {
                let 교주값 = 값(cat(작업머리, 교인자들[0]))
                let 교값 = 값(cat(작업머리, 교인자들[1]))
                if 교주값.count > 0 && 교값.count > 0 {
                    let 교포인터 = 새임시(), 교결과 = 새임시()
                    줄(cat("  ", 교포인터, " = inttoptr i64 ", 교주값, " to i64*"))
                    줄(cat("  ", 교결과, " = atomicrmw xchg i64* ", 교포인터, ", i64 ", 교값, " seq_cst"))
                    값설정(결과열쇠, 교결과, "u64")
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("원자읽기64 ") {
            let 읽참조 = trim(sub(낮몸통, 15, 낮몸통.count - 15))
            let 읽열쇠 = cat(작업머리, 읽참조)
            var 읽주소값 = 값(읽열쇠)
            let 읽주소내부 = 값내부(읽열쇠)
            if 읽주소값.count > 0 {
                if 읽주소내부 != "address" && 읽주소내부 != "u64" {
                    let 읽변환 = 형변환연산(읽주소내부, "address")
                    if 읽변환.count > 0 && 읽변환 != "?" {
                        let t = 새임시()
                        줄(cat("  ", t, " = ", 읽변환, " ", 스칼라LLVM타입(읽주소내부), " ", 읽주소값, " to i64"))
                        읽주소값 = t
                    }
                }
                let 읽포인터 = 새임시(), 읽결과 = 새임시()
                줄(cat("  ", 읽포인터, " = inttoptr i64 ", 읽주소값, " to i64*"))
                줄(cat("  ", 읽결과, " = load atomic i64, i64* ", 읽포인터, " seq_cst, align 8"))
                값설정(결과열쇠, 읽결과, "u64")
                처리됨 = true
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("원자더하기64 ") {
            let 더인자들 = commaSplit(sub(낮몸통, 18, 낮몸통.count - 18))
            if 더인자들.count == 2 {
                let 더주값 = 값(cat(작업머리, 더인자들[0]))
                let 더값 = 값(cat(작업머리, 더인자들[1]))
                if 더주값.count > 0 && 더값.count > 0 {
                    let 더포인터 = 새임시(), 더결과 = 새임시()
                    줄(cat("  ", 더포인터, " = inttoptr i64 ", 더주값, " to i64*"))
                    줄(cat("  ", 더결과, " = atomicrmw add i64* ", 더포인터, ", i64 ", 더값, " seq_cst"))
                    값설정(결과열쇠, 더결과, "u64")
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("인덱스읽기 ") {
            처리됨 = 인덱스읽기낮추기(낮몸통, 결과내부, 결과열쇠, 작업머리)
        }
        if !처리됨 && 낮몸통.hasPrefix("필드읽기 ") {
            let 필몸2 = trim(sub(낮몸통, 13, 낮몸통.count - 13))
            if let 필점자리 = fnd(필몸2, ".") {
                let 필기준 = sub(필몸2, 0, 필점자리)
                let 필이름2 = sub(필몸2, 필점자리 + 1, 필몸2.count - (필점자리 + 1))
                let 열201 = cat(작업머리, 필기준)
                let 필기값 = 값(열201)
                let 필기내부 = 값내부(열201)
                if 필기값.count > 0 {
                    var 필색인 = 999
                    var 필타입2: BStr = ""
                    if 필기내부 == "text" {
                        if 필이름2 == "주소" || 필이름2 == "데이터" { 필색인 = 0 }
                        if 필이름2 == "길이" { 필색인 = 1 }
                        if 필이름2 == "용량" { 필색인 = 2 }
                        if 필이름2 == "플래그" { 필색인 = 3 }
                        필타입2 = 결과내부
                    }
                    if 필기내부.hasPrefix("struct:") {
                        let 필구이름 = sub(필기내부, 7, 필기내부.count - 7)
                        let 필항목들 = 세미나누기(구조체들.bkg(필구이름))
                        var 필찾번 = 0
                        while 필찾번 < 필항목들.count {
                            let 필항목 = 필항목들[필찾번]
                            let 필항콜론자리 = fnd(필항목, ":") ?? 0
                            if sub(필항목, 0, 필항콜론자리) == 필이름2 {
                                필색인 = 필찾번
                                필타입2 = 종류풀기(sub(필항목, 필항콜론자리 + 1, 필항목.count - (필항콜론자리 + 1)))
                            }
                            필찾번 += 1
                        }
                    }
                    if 필색인 < 999 {
                        let 필기LL = 타입LLVM(필기내부)
                        var 필결과 = 새임시()
                        let 필결내부 = 필타입2
                        줄(cat("  ", 필결과, " = extractvalue ", 필기LL, " ", 필기값, ", ", num(필색인)))
                        (필결과, _) = 변환해내기(필결과, 필결내부, 결과내부)
                        값설정(결과열쇠, 필결과, 결과내부)
                        처리됨 = true
                    }
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("오프셋읽기 ") {
            let 옵인자들 = commaSplit(sub(낮몸통, 16, 낮몸통.count - 16))
            if 옵인자들.count == 2 {
                let 열203 = cat(작업머리, 옵인자들[0])
                var 옵주소값 = 값(열203)
                let 옵주소내부 = 값내부(열203)
                let 옵값내부 = 종류풀기(내부해석(옵인자들[1]))
                let 옵LL = 타입LLVM(옵값내부)
                if 옵주소값.count > 0 && 옵LL.count > 0 {
                    (옵주소값, _) = 변환해내기(옵주소값, 옵주소내부, "address")
                    let 옵포인터 = 새임시()
                    var 옵결과 = 새임시()
                    줄(cat("  ", 옵포인터, " = inttoptr i64 ", 옵주소값, " to ", 옵LL, "*"))
                    줄(cat("  ", 옵결과, " = load ", 옵LL, ", ", 옵LL, "* ", 옵포인터, ", align 1"))
                    (옵결과, _) = 변환해내기(옵결과, 옵값내부, 결과내부)
                    값설정(결과열쇠, 옵결과, 결과내부)
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("문자열바이트읽기 ") {
            let 바인자들 = commaSplit(sub(낮몸통, 25, 낮몸통.count - 25))
            if 바인자들.count == 2 {
                let 열206 = cat(작업머리, 바인자들[0])
                let 바문값 = 값(열206)
                let 열207 = cat(작업머리, 바인자들[1])
                var 바색값 = 값(열207)
                let 바색내부 = 값내부(열207)
                if 바문값.count > 0 && 바색값.count > 0 {
                    (바색값, _) = 변환해내기(바색값, 바색내부, "i64")
                    let 바기준 = 새임시(), 바영기반 = 새임시(), 바주소 = 새임시(), 바포인터 = 새임시()
                    var 바결과 = 새임시()
                    줄(cat("  ", 바기준, " = extractvalue { i64, i64, i64, i64 } ", 바문값, ", 0"))
                    줄(cat("  ", 바영기반, " = sub i64 ", 바색값, ", 1"))
                    줄(cat("  ", 바주소, " = add i64 ", 바기준, ", ", 바영기반))
                    줄(cat("  ", 바포인터, " = inttoptr i64 ", 바주소, " to i8*"))
                    줄(cat("  ", 바결과, " = load i8, i8* ", 바포인터, ", align 1"))
                    (바결과, _) = 변환해내기(바결과, "u8", 결과내부)
                    값설정(결과열쇠, 바결과, 결과내부)
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("비교 ") {
            let 비몸 = sub(낮몸통, 7, 낮몸통.count - 7)
            let 비공백자리 = fnd(비몸, " ") ?? 0
            let 비연산 = sub(비몸, 0, 비공백자리)
            let 비인자들 = commaSplit(sub(비몸, 비공백자리 + 1, 비몸.count - (비공백자리 + 1)))
            if 비인자들.count == 2 {
                let 열2 = cat(작업머리, 비인자들[0])
                let 비왼값 = 값(열2)
                let 비왼내부 = 값내부(열2)
                let 열3 = cat(작업머리, 비인자들[1])
                var 비오른값 = 값(열3)
                var 비오른내부 = 값내부(열3)
                if 비왼값.count > 0 && 비오른값.count > 0 {
                    if 스칼라LLVM타입(비왼내부).count == 0 || 스칼라LLVM타입(비오른내부).count == 0 {
                        fatalError("지원하지 않는 비교 타입: \(비왼내부) \(비연산) \(비오른내부)")
                    }
                    if 비왼내부.hasPrefix("f") {
                        var 바뀜 = false
                        (비오른값, 바뀜) = 변환해내기(비오른값, 비오른내부, 비왼내부)
                        if 바뀜 { 비오른내부 = 비왼내부 }
                        var 비실서술: BStr = "oeq"
                        if 비연산 == "!=" { 비실서술 = "one" }
                        if 비연산 == ">" { 비실서술 = "ogt" }
                        if 비연산 == ">=" { 비실서술 = "oge" }
                        if 비연산 == "<" { 비실서술 = "olt" }
                        if 비연산 == "<=" { 비실서술 = "ole" }
                        let 비실결과 = 새임시()
                        줄(cat("  ", 비실결과, " = fcmp ", 비실서술, " ", 스칼라LLVM타입(비왼내부), " ", 비왼값, ", ", 비오른값))
                        값설정(결과열쇠, 비실결과, "bool")
                        처리됨 = true
                    }
                    if !처리됨 && !비왼내부.hasPrefix("f") {
                        var 바뀜 = false
                        (비오른값, 바뀜) = 변환해내기(비오른값, 비오른내부, 비왼내부)
                        if 바뀜 { 비오른내부 = 비왼내부 }
                        let 비서술 = 비교서술어(비연산, 비왼내부)
                        let 비결과 = 새임시()
                        줄(cat("  ", 비결과, " = icmp ", 비서술, " ", 스칼라LLVM타입(비왼내부), " ", 비왼값, ", ", 비오른값))
                        값설정(결과열쇠, 비결과, "bool")
                        처리됨 = true
                    }
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("부정 ") {
            let 부참조 = trim(sub(낮몸통, 7, 낮몸통.count - 7))
            let 부값 = 값(cat(작업머리, 부참조))
            if 부값.count > 0 {
                let 부결과 = 새임시()
                줄(cat("  ", 부결과, " = xor i1 ", 부값, ", true"))
                값설정(결과열쇠, 부결과, "bool")
                처리됨 = true
            }
        }
        if 낮몸통.hasPrefix("논리곱 ") || 낮몸통.hasPrefix("논리합 ") { 논맞음 = true }
        if !처리됨 && 논맞음 {
            let 논연산줄 = sub(낮몸통, 0, 9)
            let 논인자들 = commaSplit(sub(낮몸통, 10, 낮몸통.count - 10))
            if 논인자들.count == 2 {
                let 논왼값 = 값(cat(작업머리, 논인자들[0]))
                let 논오른값 = 값(cat(작업머리, 논인자들[1]))
                if 논왼값.count > 0 && 논오른값.count > 0 {
                    let 논LLVM: BStr = 논연산줄 == "논리합" ? "or" : "and"
                    let 논결과 = 새임시()
                    줄(cat("  ", 논결과, " = ", 논LLVM, " i1 ", 논왼값, ", ", 논오른값))
                    값설정(결과열쇠, 논결과, "bool")
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("단항 - ") {
            let 단참조 = trim(sub(낮몸통, 9, 낮몸통.count - 9))
            let 단열쇠 = cat(작업머리, 단참조)
            var 단값 = 값(단열쇠)
            let 단내부 = 값내부(단열쇠)
            if 단값.count > 0 {
                var 단유효 = true
                if 단내부 != 결과내부 {
                    let 단변환 = 형변환연산(단내부, 결과내부)
                    if 단변환 == "?" { 단유효 = false }
                    else if 단변환.count > 0 {
                        let t = 새임시()
                        줄(cat("  ", t, " = ", 단변환, " ", 스칼라LLVM타입(단내부), " ", 단값, " to ", 스칼라LLVM타입(결과내부)))
                        단값 = t
                    }
                }
                if 단유효 {
                    let 단결과 = 새임시()
                    if 결과내부.hasPrefix("f") {
                        줄(cat("  ", 단결과, " = fsub ", 스칼라LLVM타입(결과내부), " 0.0, ", 단값))
                    } else {
                        줄(cat("  ", 단결과, " = sub ", 스칼라LLVM타입(결과내부), " 0, ", 단값))
                    }
                    값설정(결과열쇠, 단결과, 결과내부)
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("바이트뒤집기 ") {
            let 바뒤참조 = trim(sub(낮몸통, 19, 낮몸통.count - 19))
            let 바뒤원값 = 값(cat(작업머리, 바뒤참조))
            if 바뒤원값.count > 0 {
                var 바뒤바이트수 = 8
                if 결과내부 == "u8" || 결과내부 == "i8" { 바뒤바이트수 = 1 }
                if 결과내부 == "u16" || 결과내부 == "i16" { 바뒤바이트수 = 2 }
                if 결과내부 == "u32" || 결과내부 == "i32" { 바뒤바이트수 = 4 }
                var 바뒤작업내부 = 결과내부
                var 바뒤값 = 바뒤원값
                var 바뒤실수 = false
                if 결과내부 == "f32" { 바뒤바이트수 = 4; 바뒤작업내부 = "u32"; 바뒤실수 = true }
                else if 결과내부 == "f64" { 바뒤바이트수 = 8; 바뒤작업내부 = "u64"; 바뒤실수 = true }
                if 바뒤실수 {
                    바뒤값 = 새임시()
                    줄(cat("  ", 바뒤값, " = bitcast ", 스칼라LLVM타입(결과내부), " ", 바뒤원값, " to ", 스칼라LLVM타입(바뒤작업내부)))
                }
                var 바뒤누적 = 바뒤값
                if 바뒤바이트수 > 1 {
                    바뒤누적 = "0"
                    var 바뒤번 = 0
                    while 바뒤번 < 바뒤바이트수 {
                        let 바뒤옮김 = 새임시()
                        줄(cat("  ", 바뒤옮김, " = lshr ", 타입LLVM(바뒤작업내부), " ", 바뒤값, ", ", num(바뒤번 * 8)))
                        let 바뒤가림 = 새임시()
                        줄(cat("  ", 바뒤가림, " = and ", 타입LLVM(바뒤작업내부), " ", 바뒤옮김, ", 255"))
                        var 바뒤놓임 = 바뒤가림
                        let 바뒤목표이동 = (바뒤바이트수 - 1 - 바뒤번) * 8
                        if 바뒤목표이동 > 0 {
                            바뒤놓임 = 새임시()
                            줄(cat("  ", 바뒤놓임, " = shl ", 타입LLVM(바뒤작업내부), " ", 바뒤가림, ", ", num(바뒤목표이동)))
                        }
                        let 바뒤합 = 새임시()
                        줄(cat("  ", 바뒤합, " = or ", 타입LLVM(바뒤작업내부), " ", 바뒤누적, ", ", 바뒤놓임))
                        바뒤누적 = 바뒤합
                        바뒤번 += 1
                    }
                }
                if 바뒤실수 {
                    let r = 새임시()
                    줄(cat("  ", r, " = bitcast ", 스칼라LLVM타입(바뒤작업내부), " ", 바뒤누적, " to ", 스칼라LLVM타입(결과내부)))
                    바뒤누적 = r
                }
                값설정(결과열쇠, 바뒤누적, 결과내부)
                처리됨 = true
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("변환 ") {
            let 변인자들 = commaSplit(sub(낮몸통, 7, 낮몸통.count - 7))
            if 변인자들.count == 2 {
                let 열8 = cat(작업머리, 변인자들[0])
                var 변값 = 값(열8)
                let 변내부 = 값내부(열8)
                let 변목표 = 종류풀기(내부해석(변인자들[1]))
                if 변값.count > 0 {
                    let 변연산 = 형변환연산(변내부, 변목표)
                    if 변연산 != "?" {
                        if 변연산.count > 0 {
                            let t = 새임시()
                            줄(cat("  ", t, " = ", 변연산, " ", 스칼라LLVM타입(변내부), " ", 변값, " to ", 스칼라LLVM타입(변목표)))
                            변값 = t
                        }
                        값설정(결과열쇠, 변값, 변목표)
                        처리됨 = true
                    }
                }
            }
        }
        if !처리됨 { 처리됨 = 벡터값낮추기(낮몸통, 결과열쇠, 작업머리) }
        if !처리됨 { 처리됨 = 함수값생성낮추기(낮몸통, 결과내부, 결과열쇠) }
        if !처리됨 { 처리됨 = 간접호출낮추기(낮몸통, 결과내부, 결과열쇠, 작업머리, 진입색인) }
        if !처리됨 { 처리됨 = 함수값참조낮추기(낮몸통, 결과열쇠, 작업머리) }
        if !처리됨 { 처리됨 = 클로저생성낮추기(낮몸통, 결과내부, 결과열쇠, 작업머리, 진입색인) }
        let 함주머리: BStr = "함수주소값 "
        if !처리됨 && 낮몸통.hasPrefix(함주머리) {
            let 함주몸 = trim(sub(낮몸통, 함주머리.count, 낮몸통.count - 함주머리.count))
            if let 함주여는자리 = fnd(함주몸, "(") {
                let 함주이름 = sub(함주몸, 0, 함주여는자리)
                let 함주매개부 = sub(함주몸, 함주여는자리 + 1, 함주몸.count - (함주여는자리 + 2))
                let 함주매개표기들 = commaSplit(함주매개부)
                var 함주인자내부들: [BStr] = []
                var 함주인자직렬: BStr = ""
                var 함주LLVM인자: BStr = ""
                var 함주번 = 0
                for 표기 in 함주매개표기들 {
                    let 함주낱내부 = 내부해석(표기)
                    함주인자내부들.append(함주낱내부)
                    if 함주번 > 0 { 함주인자직렬 = cat(함주인자직렬, ","); 함주LLVM인자 = cat(함주LLVM인자, ", ") }
                    함주인자직렬 = cat(함주인자직렬, 함주낱내부)
                    함주LLVM인자 = cat(함주LLVM인자, 타입LLVM(함주낱내부))
                    함주번 += 1
                }
                let 함주반환내부 = 함수반환.bkg(cat(함주이름, "|", 함주인자직렬))
                if 함주반환내부.count > 0 {
                    var 함주반환LL = 타입LLVM(함주반환내부)
                    if ABI간접(함주반환내부) { 함주반환LL = "void" }
                    let 함주결과 = 새임시()
                    let 함주심볼 = 함수심볼(함주이름, 함주인자내부들)
                    줄(cat("  ", 함주결과, " = ptrtoint ", 함주반환LL, " (", 함주LLVM인자, ")* @", 함주심볼, " to i64"))
                    값설정(결과열쇠, 함주결과, "address")
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮몸통.hasPrefix("주소값 ") {
            let 주이름 = trim(sub(낮몸통, 10, 낮몸통.count - 10))
            let 주열쇠 = cat(작업머리, 주이름)
            var 주포인터 = st.환경포인터.bkg(주열쇠)
            var 주내부 = st.환경내부들.bkg(주열쇠)
            if 주포인터.count == 0 {
                if 전역타입[주이름] != nil {
                    주포인터 = 전역심볼이름(주이름)
                    주내부 = 전역타입.bkg(주이름)
                }
            }
            if 주포인터.count > 0 {
                let 주LL = 타입LLVM(주내부)
                let 주결과 = 새임시()
                줄(cat("  ", 주결과, " = ptrtoint ", 주LL, "* ", 주포인터, " to i64"))
                값설정(결과열쇠, 주결과, "address")
                처리됨 = true
            }
        }
        if !처리됨 {
            if let 산공백자리 = fnd(낮몸통, " ") {
                let 산이름 = sub(낮몸통, 0, 산공백자리)
                var 산LLVM: BStr = ""
                switch 산이름 {
                case "더하기": 산LLVM = "add"
                case "빼기": 산LLVM = "sub"
                case "곱하기": 산LLVM = "mul"
                case "비트곱": 산LLVM = "and"
                case "비트합": 산LLVM = "or"
                case "비트배타합": 산LLVM = "xor"
                case "왼쪽이동": 산LLVM = "shl"
                default: break
                }
                let 산무부호 = 결과내부.hasPrefix("u") || 결과내부 == "address"
                if 산이름 == "나누기" { 산LLVM = 산무부호 ? "udiv" : "sdiv" }
                if 산이름 == "나머지" { 산LLVM = 산무부호 ? "urem" : "srem" }
                if 산이름 == "오른쪽이동" { 산LLVM = 산무부호 ? "lshr" : "ashr" }
                if 결과내부.hasPrefix("f") {
                    if 산이름 == "더하기" { 산LLVM = "fadd" }
                    if 산이름 == "빼기" { 산LLVM = "fsub" }
                    if 산이름 == "곱하기" { 산LLVM = "fmul" }
                    if 산이름 == "나누기" { 산LLVM = "fdiv" }
                    switch 산이름 {
                    case "나머지", "비트곱", "비트합", "비트배타합", "왼쪽이동", "오른쪽이동": 산LLVM = ""
                    default: break
                    }
                }
                if 산LLVM.count > 0 {
                    let 산인자들 = commaSplit(sub(낮몸통, 산공백자리 + 1, 낮몸통.count - (산공백자리 + 1)))
                    if 산인자들.count == 2 {
                        let 열101 = cat(작업머리, 산인자들[0])
                        var 산왼값 = 값(열101)
                        let 산왼내부 = 값내부(열101)
                        let 열102 = cat(작업머리, 산인자들[1])
                        var 산오른값 = 값(열102)
                        let 산오른내부 = 값내부(열102)
                        if 산왼값.count > 0 && 산오른값.count > 0 {
                            (산왼값, _) = 변환해내기(산왼값, 산왼내부, 결과내부)
                            (산오른값, _) = 변환해내기(산오른값, 산오른내부, 결과내부)
                            let 산결과 = 새임시()
                            줄(cat("  ", 산결과, " = ", 산LLVM, " ", 스칼라LLVM타입(결과내부), " ", 산왼값, ", ", 산오른값))
                            값설정(결과열쇠, 산결과, 결과내부)
                            처리됨 = true
                        }
                    }
                }
            }
        }
        if !처리됨 { 처리됨 = 결과호출낮추기(낮몸통, 결과내부, 결과열쇠, 작업머리, 진입색인) }
        return 처리됨
    }

    // 정본: 값명령낮추기의 `읽기 ` 갈래
    func 읽기낮추기(_ 낮몸통: BStr, _ 결과내부: BStr, _ 결과열쇠: BStr, _ 작업머리: BStr) -> Bool {
        let 읽이름 = trim(sub(낮몸통, 7, 낮몸통.count - 7))
        var 독유효 = true
        let 독대상전체 = 읽이름
        let 독전길이 = 독대상전체.count
        var 독머리끝 = 독전길이
        for 독걸음 in 0..<독전길이 {
            let b = 독대상전체[독걸음]
            if (b == 46 || b == 91) && 독머리끝 == 독전길이 { 독머리끝 = 독걸음 }
        }
        let 독첫이름 = sub(독대상전체, 0, 독머리끝)
        let 독환경열쇠 = cat(작업머리, 독첫이름)
        var 독포인터 = st.환경포인터.bkg(독환경열쇠)
        var 독내부 = st.환경내부들.bkg(독환경열쇠)
        if 독포인터.count == 0 {
            if 전역타입[독첫이름] != nil {
                독포인터 = 전역심볼이름(독첫이름)
                독내부 = 종류풀기(전역타입.bkg(독첫이름))
            }
        }
        if 독포인터.count == 0 { 독유효 = false }
        var 독자리 = 독머리끝
        while 독유효 && 독자리 < 독전길이 {
            let 독갈바이트 = 독대상전체[독자리]
            if 독갈바이트 == 46 {
                var 독필끝 = 독자리 + 1
                while 독필끝 < 독전길이 {
                    let b = 독대상전체[독필끝]
                    if b == 46 || b == 91 { break }
                    독필끝 += 1
                }
                let 독필드명 = sub(독대상전체, 독자리 + 1, 독필끝 - (독자리 + 1))
                if !독내부.hasPrefix("struct:") {
                    독유효 = false
                } else {
                    let 독구이름 = sub(독내부, 7, 독내부.count - 7)
                    let 독구필드들 = 세미나누기(구조체들.bkg(독구이름))
                    var 독구색인 = 999
                    var 독구필내부: BStr = ""
                    var 독구번 = 0
                    for 독구항목 in 독구필드들 {
                        let 독구콜자리 = fnd(독구항목, ":") ?? 0
                        if sub(독구항목, 0, 독구콜자리) == 독필드명 {
                            독구색인 = 독구번
                            독구필내부 = sub(독구항목, 독구콜자리 + 1, 독구항목.count - (독구콜자리 + 1))
                        }
                        독구번 += 1
                    }
                    if 독구색인 == 999 {
                        독유효 = false
                    } else {
                        let 독구LL = 타입LLVM(독내부)
                        let 독구다음 = 새임시()
                        줄(cat("  ", 독구다음, " = getelementptr inbounds ", 독구LL, ", ", 독구LL, "* ", 독포인터, ", i64 0, i32 ", num(독구색인)))
                        독포인터 = 독구다음
                        독내부 = 독구필내부
                    }
                }
                독자리 = 독필끝
            } else if 독갈바이트 == 91 {
                var 독닫자리 = 독자리 + 1
                while 독닫자리 < 독전길이 && 독대상전체[독닫자리] != 93 { 독닫자리 += 1 }
                var 독색인표기 = trim(sub(독대상전체, 독자리 + 1, 독닫자리 - (독자리 + 1)))
                var 독순번임 = false
                if 독색인표기.hasPrefix("순번 ") {
                    독순번임 = true
                    독색인표기 = trim(sub(독색인표기, 7, 독색인표기.count - 7))
                }
                let 독색열쇠 = cat(작업머리, 독색인표기)
                var 독색값 = 값(독색열쇠)
                let 독색내부 = 값내부(독색열쇠)
                if 독색값.count == 0 || !독내부.hasPrefix("array<") {
                    독유효 = false
                } else {
                    let 독색변환 = 형변환연산(독색내부, "i64")
                    if 독색변환 == "?" {
                        독유효 = false
                    } else {
                        if 독색변환.count > 0 {
                            let t = 새임시()
                            줄(cat("  ", t, " = ", 독색변환, " ", 스칼라LLVM타입(독색내부), " ", 독색값, " to i64"))
                            독색값 = t
                        }
                        if 독순번임 {
                            let t = 새임시()
                            줄(cat("  ", t, " = sub i64 ", 독색값, ", 1"))
                            독색값 = t
                        }
                        let 독배LL = 타입LLVM(독내부)
                        let 독배쉼자리 = fnd(독내부, ",") ?? 0
                        let 독배원내부 = 종류풀기(sub(독내부, 6, 독배쉼자리 - 6))
                        let 독배다음 = 새임시()
                        줄(cat("  ", 독배다음, " = getelementptr inbounds ", 독배LL, ", ", 독배LL, "* ", 독포인터, ", i64 0, i64 ", 독색값))
                        독포인터 = 독배다음
                        독내부 = 독배원내부
                    }
                }
                독자리 = 독닫자리 + 1
            } else {
                독유효 = false
            }
        }
        if 독유효 {
            var 독전역보관 = false
            if 전역타입[읽이름] != nil {
                if 독내부.hasPrefix("array<") { 독전역보관 = true }
            }
            if 독전역보관 {
                값설정(결과열쇠, 독포인터, cat("ptr:", 독내부))
                return true
            }
            let 독LL = 타입LLVM(독내부)
            if 독LL.count > 0 {
                var 독값 = 새임시()
                var 독값내부 = 독내부
                줄(cat("  ", 독값, " = load ", 독LL, ", ", 독LL, "* ", 독포인터))
                if 독값내부 != 결과내부 {
                    let 독변환 = 형변환연산(독값내부, 결과내부)
                    if 독변환 != "?" {
                        if 독변환.count > 0 {
                            let t = 새임시()
                            줄(cat("  ", t, " = ", 독변환, " ", 스칼라LLVM타입(독값내부), " ", 독값, " to ", 스칼라LLVM타입(결과내부)))
                            독값 = t
                        }
                        독값내부 = 결과내부
                    }
                }
                값설정(결과열쇠, 독값, 독값내부)
                return true
            }
        }
        return false
    }

    // 정본: 값명령낮추기의 `인덱스읽기 ` 갈래
    func 인덱스읽기낮추기(_ 낮몸통: BStr, _ 결과내부: BStr, _ 결과열쇠: BStr, _ 작업머리: BStr) -> Bool {
        let 색몸 = sub(낮몸통, 16, 낮몸통.count - 16)
        guard let 색여는자리 = fnd(색몸, "[") else { return false }
        let 색닫는자리 = fnd(색몸, "]") ?? 0
        let 색기준참조 = sub(색몸, 0, 색여는자리)
        let 색색인참조 = sub(색몸, 색여는자리 + 1, 색닫는자리 - (색여는자리 + 1))
        let 색꼬리 = trim(sub(색몸, 색닫는자리 + 1, 색몸.count - (색닫는자리 + 1)))
        let 색순번임 = 색꼬리 == ", 순번"
        let 색기열쇠 = cat(작업머리, 색기준참조)
        let 색기값 = 값(색기열쇠)
        let 색기내부 = 값내부(색기열쇠)
        let 색색열쇠 = cat(작업머리, 색색인참조)
        var 색색값 = 값(색색열쇠)
        let 색색내부 = 값내부(색색열쇠)
        if !(색기값.count > 0 && 색색값.count > 0) { return false }
        var 색배내부 = 색기내부
        var 색포인터 = 색기값
        var 색값배열임 = false
        if 색기내부.hasPrefix("ptr:") { 색배내부 = sub(색기내부, 4, 색기내부.count - 4) } else { 색값배열임 = true }
        if !색배내부.hasPrefix("array<") { return false }
        if 색값배열임 {
            let 색배LL2 = 타입LLVM(색배내부)
            let 색슬롯 = 새임시()
            줄(cat("  ", 색슬롯, " = alloca ", 색배LL2))
            줄(cat("  store ", 색배LL2, " ", 색기값, ", ", 색배LL2, "* ", 색슬롯))
            색포인터 = 색슬롯
        }
        let 색변환2 = 형변환연산(색색내부, "i64")
        if 색변환2 == "?" { return false }
        if 색변환2.count > 0 {
            let t = 새임시()
            줄(cat("  ", t, " = ", 색변환2, " ", 스칼라LLVM타입(색색내부), " ", 색색값, " to i64"))
            색색값 = t
        }
        if 색순번임 {
            let t = 새임시()
            줄(cat("  ", t, " = sub i64 ", 색색값, ", 1"))
            색색값 = t
        }
        let 색배LL = 타입LLVM(색배내부)
        let 색쉼자리 = fnd(색배내부, ",") ?? 0
        let 색원내부 = 종류풀기(sub(색배내부, 6, 색쉼자리 - 6))
        let 색원포인터 = 새임시()
        줄(cat("  ", 색원포인터, " = getelementptr inbounds ", 색배LL, ", ", 색배LL, "* ", 색포인터, ", i64 0, i64 ", 색색값))
        if 색원내부.hasPrefix("array<") {
            if !색값배열임 {
                값설정(결과열쇠, 색원포인터, cat("ptr:", 색원내부))
                return true
            }
            return false
        }
        let 색원LL = 타입LLVM(색원내부)
        var 색결과 = 새임시()
        var 색결내부 = 색원내부
        줄(cat("  ", 색결과, " = load ", 색원LL, ", ", 색원LL, "* ", 색원포인터))
        if 색결내부 != 결과내부 {
            let 색변환3 = 형변환연산(색결내부, 결과내부)
            if 색변환3 != "?" {
                if 색변환3.count > 0 {
                    let t = 새임시()
                    줄(cat("  ", t, " = ", 색변환3, " ", 스칼라LLVM타입(색결내부), " ", 색결과, " to ", 스칼라LLVM타입(결과내부)))
                    색결과 = t
                }
                색결내부 = 결과내부
            }
        }
        값설정(결과열쇠, 색결과, 색결내부)
        return true
    }
}
