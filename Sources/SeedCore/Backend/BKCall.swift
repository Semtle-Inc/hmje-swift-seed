// 정본: LLVM/호출낮추기.hmje, LLVM/호출인자.hmje

extension BKL {
    // 정본: 함수심볼
    func 함수심볼(_ 이름: BStr, _ 인자내부들: [BStr]) -> BStr {
        if 이름.hasPrefix("hmje_rt_") || 이름.hasPrefix("hmje_kernel_") || 이름.hasPrefix("hmje_arch_") { return 이름 }
        var parts: [BStr] = ["hmje_fn_", 맹글이름(이름), "__"]
        if 인자내부들.isEmpty {
            parts.append("void")
        } else {
            for (i, a) in 인자내부들.enumerated() {
                if i > 0 { parts.append("_") }
                parts.append(맹글이름(a))
            }
        }
        return catArr(parts)
    }

    // 정본: LLVM바인딩인자읽기 → (값, 내부, 적재줄)
    func LLVM바인딩인자읽기(_ 열쇠: BStr, _ 다음번호: Int) -> (BStr, BStr, BStr) {
        let 포인터 = st.환경포인터.bkg(열쇠)
        let 내부 = st.환경내부들.bkg(열쇠)
        let 타입 = 타입LLVM(내부)
        if 포인터.count == 0 || 타입.count == 0 { return ("", "", "") }
        let v = tv(다음번호)
        return (v, 내부, cat("  ", v, " = load ", 타입, ", ", 타입, "* ", 포인터))
    }

    // 정본: 간접호출낮추기
    func 간접호출낮추기(_ 낮몸통: BStr, _ 결과내부: BStr, _ 결과열쇠: BStr, _ 작업머리: BStr, _ 진입색인: Int) -> Bool {
        let 간호머리: BStr = "간접호출 "
        guard 낮몸통.hasPrefix(간호머리) else { return false }
        let 간호몸 = sub(낮몸통, 간호머리.count, 낮몸통.count - 간호머리.count)
        guard let 간호여는자리 = fnd(간호몸, "(") else { return false }
        let 간호이름 = trim(sub(간호몸, 0, 간호여는자리))
        let 간호인자부 = sub(간호몸, 간호여는자리 + 1, 간호몸.count - (간호여는자리 + 2))
        let 간호참조들 = commaSplit(간호인자부)
        var 간호열쇠 = cat(작업머리, 간호이름)
        if st.환경포인터[간호열쇠] == nil { 간호열쇠 = cat("@전역함수:", 간호이름) }
        let 간호포인터 = st.환경포인터.bkg(간호열쇠)
        let 간호내부 = st.환경내부들.bkg(간호열쇠)
        guard 간호포인터.count > 0 else { return false }
        let 간호함값LL = 타입LLVM(간호내부)
        let 간호함값 = 새임시()
        줄(cat("  ", 간호함값, " = load ", 간호함값LL, ", ", 간호함값LL, "* ", 간호포인터))
        let 간호코드 = 새임시()
        let 간호환경 = 새임시()
        줄(cat("  ", 간호코드, " = extractvalue { i64, i64, i64 } ", 간호함값, ", 0"))
        줄(cat("  ", 간호환경, " = extractvalue { i64, i64, i64 } ", 간호함값, ", 1"))
        let 간호반환 = 함수타입반환(간호내부)
        let 간호인자내부들 = 함수타입인자들(간호내부)
        var 간호포인터서명: BStr = "i64"
        var 간호호출인자 = cat("i64 ", 간호환경)
        var 간호번 = 0
        var 간호인자유효함 = true
        var 간호임시슬롯들: [BStr] = []
        while 간호번 < 간호참조들.count && 간호번 < 간호인자내부들.count {
            let 간호낱값 = 값(cat(작업머리, 간호참조들[간호번]))
            if 간호낱값.count == 0 { 간호인자유효함 = false }
            let 간호낱내부 = 간호인자내부들[간호번]
            let 간호낱간접임 = ABI간접(간호낱내부)
            let 간호낱LL = ABI매개LLVM(간호낱내부)
            간호포인터서명 = cat(간호포인터서명, ", ", 간호낱LL)
            var 간호넘길값 = 간호낱값
            if 간호낱간접임 && 간호낱값.count > 0 {
                let 간호낱값LL = 타입LLVM(간호낱내부)
                let 간호낱슬롯 = 새임시()
                줄(cat("  ", 간호낱슬롯, " = alloca ", 간호낱값LL))
                줄(cat("  call void @llvm.lifetime.start.p0(i64 -1, ptr ", 간호낱슬롯, ")"))
                줄(cat("  store ", 간호낱값LL, " ", 간호낱값, ", ", 간호낱값LL, "* ", 간호낱슬롯))
                간호임시슬롯들.append(간호낱슬롯)
                간호넘길값 = 간호낱슬롯
            }
            간호호출인자 = cat(간호호출인자, ", ", 간호낱LL, " ", 간호넘길값)
            간호번 += 1
        }
        guard 간호인자유효함 else { return false }
        let 간호타입함수 = 새임시()
        let 간호반환LL = 타입LLVM(간호반환)
        var 간호결과: BStr = ""
        if ABI간접(간호반환) {
            간호포인터서명 = cat(간호반환LL, "*, ", 간호포인터서명)
            줄(cat("  ", 간호타입함수, " = inttoptr i64 ", 간호코드, " to void (", 간호포인터서명, ")*"))
            let 간호결과슬롯 = 새임시()
            줄(cat("  ", 간호결과슬롯, " = alloca ", 간호반환LL))
            줄(cat("  call void ", 간호타입함수, "(", 간호반환LL, "* sret(", 간호반환LL, ") ", 간호결과슬롯, ", ", 간호호출인자, ")"))
            간호결과 = 새임시()
            줄(cat("  ", 간호결과, " = load ", 간호반환LL, ", ", 간호반환LL, "* ", 간호결과슬롯))
        } else {
            줄(cat("  ", 간호타입함수, " = inttoptr i64 ", 간호코드, " to ", 간호반환LL, " (", 간호포인터서명, ")*"))
            if 간호반환 == "void" {
                줄(cat("  call void ", 간호타입함수, "(", 간호호출인자, ")"))
            } else {
                간호결과 = 새임시()
                줄(cat("  ", 간호결과, " = call ", 간호반환LL, " ", 간호타입함수, "(", 간호호출인자, ")"))
            }
        }
        for s in 간호임시슬롯들 { 줄(cat("  call void @llvm.lifetime.end.p0(i64 -1, ptr ", s, ")")) }
        if 간호반환 != "void" { 값설정(결과열쇠, 간호결과, 간호반환) }
        return true
    }

