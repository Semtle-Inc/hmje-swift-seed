// 정본: LLVM/클로저낮추기.hmje

extension BKL {
    // 정본: 클로저포인터반환LLVM
    func 클로저포인터반환LLVM(_ 반환내부: BStr) -> BStr {
        if ABI간접(반환내부) { return "void" }
        return 타입LLVM(반환내부)
    }

    // 정본: 클로저포인터첫인자LLVM
    func 클로저포인터첫인자LLVM(_ 반환내부: BStr) -> BStr {
        if ABI간접(반환내부) { return cat(타입LLVM(반환내부), "*, i64") }
        return "i64"
    }

    /// 출력줄들·임시번호·라벨번호를 잠시 다른 것으로 바꿔 소유해제낮추기를 돌린다
    /// (정본은 별도 LLVM변환상태를 만들어 넘기고 세 필드만 되받는다).
    func 딴줄에서해제(_ 줄들: inout [BStr], _ 임시: inout Int, _ 라벨: inout Int, _ 값: BStr, _ 내부: BStr) {
        let s줄 = st.출력줄들, s임 = st.임시번호, s라 = st.라벨번호
        st.출력줄들 = 줄들; st.임시번호 = 임시; st.라벨번호 = 라벨
        소유해제낮추기(값, 내부)
        줄들 = st.출력줄들; 임시 = st.임시번호; 라벨 = st.라벨번호
        st.출력줄들 = s줄; st.임시번호 = s임; st.라벨번호 = s라
    }

    // 정본: 함수값참조낮추기
    func 함수값참조낮추기(_ 낮몸통: BStr, _ 결과열쇠: BStr, _ 작업머리: BStr) -> Bool {
        let 머리: BStr = "함수값참조 "
        guard 낮몸통.hasPrefix(머리) else { return false }
        let 참조 = trim(sub(낮몸통, 머리.count, 낮몸통.count - 머리.count))
        let 열쇠 = cat(작업머리, 참조)
        let 함참값 = 값(열쇠)
        let 함참내부 = 값내부(열쇠)
        guard 함참값.count > 0 else { return false }
        let 함참환경 = 새임시(), 함참환경있음 = 새임시()
        줄(cat("  ", 함참환경, " = extractvalue { i64, i64, i64 } ", 함참값, ", 1"))
        줄(cat("  ", 함참환경있음, " = icmp ne i64 ", 함참환경, ", 0"))
        st.라벨번호 += 1
        let 함참라벨 = cat("closure.retain.", num(st.라벨번호))
        st.라벨번호 += 1
        let 함참끝라벨 = cat("closure.retain.done.", num(st.라벨번호))
        줄(cat("  br i1 ", 함참환경있음, ", label %", 함참라벨, ", label %", 함참끝라벨))
        줄(cat(함참라벨, ":"))
        let 함참포인터 = 새임시(), 함참개수 = 새임시(), 함참증가값 = 새임시(), 함참포화 = 새임시()
        st.라벨번호 += 1
        let 함참증가라벨 = cat("closure.retain.increment.", num(st.라벨번호))
        줄(cat("  ", 함참포인터, " = inttoptr i64 ", 함참환경, " to i64*"))
        줄(cat("  ", 함참개수, " = load i64, i64* ", 함참포인터))
        줄(cat("  ", 함참포화, " = icmp eq i64 ", 함참개수, ", -1"))
        줄(cat("  br i1 ", 함참포화, ", label %", 함참끝라벨, ", label %", 함참증가라벨))
        줄(cat(함참증가라벨, ":"))
        줄(cat("  ", 함참증가값, " = add i64 ", 함참개수, ", 1"))
        줄(cat("  store i64 ", 함참증가값, ", i64* ", 함참포인터))
        줄(cat("  br label %", 함참끝라벨))
        줄(cat(함참끝라벨, ":"))
        값설정(결과열쇠, 함참값, 함참내부)
        return true
    }

