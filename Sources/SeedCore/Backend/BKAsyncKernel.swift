// 정본: LLVM/비동기낮추기.hmje(비동기명령낮추기), LLVM/커널명령낮추기.hmje
// 네 도구 입력에는 비동기 함수·비동기 명령·커널 명령이 없다. 비동기 함수가 아닐 때도
// 도는 갈래 가운데 입력에 나타나는 것은 `함수값해제 `뿐이라 그것만 옮긴다.

extension BKL {
    /// 정본: 비동기명령낮추기 → (처리됨, 종결됨)
    func 비동기명령낮추기(_ 낮결과: BStr, _ 낮텍스트: BStr, _ 낮몸통: BStr, _ 작업머리: BStr, _ 비동기임: Bool, _ 종결입력: Bool) -> (Bool, Bool) {
        if 비동기임 { fatalError("미이식: 비동기명령낮추기 (비동기 함수)") }
        let 몸머리들: [BStr] = ["비동기시작 ", "비동기간접시작 "]
        for m in 몸머리들 where 낮몸통.hasPrefix(m) { fatalError("미이식: 비동기명령낮추기 \(m)") }
        let 텍머리들: [BStr] = ["비동기정리 ", "비동기실패정리 ", "비동기취소정리 ", "동시기다림 ", "비동기기다림 ", "UI비동기작업인계 ", "비동기인계 "]
        for m in 텍머리들 where 낮텍스트.hasPrefix(m) { fatalError("미이식: 비동기명령낮추기 \(m)") }
        if 낮텍스트 == "비동기취소가림시작" || 낮텍스트 == "비동기취소가림끝" { fatalError("미이식: 비동기명령낮추기 \(낮텍스트)") }
        let 머리: BStr = "함수값해제 "
        if 낮텍스트.hasPrefix(머리) {
            let 참조 = trim(sub(낮텍스트, 머리.count, 낮텍스트.count - 머리.count))
            let 함해값 = 값(cat(작업머리, 참조))
            let 함해환경 = 새임시(), 함해코드 = 새임시(), 함해있음 = 새임시()
            줄(cat("  ", 함해환경, " = extractvalue { i64, i64, i64 } ", 함해값, ", 1"))
            줄(cat("  ", 함해코드, " = extractvalue { i64, i64, i64 } ", 함해값, ", 2"))
            줄(cat("  ", 함해있음, " = icmp ne i64 ", 함해환경, ", 0"))
            st.라벨번호 += 1
            let 함해라벨 = cat("closure.release.", num(st.라벨번호))
            st.라벨번호 += 1
            let 함해끝 = cat("closure.release.done.", num(st.라벨번호))
            줄(cat("  br i1 ", 함해있음, ", label %", 함해라벨, ", label %", 함해끝))
            줄(cat(함해라벨, ":"))
            let p = 새임시()
            줄(cat("  ", p, " = inttoptr i64 ", 함해코드, " to void (i64)*"))
            줄(cat("  call void ", p, "(i64 ", 함해환경, ")"))
            줄(cat("  br label %", 함해끝))
            줄(cat(함해끝, ":"))
            return (true, 종결입력)
        }
        return (false, 종결입력)
    }

    // 정본: 커널값낮추기 / 커널문장낮추기 — 입력에 없으므로 닿으면 멈춘다.
    func 커널값낮추기(_ 낮몸통: BStr, _ 결과열쇠: BStr) -> Bool {
        fatalError("미이식: 커널값낮추기 (\(낮몸통))")
    }
    func 커널문장낮추기(_ 낮텍스트: BStr, _ 작업머리: BStr) -> (Bool, Bool) {
        fatalError("미이식: 커널문장낮추기 (\(낮텍스트))")
    }
}
