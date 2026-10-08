// 정본: LLVM/소유낮추기.hmje

extension BKL {
    // 정본: 소유채널끝점인가
    func 소유채널끝점인가(_ 구조이름: BStr) -> Bool {
        구조이름.hasPrefix("HMJE채널송신_") || 구조이름.hasPrefix("HMJE채널수신_")
    }

    // 정본: 소유동적배열접두
    func 소유동적배열접두(_ 소유내부: BStr) -> BStr {
        let 꼬리: BStr = "동적배열형"
        if !소유내부.hasPrefix("struct:") { return "" }
        let 구조이름 = sub(소유내부, 7, 소유내부.count - 7)
        if !구조이름.hasSuffix(꼬리) { return "" }
        return sub(구조이름, 0, 구조이름.count - 꼬리.count)
    }

    // 정본: 소유내부인가
    func 소유내부인가(_ 소유내부: BStr, _ 소유깊이: Int) -> Bool {
        if 소유깊이 > 8 { return false }
        if 소유내부.hasPrefix("overlay:") || 소유내부.hasPrefix("overlay_array:") { return false }
        if 소유내부 == "text" { return true }
        if 소유내부.hasPrefix("fn<") || 소유내부.hasPrefix("asyncfn<") { return true }
        if 소유내부.hasPrefix("enum:") {
            let k = 종류풀기(소유내부)
            if k == 소유내부 { return false }
            return 소유내부인가(k, 소유깊이 + 1)
        }
        if 소유내부.hasPrefix("array<") {
            if let p = fnd(소유내부, ",") { return 소유내부인가(sub(소유내부, 6, p - 6), 소유깊이 + 1) }
            return false
        }
        if !소유내부.hasPrefix("struct:") { return false }
        let 소유구이름 = sub(소유내부, 7, 소유내부.count - 7)
        if 소유구이름.hasSuffix("동적배열형") { return true }
        if 소유채널끝점인가(소유구이름) { return true }
        guard let def = 구조체들[소유구이름] else { return false }
        for 조각 in 세미나누기(def) {
            if let p = fnd(조각, ":") {
                if 소유내부인가(sub(조각, p + 1, 조각.count - (p + 1)), 소유깊이 + 1) { return true }
            }
        }
        return false
    }

    // 정본: 소유필드내부
    func 소유필드내부(_ 조각: BStr) -> BStr {
        if let p = fnd(조각, ":") { return sub(조각, p + 1, 조각.count - (p + 1)) }
        return ""
    }

    // 정본: 소유참조낮추기 → 새 값
    func 소유참조낮추기(_ 소유값: BStr, _ 소유내부: BStr) -> BStr {
        var 결과값 = 소유값
        var 처리됨 = false
        let 소유LL = 타입LLVM(소유내부)
        var 끝점이름: BStr = ""
        if 소유내부.hasPrefix("struct:") {
            let n = sub(소유내부, 7, 소유내부.count - 7)
            if 소유채널끝점인가(n) { 끝점이름 = n }
        }
        if 끝점이름.count > 0 {
            let 끝점심볼 = 함수심볼(cat(끝점이름, "참조"), [소유내부])
            결과값 = 새임시()
            줄(cat("  ", 결과값, " = call ", 소유LL, " @", 끝점심볼, "(", 소유LL, " ", 소유값, ")"))
            처리됨 = true
        }
        let 함수값임 = 소유내부.hasPrefix("fn<") || 소유내부.hasPrefix("asyncfn<")
        if !처리됨 && 함수값임 {
            let 참환경 = 새임시(), 참환경있음 = 새임시()
            줄(cat("  ", 참환경, " = extractvalue { i64, i64, i64 } ", 소유값, ", 1"))
            줄(cat("  ", 참환경있음, " = icmp ne i64 ", 참환경, ", 0"))
            st.라벨번호 += 1
            let 참라벨 = cat("closure.retain.", num(st.라벨번호))
            st.라벨번호 += 1
            let 참끝라벨 = cat("closure.retain.done.", num(st.라벨번호))
            줄(cat("  br i1 ", 참환경있음, ", label %", 참라벨, ", label %", 참끝라벨))
            줄(cat(참라벨, ":"))
            let 참포인터 = 새임시(), 참개수 = 새임시(), 참증가값 = 새임시(), 참포화 = 새임시()
            st.라벨번호 += 1
            let 참증가라벨 = cat("closure.retain.increment.", num(st.라벨번호))
            줄(cat("  ", 참포인터, " = inttoptr i64 ", 참환경, " to i64*"))
            줄(cat("  ", 참개수, " = load i64, i64* ", 참포인터))
            줄(cat("  ", 참포화, " = icmp eq i64 ", 참개수, ", -1"))
            줄(cat("  br i1 ", 참포화, ", label %", 참끝라벨, ", label %", 참증가라벨))
            줄(cat(참증가라벨, ":"))
            줄(cat("  ", 참증가값, " = add i64 ", 참개수, ", 1"))
            줄(cat("  store i64 ", 참증가값, ", i64* ", 참포인터))
            줄(cat("  br label %", 참끝라벨))
            줄(cat(참끝라벨, ":"))
            처리됨 = true
        }
        if !처리됨 && 소유내부 == "text" {
            let 참문심볼 = 함수심볼("문자열참조", ["text"])
            결과값 = 새임시()
            줄(cat("  ", 결과값, " = call ", 소유LL, " @", 참문심볼, "(", 소유LL, " ", 소유값, ")"))
            처리됨 = true
        }
        let 참동적접두 = 소유동적배열접두(소유내부)
        if !처리됨 && 참동적접두.count > 0 {
            let 참동적심볼 = 함수심볼(cat(참동적접두, "동적배열참조"), [소유내부])
            if ABI간접(소유내부) {
                let 입력슬롯 = 새임시()
                줄(cat("  ", 입력슬롯, " = alloca ", 소유LL))
                줄(cat("  store ", 소유LL, " ", 소유값, ", ", 소유LL, "* ", 입력슬롯))
                let 결과슬롯 = 새임시()
                줄(cat("  ", 결과슬롯, " = alloca ", 소유LL))
                줄(cat("  call void @", 참동적심볼, "(", 소유LL, "* sret(", 소유LL, ") ", 결과슬롯, ", ", 소유LL, "* ", 입력슬롯, ")"))
                결과값 = 새임시()
                줄(cat("  ", 결과값, " = load ", 소유LL, ", ", 소유LL, "* ", 결과슬롯))
            } else {
                결과값 = 새임시()
                줄(cat("  ", 결과값, " = call ", 소유LL, " @", 참동적심볼, "(", 소유LL, " ", 소유값, ")"))
            }
            처리됨 = true
        }
        if !처리됨 && 소유내부.hasPrefix("struct:") {
            let 참구이름2 = sub(소유내부, 7, 소유내부.count - 7)
            let 참구필드들 = 세미나누기(구조체들.bkg(참구이름2))
            var 참누적: BStr = "undef"
            var 참필번 = 0
            while 참필번 < 참구필드들.count {
                let 참필내부 = 소유필드내부(참구필드들[참필번])
                let 참필LL = 타입LLVM(참필내부)
                var 참필값 = 새임시()
                줄(cat("  ", 참필값, " = extractvalue ", 소유LL, " ", 소유값, ", ", num(참필번)))
                if 소유내부인가(참필내부, 0) {
                    참필값 = 소유참조낮추기(참필값, 참필내부)
                }
                let 참필넣 = 새임시()
                줄(cat("  ", 참필넣, " = insertvalue ", 소유LL, " ", 참누적, ", ", 참필LL, " ", 참필값, ", ", num(참필번)))
                참누적 = 참필넣
                참필번 += 1
            }
            결과값 = 참누적
        }
        return 결과값
    }