    // 정본: 클로저생성낮추기
    func 클로저생성낮추기(_ 낮몸통: BStr, _ 결과내부: BStr, _ 결과열쇠: BStr, _ 작업머리: BStr, _ 진입색인: Int) -> Bool {
        let 머리: BStr = "클로저값 "
        guard 낮몸통.hasPrefix(머리) else { return false }
        let 몸 = sub(낮몸통, 머리.count, 낮몸통.count - 머리.count)
        guard let 여는자리 = fnd(몸, "(") else { return false }
        let 클로저함수이름 = sub(몸, 0, 여는자리)
        let 캡처부 = sub(몸, 여는자리 + 1, 몸.count - (여는자리 + 2))
        let 캡처참조들 = commaSplit(캡처부)
        var 캡처값들: [BStr] = []
        var 캡처내부들: [BStr] = []
        var 환경크기 = 8
        var 캡유효함 = true
        for r in 캡처참조들 {
            let k = cat(작업머리, r)
            let v = 값(k), t = 값내부(k)
            if v.count == 0 || t.count == 0 { 캡유효함 = false }
            캡처값들.append(v)
            캡처내부들.append(t)
            환경크기 = 환경크기 &+ ABI크기(t)
        }
        guard 캡유효함 else { return false }
        var 환경값: BStr = "0"
        if 캡처값들.count > 0 {
            let 할당심볼 = 함수심볼("메모리할당", ["u64"])
            환경값 = 새임시()
            줄(cat("  ", 환경값, " = call i64 @", 할당심볼, "(i64 ", num(환경크기), ")"))
            let 참조포인터 = 새임시()
            줄(cat("  ", 참조포인터, " = inttoptr i64 ", 환경값, " to i64*"))
            줄(cat("  store i64 1, i64* ", 참조포인터))
            var 오프셋 = 8
            for i in 0..<캡처값들.count {
                let 캡내부2 = 캡처내부들[i]
                if 소유내부인가(캡내부2, 0) {
                    캡처값들[i] = 소유참조낮추기(캡처값들[i], 캡내부2)
                }
                let 캡LL = 타입LLVM(캡처내부들[i])
                let 바이트포인터 = 새임시()
                줄(cat("  ", 바이트포인터, " = inttoptr i64 ", 환경값, " to i8*"))
                let 옮긴포인터 = 새임시()
                줄(cat("  ", 옮긴포인터, " = getelementptr i8, i8* ", 바이트포인터, ", i64 ", num(오프셋)))
                let 타입포인터 = 새임시()
                줄(cat("  ", 타입포인터, " = bitcast i8* ", 옮긴포인터, " to ", 캡LL, "*"))
                줄(cat("  store ", 캡LL, " ", 캡처값들[i], ", ", 캡LL, "* ", 타입포인터))
                오프셋 = 오프셋 &+ ABI크기(캡처내부들[i])
            }
        }
        let 반환내부 = 함수타입반환(결과내부)
        let 인자내부들 = 함수타입인자들(결과내부)
        var 숨: [BStr] = ["address"]
        var 함수인자LL = 클로저포인터첫인자LLVM(반환내부)
        var 함수반환LL = 클로저포인터반환LLVM(반환내부)
        if 결과내부.hasPrefix("asyncfn<") { 함수반환LL = "i8*" }
        for a in 인자내부들 {
            숨.append(a)
            함수인자LL = cat(함수인자LL, ", ", ABI매개LLVM(a))
        }
        let 클로저심볼 = 함수심볼(클로저함수이름, 숨)
        let 코드 = 새임시()
        줄(cat("  ", 코드, " = ptrtoint ", 함수반환LL, " (", 함수인자LL, ")* @", 클로저심볼, " to i64"))
        let 값하나 = 새임시()
        let 값둘 = 새임시()
        var 해제값: BStr = "0"
        if 캡처값들.count > 0 {
            var 캡서명: [BStr] = []
            for (i, t) in 캡처내부들.enumerated() {
                if i > 0 { 캡서명.append("_") }
                캡서명.append(맹글이름(t))
            }
            let 해제이름 = cat("hmje_closure_release__", 맹글이름(클로저함수이름), "__", catArr(캡서명))
            if !st.생성어댑터들.contains(해제이름) {
                st.생성어댑터들.insert(해제이름)
                var 해몸통줄들: [BStr] = []
                var 해임시번호 = 5
                var 해라벨번호 = 0
                var 해오프셋 = 8
                for 해캡내부 in 캡처내부들 {
                    if 소유내부인가(해캡내부, 0) {
                        let 해캡LL = 타입LLVM(해캡내부)
                        해임시번호 += 1; let 해바이트포인터 = tv(해임시번호)
                        해임시번호 += 1; let 해옮긴포인터 = tv(해임시번호)
                        해임시번호 += 1; let 해타입포인터 = tv(해임시번호)
                        해임시번호 += 1; let 해적재값 = tv(해임시번호)
                        해몸통줄들.append(cat("  ", 해바이트포인터, " = inttoptr i64 %ctx to i8*"))
                        해몸통줄들.append(cat("  ", 해옮긴포인터, " = getelementptr i8, i8* ", 해바이트포인터, ", i64 ", num(해오프셋)))
                        해몸통줄들.append(cat("  ", 해타입포인터, " = bitcast i8* ", 해옮긴포인터, " to ", 해캡LL, "*"))
                        해몸통줄들.append(cat("  ", 해적재값, " = load ", 해캡LL, ", ", 해캡LL, "* ", 해타입포인터))
                        딴줄에서해제(&해몸통줄들, &해임시번호, &해라벨번호, 해적재값, 해캡내부)
                    }
                    해오프셋 = 해오프셋 &+ ABI크기(해캡내부)
                }
                var 해할당줄들: [BStr] = []
                var 해본문줄들: [BStr] = []
                for l in 해몸통줄들 {
                    if fnd(l, " = alloca ") != nil { 해할당줄들.append(l) } else { 해본문줄들.append(l) }
                }
                st.전역줄들.append(cat("define void @", 해제이름, "(i64 %ctx) {"))
                st.전역줄들.append("entry:")
                st.전역줄들.append(contentsOf: 해할당줄들)
                st.전역줄들.append("  %t1 = inttoptr i64 %ctx to i64*")
                st.전역줄들.append("  %t2 = load i64, i64* %t1")
                st.전역줄들.append("  %t3 = icmp eq i64 %t2, -1")
                st.전역줄들.append("  br i1 %t3, label %saturated, label %check")
                st.전역줄들.append("saturated:")
                st.전역줄들.append("  ret void")
                st.전역줄들.append("check:")
                st.전역줄들.append("  %t4 = icmp ule i64 %t2, 1")
                st.전역줄들.append("  br i1 %t4, label %free, label %dec")
                st.전역줄들.append("dec:")
                st.전역줄들.append("  %t5 = sub i64 %t2, 1")
                st.전역줄들.append("  store i64 %t5, i64* %t1")
                st.전역줄들.append("  ret void")
                st.전역줄들.append("free:")
                st.전역줄들.append(contentsOf: 해본문줄들)
                let 메모리해제 = 함수심볼("메모리해제", ["address"])
                st.전역줄들.append(cat("  call void @", 메모리해제, "(i64 %ctx)"))
                st.전역줄들.append("  ret void")
                st.전역줄들.append("}")
                st.전역줄들.append("")
            }
            해제값 = 새임시()
            줄(cat("  ", 해제값, " = ptrtoint void (i64)* @", 해제이름, " to i64"))
        }
        let 값셋 = 새임시()
        줄(cat("  ", 값하나, " = insertvalue { i64, i64, i64 } zeroinitializer, i64 ", 코드, ", 0"))
        줄(cat("  ", 값둘, " = insertvalue { i64, i64, i64 } ", 값하나, ", i64 ", 환경값, ", 1"))
        줄(cat("  ", 값셋, " = insertvalue { i64, i64, i64 } ", 값둘, ", i64 ", 해제값, ", 2"))
        값설정(결과열쇠, 값셋, 결과내부)
        return true
    }