    /// 결과호출·문장호출이 공유하는 머리 해석: (대상, 외부이름, 이름, 내부들, 내부직렬, 인자참조들)
    func 호출머리해석(_ 몸: BStr) -> (BStr, BStr, BStr, [BStr], BStr, [BStr])? {
        guard let 대괄자리 = fnd(몸, "](") else { return nil }
        let 심볼부 = sub(몸, 7, 대괄자리 + 1 - 7)
        let 인자부 = sub(몸, 대괄자리 + 2, 몸.count - (대괄자리 + 2) - 1)
        let 여는자리 = fnd(심볼부, "[") ?? 0
        let 타입부 = sub(심볼부, 여는자리 + 1, 심볼부.count - (여는자리 + 1) - 1)
        var 이름: BStr = ""
        var 외부이름: BStr = ""
        if 심볼부.hasPrefix("@외부:") { 외부이름 = sub(심볼부, 8, 여는자리 - 8) }
        else { 이름 = sub(심볼부, 1, 여는자리 - 1) }
        var 내부직렬: BStr = ""
        var 내부들: [BStr] = []
        for (i, 표기) in commaSplit(타입부).enumerated() {
            let 낱 = 내부해석(표기)
            내부들.append(낱)
            if i > 0 { 내부직렬 = cat(내부직렬, ",") }
            내부직렬 = cat(내부직렬, 낱)
        }
        return (외부이름, 외부이름, 이름, 내부들, 내부직렬, commaSplit(인자부))
    }

    /// 결과호출·문장호출의 인자 적재 루프 (같은 본문). → (유효함, 호출인자, 임시슬롯들)
    func 호출인자모으기(_ 작업머리: BStr, _ 인자참조들: [BStr], _ 내부들: [BStr], _ 유효함0: Bool) -> (Bool, BStr, [BStr]) {
        var 유효함 = 유효함0
        var 호출인자: BStr = ""
        var 임시슬롯들: [BStr] = []
        if 인자참조들.count != 내부들.count { 유효함 = false }
        var 인번 = 0
        while 인번 < 인자참조들.count && 인번 < 내부들.count {
            let 참열쇠 = cat(작업머리, 인자참조들[인번])
            var 인값 = 값(참열쇠)
            var 인내부 = 값내부(참열쇠)
            if 인값.count == 0 {
                let (bv, bi, bl) = LLVM바인딩인자읽기(참열쇠, st.임시번호 + 1)
                if bv.count > 0 {
                    st.임시번호 += 1
                    줄(bl)
                    인값 = bv
                    인내부 = bi
                }
            }
            if 인값.count == 0 {
                유효함 = false
            } else {
                let 목표내부 = 종류풀기(내부들[인번])
                let 인간접임 = ABI간접(목표내부)
                if 인내부 != 목표내부 && !인간접임 {
                    let 인변환 = 형변환연산(인내부, 목표내부)
                    if 인변환 == "?" {
                        유효함 = false
                    } else if 인변환.count > 0 {
                        let t = 새임시()
                        줄(cat("  ", t, " = ", 인변환, " ", 스칼라LLVM타입(인내부), " ", 인값, " to ", 스칼라LLVM타입(목표내부)))
                        인값 = t
                    }
                }
                if 호출인자.count > 0 { 호출인자 = cat(호출인자, ", ") }
                if 인간접임 {
                    let 인LL = 타입LLVM(목표내부)
                    let 인슬롯 = 새임시()
                    줄(cat("  ", 인슬롯, " = alloca ", 인LL))
                    줄(cat("  call void @llvm.lifetime.start.p0(i64 -1, ptr ", 인슬롯, ")"))
                    let 실LL = 타입LLVM(인내부)
                    줄(cat("  store ", 실LL, " ", 인값, ", ", 실LL, "* ", 인슬롯))
                    임시슬롯들.append(인슬롯)
                    호출인자 = cat(호출인자, 인LL, "* ", 인슬롯)
                } else {
                    호출인자 = cat(호출인자, 타입LLVM(내부들[인번]), " ", 인값)
                }
            }
            인번 += 1
        }
        return (유효함, 호출인자, 임시슬롯들)
    }