    // 정본: 소유해제낮추기
    func 소유해제낮추기(_ 소유값: BStr, _ 소유내부: BStr) {
        var 처리됨 = false
        let 해LL = 타입LLVM(소유내부)
        var 해끝점이름: BStr = ""
        if 소유내부.hasPrefix("struct:") {
            let n = sub(소유내부, 7, 소유내부.count - 7)
            if 소유채널끝점인가(n) { 해끝점이름 = n }
        }
        if 해끝점이름.count > 0 {
            let s = 함수심볼(cat(해끝점이름, "해제"), [소유내부])
            줄(cat("  call void @", s, "(", 해LL, " ", 소유값, ")"))
            처리됨 = true
        }
        let 해함수값임 = 소유내부.hasPrefix("fn<") || 소유내부.hasPrefix("asyncfn<")
        if !처리됨 && 해함수값임 {
            let 해환경 = 새임시(), 해해제값 = 새임시(), 해환경있음 = 새임시()
            줄(cat("  ", 해환경, " = extractvalue { i64, i64, i64 } ", 소유값, ", 1"))
            줄(cat("  ", 해해제값, " = extractvalue { i64, i64, i64 } ", 소유값, ", 2"))
            줄(cat("  ", 해환경있음, " = icmp ne i64 ", 해환경, ", 0"))
            st.라벨번호 += 1
            let 해라벨 = cat("closure.release.", num(st.라벨번호))
            st.라벨번호 += 1
            let 해끝라벨 = cat("closure.release.done.", num(st.라벨번호))
            줄(cat("  br i1 ", 해환경있음, ", label %", 해라벨, ", label %", 해끝라벨))
            줄(cat(해라벨, ":"))
            let 해포인터 = 새임시()
            줄(cat("  ", 해포인터, " = inttoptr i64 ", 해해제값, " to void (i64)*"))
            줄(cat("  call void ", 해포인터, "(i64 ", 해환경, ")"))
            줄(cat("  br label %", 해끝라벨))
            줄(cat(해끝라벨, ":"))
            처리됨 = true
        }
        if !처리됨 && 소유내부 == "text" {
            let s = 함수심볼("문자열해제", ["text"])
            줄(cat("  call void @", s, "(", 해LL, " ", 소유값, ")"))
            처리됨 = true
        }
        let 해동적접두 = 소유동적배열접두(소유내부)
        if !처리됨 && 해동적접두.count > 0 {
            let s = 함수심볼(cat(해동적접두, "동적배열해제"), [소유내부])
            let 슬롯 = 새임시()
            줄(cat("  ", 슬롯, " = alloca ", 해LL))
            줄(cat("  store ", 해LL, " ", 소유값, ", ", 해LL, "* ", 슬롯))
            줄(cat("  call void @", s, "(", 해LL, "* ", 슬롯, ")"))
            처리됨 = true
        }
        if !처리됨 && 소유내부.hasPrefix("struct:") {
            let n = sub(소유내부, 7, 소유내부.count - 7)
            let 필드들 = 세미나누기(구조체들.bkg(n))
            var 해필번 = 0
            while 해필번 < 필드들.count {
                let 해필내부 = 소유필드내부(필드들[해필번])
                if 소유내부인가(해필내부, 0) {
                    let 해필값 = 새임시()
                    줄(cat("  ", 해필값, " = extractvalue ", 해LL, " ", 소유값, ", ", num(해필번)))
                    소유해제낮추기(해필값, 해필내부)
                }
                해필번 += 1
            }
        }
    }
}