    // 정본: 함수값해제낮추기
    func 함수값해제낮추기(_ 낮텍스트: BStr, _ 작업머리: BStr) -> Bool {
        let 머리: BStr = "함수값해제 "
        guard 낮텍스트.hasPrefix(머리) else { return false }
        let 참조 = trim(sub(낮텍스트, 머리.count, 낮텍스트.count - 머리.count))
        let 열쇠 = cat(작업머리, 참조)
        let 함해값 = 값(열쇠)
        let 함해내부 = 값내부(열쇠)
        guard 함해값.count > 0 && 함해내부.hasPrefix("fn<") else { return false }
        let 함해환경 = 새임시(), 함해함수값 = 새임시(), 함해있음 = 새임시()
        줄(cat("  ", 함해환경, " = extractvalue { i64, i64, i64 } ", 함해값, ", 1"))
        줄(cat("  ", 함해함수값, " = extractvalue { i64, i64, i64 } ", 함해값, ", 2"))
        줄(cat("  ", 함해있음, " = icmp ne i64 ", 함해환경, ", 0"))
        st.라벨번호 += 1
        let 함해라벨 = cat("closure.release.", num(st.라벨번호))
        st.라벨번호 += 1
        let 함해끝라벨 = cat("closure.release.done.", num(st.라벨번호))
        줄(cat("  br i1 ", 함해있음, ", label %", 함해라벨, ", label %", 함해끝라벨))
        줄(cat(함해라벨, ":"))
        let 함해포인터 = 새임시()
        줄(cat("  ", 함해포인터, " = inttoptr i64 ", 함해함수값, " to void (i64)*"))
        줄(cat("  call void ", 함해포인터, "(i64 ", 함해환경, ")"))
        줄(cat("  br label %", 함해끝라벨))
        줄(cat(함해끝라벨, ":"))
        return true
    }

