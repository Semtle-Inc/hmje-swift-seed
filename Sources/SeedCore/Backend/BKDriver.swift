// 정본: 변환기.hmje(앱시작), HMIR/파서.hmje, HMIR/등록부.hmje, LLVM/출력기.hmje

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension BKL {
    // 정본: HMIR파싱
    func HMIR파싱(_ 내용: BStr) -> BKDoc {
        var d = BKDoc()
        for 원 in splitS(내용, "\n") {
            let 줄 = trim(원)
            d.텍스트들.append(줄)
            var 결과표시: BStr = "", 타입표시: BStr = "", 몸통 = 줄
            if 줄.hasPrefix("%") {
                if let c = fnd(줄, ": "), let e = fnd(줄, " = ") {
                    결과표시 = sub(줄, 0, c)
                    타입표시 = trim(sub(줄, c + 2, e - (c + 2)))
                    몸통 = sub(줄, e + 3, 줄.count - (e + 3))
                }
            }
            d.결과표시들.append(결과표시)
            d.타입표시들.append(타입표시)
            d.몸통들.append(몸통)
        }
        return d
    }

    // 정본: 문자열모두바꾸기
    func 문자열모두바꾸기(_ 원문: BStr, _ 찾을말: BStr, _ 바꿀말: BStr) -> BStr {
        if 찾을말.count == 0 { return 원문 }
        guard fnd(원문, 찾을말) != nil else { return 원문 }
        var 남음 = 원문
        var parts: [BStr] = []
        while true {
            if let 자리 = fnd(남음, 찾을말) {
                parts.append(sub(남음, 0, 자리)); parts.append(바꿀말)
                let 다음 = 자리 + 찾을말.count
                남음 = sub(남음, 다음, 남음.count - 다음)
            } else { parts.append(남음); break }
        }
        return catArr(parts)
    }

    // 정본: HMIR채널타입정규화
    func HMIR채널타입정규화(_ 문서: BKDoc) -> BKDoc {
        var d = 문서
        var 사람표기들: [BStr] = [], 내부표기들: [BStr] = []
        for 줄 in d.텍스트들 where 줄.hasPrefix("함수 HMJE채널") {
            if let 참조자리3 = fnd(줄, "참조(") {
                let 이름시작 = BStr("함수 ").count
                let 구조이름 = sub(줄, 이름시작, 참조자리3 - 이름시작)
                if let c = fnd(줄, ": "), let e = fnd(줄, ")") {
                    사람표기들.append(sub(줄, c + 2, e - (c + 2)))
                    내부표기들.append(cat("struct:", 구조이름))
                }
            }
        }
        for 표번 in 0..<사람표기들.count {
            for 번 in 0..<d.텍스트들.count {
                d.텍스트들[번] = 문자열모두바꾸기(d.텍스트들[번], 사람표기들[표번], 내부표기들[표번])
                d.타입표시들[번] = 문자열모두바꾸기(d.타입표시들[번], 사람표기들[표번], 내부표기들[표번])
                d.몸통들[번] = 문자열모두바꾸기(d.몸통들[번], 사람표기들[표번], 내부표기들[표번])
            }
        }
        return d
    }

    struct 등록부 {
        var 외부심볼들: [BStr] = []
        var 외부서명들: [BStr] = []
        var 전역이름들: [BStr] = []
        var 전역종별: [BStr: BStr] = [:]
        var 전역참조: [BStr: BStr] = [:]
        var 함수시작들: [Int] = []
    }

    // 정본: HMIR등록 — 구조체들·종류기반·함수반환·결과색인·전역타입은 self에 채운다.
    func HMIR등록(_ 문서: BKDoc) -> 등록부 {
        var r = 등록부()
        let 텍스트들 = 문서.텍스트들
        var 함수안임 = false
        for 선줄 in 텍스트들 where 선줄.hasPrefix("함수 ") {
            if let 선생성위치 = fnd(선줄, "동적배열생성("), let 선반환위치 = fnd(선줄, " -> ") {
                let 선반환시작 = 선반환위치 + 4
                let 선반환표기 = trim(sub(선줄, 선반환시작, 선줄.count - 선반환시작))
                if 선반환표기.hasSuffix("의 배열") {
                    let 선원소표기 = sub(선반환표기, 0, 선반환표기.count - BStr("의 배열").count)
                    let 선접두 = sub(선줄, 7, 선생성위치 - 7)
                    구조체들[cat("dynamic-display:", 선원소표기)] = 선접두
                }
            }
        }
        for 채널줄 in 텍스트들 {
            if 채널줄.hasPrefix("함수 HMJE채널") {
                if fnd(채널줄, "참조(") != nil {
                    let 채널함몸 = sub(채널줄, 7, 채널줄.count - 7)
                    let 채널참조자리2 = fnd(채널함몸, "참조(") ?? 0
                    let 채널실구이름 = sub(채널함몸, 0, 채널참조자리2)
                    if let c = fnd(채널함몸, ": "), let e = fnd(채널함몸, ")") {
                        let 채널사람표기 = sub(채널함몸, c + 2, e - (c + 2))
                        구조체들[cat("channel:", 맹글이름(채널사람표기))] = 채널실구이름
                    }
                }
            }
            let 선택등호묶음 = fnd(채널줄, " = 구조체 {")
            let 선택값표시: BStr = ", 값: "
            let 선택값묶음 = fnd(채널줄, 선택값표시)
            if 채널줄.hasPrefix("타입 ") {
                if let 선택등호자리 = 선택등호묶음, let 선택값자리 = 선택값묶음 {
                    let 선택구이름 = trim(sub(채널줄, 7, 선택등호자리 - 7))
                    if 선택구이름.hasSuffix("선택값") {
                        let 선택값시작 = 선택값자리 + 선택값표시.count
                        let 선택값표기 = trim(sub(채널줄, 선택값시작, 채널줄.count - 선택값시작 - 2))
                        let 선택값내부 = 내부해석(선택값표기)
                        구조체들[cat("optional:", 선택값내부)] = 선택구이름
                        구조체들[cat("optional-display:", 선택값표기)] = 선택구이름
                        if 선택값표기.hasSuffix("개의 고정배열") { 구조체들[선택값표기] = 선택구이름 }
                    }
                }
            }
        }
        for 번 in 0..<텍스트들.count {
            let 줄2 = 텍스트들[번]
            let 결과표시2 = 문서.결과표시들[번]
            if 결과표시2.count > 0 { 결과색인[결과표시2] = 번 }
            if 함수안임 {
                if 줄2 == "함수끝" { 함수안임 = false }
                continue
            }
            if 줄2.hasPrefix("타입 ") {
                if let 등호자리2 = fnd(줄2, " = ") {
                    let 타입이름 = trim(sub(줄2, 7, 등호자리2 - 7))
                    let 정의부 = sub(줄2, 등호자리2 + 3, 줄2.count - (등호자리2 + 3))
                    if 정의부.hasPrefix("구조체 {") {
                        let 여닫이제거 = trim(sub(정의부, 11, 정의부.count - 12))
                        var 필드직렬: [BStr] = []
                        var 마지막필내부: BStr = "", 마지막필표기: BStr = ""
                        var 필번 = 0
                        for 필드조각 in commaSplit(여닫이제거) {
                            if let 필콜론자리 = fnd(필드조각, ": ") {
                                let 필이름 = sub(필드조각, 0, 필콜론자리)
                                let 필타입표기 = trim(sub(필드조각, 필콜론자리 + 2, 필드조각.count - (필콜론자리 + 2)))
                                let 필내부 = 내부해석(필타입표기)
                                마지막필내부 = 필내부; 마지막필표기 = 필타입표기
                                if 필번 > 0 { 필드직렬.append(";") }
                                필드직렬.append(필이름); 필드직렬.append(":"); 필드직렬.append(필내부)
                            }
                            필번 += 1
                        }
                        구조체들[타입이름] = catArr(필드직렬)
                        if 타입이름.hasSuffix("선택값") && 마지막필내부.count > 0 {
                            구조체들[cat("optional:", 마지막필내부)] = 타입이름
                            구조체들[cat("optional-display:", 마지막필표기)] = 타입이름
                            if 마지막필표기.hasSuffix("개의 고정배열") { 구조체들[마지막필표기] = 타입이름 }
                        }
                        if 타입이름.hasPrefix("함수값") && 타입이름.hasSuffix("동적배열형") {
                            구조체들["dynamic-function"] = sub(타입이름, 0, 타입이름.count - BStr("동적배열형").count)
                        }
                        if 타입이름.hasPrefix("함수값") && 타입이름.hasSuffix("선택값") {
                            구조체들["optional-function"] = sub(타입이름, 0, 타입이름.count - BStr("선택값").count)
                        }
                    }
                }
            }
            if 줄2.hasPrefix("종류 ") {
                if let 등호자리3 = fnd(줄2, " = ") {
                    let 종류이름 = trim(sub(줄2, 7, 등호자리3 - 7))
                    let 기반부 = trim(sub(줄2, 등호자리3 + 3, 줄2.count - (등호자리3 + 3)))
                    var 기반표기 = 기반부
                    if let p = fnd(기반부, " {") { 기반표기 = trim(sub(기반부, 0, p)) }
                    let 종류내부기반 = 내부타입(기반표기)
                    종류기반[종류이름] = 종류내부기반
                    구조체들[cat("enum:", 종류이름)] = 종류내부기반
                }
            }
            if 줄2.hasPrefix("외부함수 ") || 줄2.hasPrefix("함수 ") || 줄2.hasPrefix("비동기함수 ") {
                var 머리: BStr
                var 외부임 = false
                if 줄2.hasPrefix("외부함수 ") { 외부임 = true; 머리 = sub(줄2, 13, 줄2.count - 13) }
                else if 줄2.hasPrefix("함수 ") { 머리 = sub(줄2, 7, 줄2.count - 7) }
                else { 머리 = sub(줄2, 16, 줄2.count - 16) }
                if let 여는자리 = fnd(머리, "(") {
                    let 함이름 = sub(머리, 0, 여는자리)
                    let 닫는자리 = fnd(머리, ")") ?? 0
                    let 매개부 = sub(머리, 여는자리 + 1, 닫는자리 - (여는자리 + 1))
                    var 반환내부: BStr = "void"
                    if let 화살자리 = fnd(머리, " -> ") {
                        let 반환표기 = trim(sub(머리, 화살자리 + 4, 머리.count - (화살자리 + 4)))
                        let 생성꼬리: BStr = "동적배열생성", 배열표기꼬리: BStr = "의 배열"
                        var 생성배열임 = false
                        if 함이름.hasSuffix(생성꼬리) && 반환표기.hasSuffix(배열표기꼬리) {
                            let 생성원소표기 = sub(반환표기, 0, 반환표기.count - 배열표기꼬리.count)
                            let 생성원소내부 = 내부해석(생성원소표기)
                            let 생성접두 = sub(함이름, 0, 함이름.count - 생성꼬리.count)
                            구조체들[cat("dynamic:", 생성원소내부)] = 생성접두
                            반환내부 = cat("struct:", 생성접두, "동적배열형")
                            생성배열임 = true
                        }
                        if !생성배열임 { 반환내부 = 내부해석(반환표기) }
                    }
                    var 인자직렬: [BStr] = []
                    var 매번 = 0
                    for 매개조각 in commaSplit(매개부) {
                        if let 매콜론자리 = fnd(매개조각, ": ") {
                            let 매타입표기 = trim(sub(매개조각, 매콜론자리 + 2, 매개조각.count - (매콜론자리 + 2)))
                            if 함이름.hasPrefix("HMJE채널") && 함이름.hasSuffix("참조") {
                                let 채널구이름 = sub(함이름, 0, 함이름.count - BStr("참조").count)
                                구조체들[cat("channel:", 맹글이름(매타입표기))] = 채널구이름
                            }
                            if 매번 > 0 { 인자직렬.append(",") }
                            인자직렬.append(내부해석(매타입표기))
                        }
                        매번 += 1
                    }
                    let 직렬 = catArr(인자직렬)
                    함수반환[cat(함이름, "|", 직렬)] = 반환내부
                    if 외부임 {
                        r.외부심볼들.append(함이름)
                        r.외부서명들.append(cat(반환내부, "|", 직렬))
                    } else {
                        r.함수시작들.append(번)
                        함수안임 = true
                    }
                }
            }
            if 줄2.hasPrefix("전역상수 ") || 줄2.hasPrefix("전역변수 ") {
                let 종별 = sub(줄2, 0, 12)
                let 몸통부 = sub(줄2, 13, 줄2.count - 13)
                if let 전콜론자리 = fnd(몸통부, ": "), let 전등호자리 = fnd(몸통부, " = ") {
                    let 전이름 = sub(몸통부, 0, 전콜론자리)
                    let 전타입표기 = trim(sub(몸통부, 전콜론자리 + 2, 전등호자리 - (전콜론자리 + 2)))
                    let 전값부 = trim(sub(몸통부, 전등호자리 + 3, 몸통부.count - (전등호자리 + 3)))
                    r.전역이름들.append(전이름)
                    전역타입[전이름] = 종류풀기(내부해석(전타입표기))
                    r.전역종별[전이름] = 종별
                    r.전역참조[전이름] = 전값부
                }
            }
        }
        return r
    }

    // 정본: 진입할당정리
    func 진입할당정리(_ 진입색인: Int) {
        var 할당줄들: [BStr] = [], 본문줄들: [BStr] = []
        var 번 = 진입색인 + 1
        while 번 < st.출력줄들.count {
            let l = st.출력줄들[번]
            if fnd(l, " = alloca ") != nil { 할당줄들.append(l) } else { 본문줄들.append(l) }
            번 += 1
        }
        st.출력줄들.removeSubrange((진입색인 + 1)...)
        st.출력줄들.append(contentsOf: 할당줄들.reversed())
        st.출력줄들.append(contentsOf: 본문줄들)
    }

    // 정본: 고정서문줄들
    func 고정서문줄들(_ 대상트리플: BStr, _ 코루틴끝void: Bool) -> [BStr] {
        var o: [BStr] = ["; ModuleID = 'hunminjeongeum'", cat("target triple = \"", 대상트리플, "\"")]
        o += ["declare void @llvm.lifetime.start.p0(i64, ptr)", "declare void @llvm.lifetime.end.p0(i64, ptr)",
              "declare token @llvm.coro.id(i32, i8*, i8*, i8*)", "declare i64 @llvm.coro.size.i64()",
              "declare i8* @llvm.coro.begin(token, i8*)", "declare token @llvm.coro.save(i8*)",
              "declare i8 @llvm.coro.suspend(token, i1)", "declare i1 @llvm.coro.done(i8*)",
              "declare void @llvm.coro.resume(i8*)", "declare i8* @llvm.coro.promise(i8*, i32, i1)",
              "declare i8* @llvm.coro.free(token, i8*)", "declare void @llvm.coro.destroy(i8*)"]
        o.append(코루틴끝void ? "declare void @llvm.coro.end(i8*, i1, token)" : "declare i1 @llvm.coro.end(i8*, i1, token)")
        o += ["declare void @llvm.trap()", "declare i64 @hmje_async_event_create()",
              "declare i32 @hmje_async_event_is_ready(i64)", "declare i32 @hmje_async_event_take_u64(i64, i64*, i32*)",
              "declare i32 @hmje_async_event_abandon(i64)", "declare void @hmje_async_handle_set_blocked(i8*, i32)",
              "declare i32 @hmje_async_handle_is_blocked(i8*)", "declare void @hmje_async_handle_request_cancel(i8*)",
              "declare i32 @hmje_async_handle_is_cancelled(i8*)", "declare void @hmje_async_cancellation_shield_enter(i8*)",
              "declare void @hmje_async_cancellation_shield_exit(i8*)", "declare void @hmje_async_handle_set_failure(i8*, i64)",
              "declare i64 @hmje_async_handle_failure(i8*)", "declare i64 @hmje_async_handle_take_failure(i8*)",
              "declare i64 @hmje_async_deadline_begin(i64, i8*)", "declare void @hmje_async_deadline_end(i64)",
              "declare void @hmje_async_deadline_cancel_for_handle(i8*)", "declare void @hmje_async_handle_forget(i8*)",
              "declare i8* @hmje_async_group_create()", "declare void @hmje_async_group_add(i8*, i8*)",
              "declare i32 @hmje_async_group_poll(i8*, i8*)", "declare void @hmje_async_group_finish(i8*, i8*)",
              "declare void @hmje_async_unstructured_add(i8*, i64, i64)", "declare i32 @hmje_async_unstructured_poll()",
              "declare void @hmje_async_wait_for_wake()",
              "declare float @llvm.vector.reduce.fadd.v16f32(float, <16 x float>)",
              "declare float @llvm.vector.reduce.fadd.v8f32(float, <8 x float>)",
              "declare float @llvm.vector.reduce.fmax.v16f32(<16 x float>)",
              "declare float @llvm.vector.reduce.fmax.v32f32(<32 x float>)",
              "declare <32 x float> @llvm.fabs.v32f32(<32 x float>)",
              "declare <32 x float> @llvm.round.v32f32(<32 x float>)",
              "declare i32 @llvm.vector.reduce.add.v16i32(<16 x i32>)"]
        return o
    }

    // 정본: 포직스파일ABI추가
    func 포직스파일ABI추가() {
        st.출력줄들 += ["", "", "declare i32 @open(i8*, i32, ...)", "declare i32 @openat(i32, i8*, i32, ...)", "",
            "define i32 @hmje_posix_open(i64 %path, i32 %flags, i32 %mode) {", "entry:",
            "  %path.ptr = inttoptr i64 %path to i8*",
            "  %result = call i32 (i8*, i32, ...) @open(i8* %path.ptr, i32 %flags, i32 %mode)",
            "  ret i32 %result", "}", "",
            "define i32 @hmje_posix_openat(i32 %directory, i64 %path, i32 %flags, i32 %mode) {", "entry:",
            "  %path.ptr = inttoptr i64 %path to i8*",
            "  %result = call i32 (i32, i8*, i32, ...) @openat(i32 %directory, i8* %path.ptr, i32 %flags, i32 %mode)",
            "  ret i32 %result", "}"]
    }

    // 정본: 파일로쓰기 (내용 조립만; 원자 교체는 호출자)
    func 파일내용(_ 줄들: [BStr], _ 전역줄들: [BStr]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(64 << 20)
        var 빈줄지남 = false
        for l in 줄들 {
            l.withBytes { out.append(contentsOf: $0) }
            out.append(10)
            if !빈줄지남 && l.count == 0 {
                빈줄지남 = true
                for g in 전역줄들 { g.withBytes { out.append(contentsOf: $0) }; out.append(10) }
                if 전역줄들.count > 0 { out.append(10) }
            }
        }
        return out
    }

    // 정본: 변환기파일데이터읽기 (파일전체읽기: 실패·빈 파일은 "")
    func 파일데이터읽기(_ 경로: BStr, _ 루트들: [BStr]) -> BStr {
        func 읽기(_ p: BStr) -> BStr {
            guard let f = fopen(p.string, "rb") else { return "" }
            defer { fclose(f) }
            var a: [UInt8] = []
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = fread(&buf, 1, buf.count, f)
                if n <= 0 { break }
                a.append(contentsOf: buf[0..<n])
            }
            return BStr(a)
        }
        let 그대로 = 읽기(경로)
        if 그대로.count > 0 { return 그대로 }
        for 루트 in 루트들 {
            var 후보 = 루트
            if !후보.hasSuffix("/") { 후보 = cat(후보, "/") }
            let 내용 = 읽기(cat(후보, 경로))
            if 내용.count > 0 { return 내용 }
        }
        return ""
    }

    // 정본: 변환기타깃섹션이름
    func 타깃섹션이름(_ 섹션: BStr, _ 트리플: BStr) -> BStr {
        if fnd(트리플, "apple") != nil {
            if 섹션 == ".rodata" { return "__TEXT,__const" }
            if 섹션 == ".data" { return "__DATA,__data" }
            return 섹션
        }
        if fnd(트리플, "windows") != nil {
            if 섹션 == ".rodata" { return ".rdata" }
        }
        return 섹션
    }
}
