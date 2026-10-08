// 정본: LLVM/문장낮추기.hmje

extension BKL {
    /// 정본: 문장명령낮추기 → (처리됨, 종결됨)
    func 문장명령낮추기(_ 낮결과: BStr, _ 낮텍스트: BStr, _ 작업머리: BStr, _ 진입색인: Int, _ 종결입력: Bool) -> (Bool, Bool) {
        var 종결됨 = 종결입력
        var 처리됨 = false
        guard 낮결과.count == 0 else { return (false, 종결됨) }

        if 낮텍스트 == "CPU휴식" {
            줄(LLVM대상ARM인가 ? "  call void asm sideeffect \"yield\", \"~{memory}\"()" : "  call void asm sideeffect \"pause\", \"~{memory}\"()")
            처리됨 = true
        }
        if 낮텍스트 == "CPU대기" {
            줄(LLVM대상ARM인가 ? "  call void asm sideeffect \"wfi\", \"~{memory}\"()" : "  call void asm sideeffect \"hlt\", \"~{memory}\"()")
            처리됨 = true
        }
        let 지역정의인가 = 낮텍스트.hasPrefix("변수 ") || 낮텍스트.hasPrefix("상수 ")
        if 지역정의인가 {
            let 정몸 = sub(낮텍스트, 7, 낮텍스트.count - 7)
            if let 정콜론자리 = fnd(정몸, ": "), let 정등호자리 = fnd(정몸, " = ") {
                let 정이름 = sub(정몸, 0, 정콜론자리)
                let 정타입표기 = trim(sub(정몸, 정콜론자리 + 2, 정등호자리 - (정콜론자리 + 2)))
                let 정참조 = trim(sub(정몸, 정등호자리 + 3, 정몸.count - (정등호자리 + 3)))
                let 정내부 = 종류풀기(내부해석(정타입표기))
                let 열105 = cat(작업머리, 정참조)
                var 정값 = 값(열105)
                let 정값내부 = 값내부(열105)
                if 정값.count > 0 {
                    let 정LL = 타입LLVM(정내부)
                    if 정LL.count > 0 {
                        (정값, _) = 변환해내기(정값, 정값내부, 정내부)
                        let 정슬롯 = 새임시()
                        줄(cat("  ", 정슬롯, " = alloca ", 정LL))
                        줄(cat("  store ", 정LL, " ", 정값, ", ", 정LL, "* ", 정슬롯))
                        let 정열쇠 = cat(작업머리, 정이름)
                        st.환경포인터[정열쇠] = 정슬롯
                        st.환경내부들[정열쇠] = 정내부
                        처리됨 = true
                    }
                }
            }
        }
        if !처리됨 && 낮텍스트.hasPrefix("쓰기 ") {
            처리됨 = 쓰기낮추기(낮텍스트, 작업머리)
        }
        if !처리됨 && 낮텍스트 == "반환" {
            줄("  ret void")
            종결됨 = true
            처리됨 = true
        }
        if !처리됨 && 낮텍스트.hasPrefix("반환 ") {
            let 반몸 = sub(낮텍스트, 7, 낮텍스트.count - 7)
            if let 반콜론자리 = fnd(반몸, ": ") {
                let 반참조 = sub(반몸, 0, 반콜론자리)
                let 반타입표기 = trim(sub(반몸, 반콜론자리 + 2, 반몸.count - (반콜론자리 + 2)))
                let 반내부 = 종류풀기(내부해석(반타입표기))
                let 열109 = cat(작업머리, 반참조)
                var 반값 = 값(열109)
                let 반값내부 = 값내부(열109)
                if 반값.count > 0 {
                    (반값, _) = 변환해내기(반값, 반값내부, 반내부)
                    let 반LL = 타입LLVM(반내부)
                    if ABI간접(반내부) {
                        줄(cat("  store ", 반LL, " ", 반값, ", ", 반LL, "* %__hmje_return"))
                        줄("  ret void")
                    } else {
                        줄(cat("  ret ", 반LL, " ", 반값))
                    }
                    종결됨 = true
                    처리됨 = true
                }
            }
        }
        if !처리됨 { 처리됨 = 문장호출낮추기(낮텍스트, 작업머리, 진입색인) }
        if !처리됨 && 낮텍스트.hasPrefix("포트쓰기 ") {
            fatalError("미이식: 문장명령낮추기 포트쓰기")
        }
        if !처리됨 && 낮텍스트.hasPrefix("포인터쓰기 ") {
            let 포몸 = sub(낮텍스트, 16, 낮텍스트.count - 16)
            if 포몸.hasPrefix("포인터 ") {
                let 포포인자들 = commaSplit(sub(포몸, 10, 포몸.count - 10))
                if 포포인자들.count == 4 {
                    let 포포주값 = 값(cat(작업머리, 포포인자들[0]))
                    let 포포색값 = 값(cat(작업머리, 포포인자들[1]))
                    let 포포값내부 = 종류풀기(내부해석(포포인자들[2]))
                    let 포포값 = 값(cat(작업머리, 포포인자들[3]))
                    let 포포LL = 타입LLVM(포포값내부)
                    if 포포주값.count > 0 && 포포색값.count > 0 && 포포값.count > 0 && 포포LL.count > 0 {
                        let 포포영색 = 새임시(), 포포오프셋 = 새임시(), 포포주소 = 새임시(), 포포포인터 = 새임시()
                        줄(cat("  ", 포포영색, " = sub i64 ", 포포색값, ", 1"))
                        줄(cat("  ", 포포오프셋, " = mul i64 ", 포포영색, ", ", num(ABI크기(포포값내부))))
                        줄(cat("  ", 포포주소, " = add i64 ", 포포주값, ", ", 포포오프셋))
                        줄(cat("  ", 포포포인터, " = inttoptr i64 ", 포포주소, " to ", 포포LL, "*"))
                        줄(cat("  store ", 포포LL, " ", 포포값, ", ", 포포LL, "* ", 포포포인터, ", align 1"))
                        처리됨 = true
                    }
                }
            } else if 포몸.hasPrefix("오프셋 ") {
                let 포인자들 = commaSplit(sub(포몸, 10, 포몸.count - 10))
                if 포인자들.count == 3 {
                    let 포주값 = 값(cat(작업머리, 포인자들[0]))
                    let 포값내부 = 종류풀기(내부해석(포인자들[1]))
                    let 포값열쇠 = cat(작업머리, 포인자들[2])
                    var 포값 = 값(포값열쇠)
                    let 포값실내부 = 값내부(포값열쇠)
                    let 포LL = 타입LLVM(포값내부)
                    if 포주값.count > 0 && 포값.count > 0 && 포LL.count > 0 {
                        var 포유효 = true
                        if 포값실내부 != 포값내부 {
                            let 포변환 = 형변환연산(포값실내부, 포값내부)
                            if 포변환 == "?" { 포유효 = false }
                            else if 포변환.count > 0 {
                                let t = 새임시()
                                줄(cat("  ", t, " = ", 포변환, " ", 스칼라LLVM타입(포값실내부), " ", 포값, " to ", 스칼라LLVM타입(포값내부)))
                                포값 = t
                            }
                        }
                        if 포유효 {
                            let 포포인터 = 새임시()
                            줄(cat("  ", 포포인터, " = inttoptr i64 ", 포주값, " to ", 포LL, "*"))
                            줄(cat("  store ", 포LL, " ", 포값, ", ", 포LL, "* ", 포포인터, ", align 1"))
                            처리됨 = true
                        }
                    }
                }
            }
        }
        if !처리됨 && 낮텍스트.hasPrefix("분기 ") {
            let 분인자들 = commaSplit(sub(낮텍스트, 7, 낮텍스트.count - 7))
            if 분인자들.count == 3 {
                let 분값 = 값(cat(작업머리, 분인자들[0]))
                if 분값.count > 0 {
                    줄(cat("  br i1 ", 분값, ", label %", 라벨이름(분인자들[1]), ", label %", 라벨이름(분인자들[2])))
                    종결됨 = true
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮텍스트.hasPrefix("스위치 ") {
            let 스인자들 = commaSplit(sub(낮텍스트, 10, 낮텍스트.count - 10))
            if 스인자들.count >= 2 {
                let 스대상열쇠 = cat(작업머리, 스인자들[0])
                let 스대상값 = 값(스대상열쇠)
                let 스대상내부 = 값내부(스대상열쇠)
                if 스대상값.count > 0 && 스인자들[1].hasPrefix("기본 ") {
                    let 스기본라벨 = trim(sub(스인자들[1], 7, 스인자들[1].count - 7))
                    let 스LL = 스칼라LLVM타입(스대상내부)
                    줄(cat("  switch ", 스LL, " ", 스대상값, ", label %", 라벨이름(스기본라벨), " ["))
                    var 스번 = 2
                    while 스번 < 스인자들.count {
                        let 스갈래 = 스인자들[스번]
                        if let 스화살자리 = fnd(스갈래, " -> ") {
                            let 스값표기 = trim(sub(스갈래, 0, 스화살자리))
                            let 스갈라벨 = trim(sub(스갈래, 스화살자리 + 4, 스갈래.count - (스화살자리 + 4)))
                            if 스값표기.count == 0 || 스갈라벨.count == 0 {
                                fatalError("스위치 갈래에는 값과 목적 라벨이 필요합니다: \(스갈래)")
                            }
                            줄(cat("    ", 스LL, " ", 정수상수텍스트(스값표기, 스대상내부), ", label %", 라벨이름(스갈라벨)))
                        } else {
                            fatalError("스위치 갈래에는 ->가 필요합니다: \(스갈래)")
                        }
                        스번 += 1
                    }
                    줄("  ]")
                    종결됨 = true
                    처리됨 = true
                }
            }
        }
        if !처리됨 && 낮텍스트.hasPrefix("이동 ") {
            let 이라벨 = trim(sub(낮텍스트, 7, 낮텍스트.count - 7))
            줄(cat("  br label %", 라벨이름(이라벨)))
            종결됨 = true
            처리됨 = true
        }
        if !처리됨 && 낮텍스트 == "도달불가" {
            줄("  unreachable")
            종결됨 = true
            처리됨 = true
        }
        if !처리됨 && 낮텍스트.hasPrefix("간접호출 ") {
            처리됨 = 간접호출낮추기(낮텍스트, "void", "", 작업머리, 진입색인)
        }
        if !처리됨 { 처리됨 = 벡터문장낮추기(낮텍스트, 작업머리) }
        if !처리됨 { 처리됨 = 함수값해제낮추기(낮텍스트, 작업머리) }
        if !처리됨 && 낮텍스트.hasPrefix("버림 ") {
            let 버몸 = sub(낮텍스트, 7, 낮텍스트.count - 7)
            if let 버콜론자리 = fnd(버몸, ": ") {
                let 버참조 = trim(sub(버몸, 0, 버콜론자리))
                let 버타입표기 = trim(sub(버몸, 버콜론자리 + 2, 버몸.count - (버콜론자리 + 2)))
                let 버내부 = 종류풀기(내부해석(버타입표기))
                if 버내부 == "text" {
                    let 버값 = 값(cat(작업머리, 버참조))
                    if 버값.count > 0 {
                        let 버해제심볼 = 함수심볼("문자열해제", ["text"])
                        줄(cat("  call void @", 버해제심볼, "({ i64, i64, i64, i64 } ", 버값, ")"))
                        처리됨 = true
                    }
                } else {
                    if !버내부.hasPrefix("struct:") { 처리됨 = true }
                }
            }
        }
        return (처리됨, 종결됨)
    }

    // 정본: 문장명령낮추기의 `쓰기 ` 갈래
    func 쓰기낮추기(_ 낮텍스트: BStr, _ 작업머리: BStr) -> Bool {
        let 쓰몸 = sub(낮텍스트, 7, 낮텍스트.count - 7)
        guard let 쓰등호자리 = fnd(쓰몸, " = ") else { return false }
        let 쓰대상 = sub(쓰몸, 0, 쓰등호자리)
        let 쓰참조 = trim(sub(쓰몸, 쓰등호자리 + 3, 쓰몸.count - (쓰등호자리 + 3)))
        let 쓰값열쇠 = cat(작업머리, 쓰참조)
        var 쓰값 = 값(쓰값열쇠)
        let 쓰값내부 = 값내부(쓰값열쇠)
        var 길유효 = true
        let 길대상전체 = 쓰대상
        let 길전길이 = 길대상전체.count
        var 길머리끝 = 길전길이
        for 길걸음 in 0..<길전길이 {
            let b = 길대상전체[길걸음]
            if (b == 46 || b == 91) && 길머리끝 == 길전길이 { 길머리끝 = 길걸음 }
        }
        let 길첫이름 = sub(길대상전체, 0, 길머리끝)
        let 길환경열쇠 = cat(작업머리, 길첫이름)
        var 길포인터 = st.환경포인터.bkg(길환경열쇠)
        var 길내부 = st.환경내부들.bkg(길환경열쇠)
        if 길포인터.count == 0 {
            if 전역타입[길첫이름] != nil {
                길포인터 = 전역심볼이름(길첫이름)
                길내부 = 전역타입.bkg(길첫이름)
            }
        }
        if 길포인터.count == 0 { 길유효 = false }
        var 길자리 = 길머리끝
        while 길유효 && 길자리 < 길전길이 {
            let 길갈바이트 = 길대상전체[길자리]
            if 길갈바이트 == 46 {
                var 길필끝 = 길자리 + 1
                while 길필끝 < 길전길이 {
                    let b = 길대상전체[길필끝]
                    if b == 46 || b == 91 { break }
                    길필끝 += 1
                }
                let 길필드명 = sub(길대상전체, 길자리 + 1, 길필끝 - (길자리 + 1))
                if !길내부.hasPrefix("struct:") {
                    길유효 = false
                } else {
                    let 길구이름 = sub(길내부, 7, 길내부.count - 7)
                    let 길구필드들 = 세미나누기(구조체들.bkg(길구이름))
                    var 길구색인 = 999
                    var 길구필내부: BStr = ""
                    var 길구번 = 0
                    for 길구항목 in 길구필드들 {
                        let 길구콜자리 = fnd(길구항목, ":") ?? 0
                        if sub(길구항목, 0, 길구콜자리) == 길필드명 {
                            길구색인 = 길구번
                            길구필내부 = sub(길구항목, 길구콜자리 + 1, 길구항목.count - (길구콜자리 + 1))
                        }
                        길구번 += 1
                    }
                    if 길구색인 == 999 {
                        길유효 = false
                    } else {
                        let 길구LL = 타입LLVM(길내부)
                        let 길구다음 = 새임시()
                        줄(cat("  ", 길구다음, " = getelementptr inbounds ", 길구LL, ", ", 길구LL, "* ", 길포인터, ", i64 0, i32 ", num(길구색인)))
                        길포인터 = 길구다음
                        길내부 = 종류풀기(길구필내부)
                    }
                }
                길자리 = 길필끝
            } else if 길갈바이트 == 91 {
                var 길닫자리 = 길자리 + 1
                while 길닫자리 < 길전길이 && 길대상전체[길닫자리] != 93 { 길닫자리 += 1 }
                var 길색인표기 = trim(sub(길대상전체, 길자리 + 1, 길닫자리 - (길자리 + 1)))
                var 길순번임 = false
                if 길색인표기.hasPrefix("순번 ") {
                    길순번임 = true
                    길색인표기 = trim(sub(길색인표기, 7, 길색인표기.count - 7))
                }
                let 길색열쇠 = cat(작업머리, 길색인표기)
                var 길색값 = 값(길색열쇠)
                let 길색내부 = 값내부(길색열쇠)
                if 길색값.count == 0 || !길내부.hasPrefix("array<") {
                    길유효 = false
                } else {
                    let 길색변환 = 형변환연산(길색내부, "i64")
                    if 길색변환 == "?" {
                        길유효 = false
                    } else {
                        if 길색변환.count > 0 {
                            let t = 새임시()
                            줄(cat("  ", t, " = ", 길색변환, " ", 스칼라LLVM타입(길색내부), " ", 길색값, " to i64"))
                            길색값 = t
                        }
                        if 길순번임 {
                            let t = 새임시()
                            줄(cat("  ", t, " = sub i64 ", 길색값, ", 1"))
                            길색값 = t
                        }
                        let 길배LL = 타입LLVM(길내부)
                        let 길배쉼자리 = fnd(길내부, ",") ?? 0
                        let 길배원내부 = sub(길내부, 6, 길배쉼자리 - 6)
                        let 길배다음 = 새임시()
                        줄(cat("  ", 길배다음, " = getelementptr inbounds ", 길배LL, ", ", 길배LL, "* ", 길포인터, ", i64 0, i64 ", 길색값))
                        길포인터 = 길배다음
                        길내부 = 종류풀기(길배원내부)
                    }
                }
                길자리 = 길닫자리 + 1
            } else {
                길유효 = false
            }
        }
        if 길유효 && 쓰값.count > 0 {
            if 쓰값내부 != 길내부 {
                let 쓰변환 = 형변환연산(쓰값내부, 길내부)
                if 쓰변환 == "?" {
                    길유효 = false
                } else if 쓰변환.count > 0 {
                    let t = 새임시()
                    줄(cat("  ", t, " = ", 쓰변환, " ", 스칼라LLVM타입(쓰값내부), " ", 쓰값, " to ", 스칼라LLVM타입(길내부)))
                    쓰값 = t
                }
            }
            if 길유효 {
                let 쓰LL = 타입LLVM(길내부)
                줄(cat("  store ", 쓰LL, " ", 쓰값, ", ", 쓰LL, "* ", 길포인터))
                return true
            }
        }
        return false
    }
}