    // 정본: 결과호출낮추기
    func 결과호출낮추기(_ 낮몸통: BStr, _ 결과내부: BStr, _ 결과열쇠: BStr, _ 작업머리: BStr, _ 진입색인: Int) -> Bool {
        guard 낮몸통.hasPrefix("호출 ") else { return false }
        guard let (외부, _, 이름, 내부들, 내부직렬, 인자참조들) = 호출머리해석(낮몸통) else { return false }
        var 대상 = 외부
        var 유효함 = true
        if 외부.count == 0 {
            if 함수반환[cat(이름, "|", 내부직렬)] != nil { 대상 = 함수심볼(이름, 내부들) } else { 유효함 = false }
        }
        let (유효2, 호출인자, 임시슬롯들) = 호출인자모으기(작업머리, 인자참조들, 내부들, 유효함)
        guard 유효2 else { return false }
        let 반환LLVM = 타입LLVM(결과내부)
        guard 반환LLVM.count > 0 else { return false }
        if ABI간접(결과내부) {
            let 받이 = 새임시()
            줄(cat("  ", 받이, " = alloca ", 반환LLVM))
            줄(cat("  call void @llvm.lifetime.start.p0(i64 -1, ptr ", 받이, ")"))
            var sret인자 = cat(반환LLVM, "* sret(", 반환LLVM, ") ", 받이)
            if 호출인자.count > 0 { sret인자 = cat(sret인자, ", ", 호출인자) }
            줄(cat("  call void @", 대상, "(", sret인자, ")"))
            let 적재 = 새임시()
            줄(cat("  ", 적재, " = load ", 반환LLVM, ", ", 반환LLVM, "* ", 받이))
            줄(cat("  call void @llvm.lifetime.end.p0(i64 -1, ptr ", 받이, ")"))
            값설정(결과열쇠, 적재, 결과내부)
        } else {
            let 결과 = 새임시()
            줄(cat("  ", 결과, " = call ", 반환LLVM, " @", 대상, "(", 호출인자, ")"))
            값설정(결과열쇠, 결과, 결과내부)
        }
        for s in 임시슬롯들 { 줄(cat("  call void @llvm.lifetime.end.p0(i64 -1, ptr ", s, ")")) }
        return true
    }

    // 정본: 문장호출낮추기
    func 문장호출낮추기(_ 낮텍스트: BStr, _ 작업머리: BStr, _ 진입색인: Int) -> Bool {
        guard 낮텍스트.hasPrefix("호출 ") else { return false }
        guard let (외부, _, 이름, 내부들, 내부직렬, 인자참조들) = 호출머리해석(낮텍스트) else { return false }
        var 대상 = 외부
        var 유효함 = true
        if 외부.count == 0 {
            if 함수반환[cat(이름, "|", 내부직렬)] != nil { 대상 = 함수심볼(이름, 내부들) } else { 유효함 = false }
        }
        let (유효2, 호출인자, 임시슬롯들) = 호출인자모으기(작업머리, 인자참조들, 내부들, 유효함)
        guard 유효2 else { return false }
        var 반환내부: BStr = "void"
        if 외부.count == 0 { 반환내부 = 함수반환[cat(이름, "|", 내부직렬)] ?? "void" }
        let 반환LLVM = 타입LLVM(반환내부)
        줄(cat("  call ", 반환LLVM, " @", 대상, "(", 호출인자, ")"))
        for s in 임시슬롯들 { 줄(cat("  call void @llvm.lifetime.end.p0(i64 -1, ptr ", s, ")")) }
        return true
    }
}