    // 정본: 함수값생성낮추기
    func 함수값생성낮추기(_ 낮몸통: BStr, _ 결과내부: BStr, _ 결과열쇠: BStr) -> Bool {
        let 머리: BStr = "함수값 "
        guard 낮몸통.hasPrefix(머리) else { return false }
        let 무캡함이름 = trim(sub(낮몸통, 머리.count, 낮몸통.count - 머리.count))
        let 무캡반환내부 = 함수타입반환(결과내부)
        let 무캡인자내부들 = 함수타입인자들(결과내부)
        var 인자직렬: BStr = ""
        var 인자LL: BStr = ""
        var 어댑터매개: BStr = "i64 %__ctx"
        var 원호출인자: BStr = ""
        for (i, a) in 무캡인자내부들.enumerated() {
            if i > 0 { 인자직렬 = cat(인자직렬, ","); 인자LL = cat(인자LL, ", ") }
            인자직렬 = cat(인자직렬, a)
            let 낱LL = ABI매개LLVM(a)
            인자LL = cat(인자LL, 낱LL)
            어댑터매개 = cat(어댑터매개, ", ", 낱LL, " %arg", num(i))
            if i > 0 { 원호출인자 = cat(원호출인자, ", ") }
            원호출인자 = cat(원호출인자, 낱LL, " %arg", num(i))
        }
        let 실반환 = 함수반환.bkg(cat(무캡함이름, "|", 인자직렬))
        guard 실반환.count > 0 else { return false }
        let 원심볼 = 함수심볼(무캡함이름, 무캡인자내부들)
        let 어댑터이름 = cat("hmje_closure_adapter__", 맹글이름(원심볼))
        let 반환LL = 타입LLVM(무캡반환내부)
        let 반환간접임 = ABI간접(무캡반환내부)
        let 반환보이드임 = 무캡반환내부 == "void"
        let 어댑터반환 = 클로저포인터반환LLVM(무캡반환내부)
        var 포인터서명 = 클로저포인터첫인자LLVM(무캡반환내부)
        if 인자LL.count > 0 { 포인터서명 = cat(포인터서명, ", ", 인자LL) }
        if 반환간접임 {
            어댑터매개 = cat(반환LL, "* sret(", 반환LL, ") %__ret, ", 어댑터매개)
            원호출인자 = cat(반환LL, "* sret(", 반환LL, ") %__ret, ", 원호출인자)
        }
        if !st.생성어댑터들.contains(어댑터이름) {
            st.생성어댑터들.insert(어댑터이름)
            st.전역줄들.append(cat("define ", 어댑터반환, " @", 어댑터이름, "(", 어댑터매개, ") {"))
            st.전역줄들.append("entry:")
            if 반환간접임 || 반환보이드임 {
                st.전역줄들.append(cat("  call void @", 원심볼, "(", 원호출인자, ")"))
                st.전역줄들.append("  ret void")
            }
            if !반환간접임 && !반환보이드임 {
                st.전역줄들.append(cat("  %r = call ", 반환LL, " @", 원심볼, "(", 원호출인자, ")"))
                st.전역줄들.append(cat("  ret ", 반환LL, " %r"))
            }
            st.전역줄들.append("}")
            st.전역줄들.append("")
        }
        let 코드 = 새임시()
        줄(cat("  ", 코드, " = ptrtoint ", 어댑터반환, " (", 포인터서명, ")* @", 어댑터이름, " to i64"))
        let 값하나 = 새임시(), 값둘 = 새임시(), 값셋 = 새임시()
        줄(cat("  ", 값하나, " = insertvalue { i64, i64, i64 } zeroinitializer, i64 ", 코드, ", 0"))
        줄(cat("  ", 값둘, " = insertvalue { i64, i64, i64 } ", 값하나, ", i64 0, 1"))
        줄(cat("  ", 값셋, " = insertvalue { i64, i64, i64 } ", 값둘, ", i64 0, 2"))
        값설정(결과열쇠, 값셋, 결과내부)
        return true
    }
}
