// 정본: 변환기.hmje 앱시작

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum HMIRToLLVM {
    /// 정본 앱시작. args = [프로그램, 입력.hmir, 출력.ll, 옵션...]. 돌려주는 값 = 종료 코드.
    public static func run(_ args: [String], readFile: (String) -> [UInt8]?, writeFile: (String, [UInt8]) -> Bool) -> Int32 {
        let L = BKL()
        return L.앱시작(args.map { BStr($0) }, readFile: readFile, writeFile: writeFile)
    }
}

extension BKL {
    func 오류출력(_ s: BStr) { fputs(s.string + "\n", stderr) }

    func 앱시작(_ 인자들: [BStr], readFile: (String) -> [UInt8]?, writeFile: (String, [UInt8]) -> Bool) -> Int32 {
        if 인자들.count < 3 {
            오류출력("쓰임: 변환기 <입력.hmir> <출력.ll> [--캐시끄기] [--계측] [--target-triple T] [--posix-file-ffi] [--방출 …] [--ELF용] [--소유권검증] [--데이터루트 D]")
            return 2
        }
        var 대상트리플: BStr = "x86_64-unknown-none"
        var 포직스파일ABI = false
        var 방출모드: BStr = ""
        var ELF용 = false
        var 데이터루트들: [BStr] = []
        var 옵션번호 = 3
        while 옵션번호 < 인자들.count {
            let a = 인자들[옵션번호]
            if a == "--캐시끄기" || a == "--계측" || a == "--소유권검증" {
                // 캐시는 씨앗에 없다(출력 바이트에 영향 없음). 계측은 stderr 전용.
                // 소유권 검증은 올바른 입력에서 출력을 바꾸지 않는 검사라 옮기지 않았다.
            } else if a == "--target-triple" {
                if 옵션번호 + 1 >= 인자들.count { 오류출력("--target-triple에 값이 필요합니다"); return 2 }
                대상트리플 = 인자들[옵션번호 + 1]; 옵션번호 += 1
            } else if a == "--posix-file-ffi" {
                포직스파일ABI = true
            } else if a == "--방출" {
                if 옵션번호 + 1 >= 인자들.count { 오류출력("--방출에 값이 필요합니다"); return 2 }
                방출모드 = 인자들[옵션번호 + 1]; 옵션번호 += 1
            } else if a == "--ELF용" {
                ELF용 = true
            } else if a == "--데이터루트" {
                if 옵션번호 + 1 >= 인자들.count { 오류출력("--데이터루트에 값이 필요합니다"); return 2 }
                데이터루트들.append(인자들[옵션번호 + 1]); 옵션번호 += 1
            }
            옵션번호 += 1
        }
        if 방출모드.count > 0 || ELF용 { fatalError("미이식: --방출/--ELF용 (semtleOS방출.hmje)") }
        var 코루틴끝void = false
        if fnd(대상트리플, "windows") != nil { 코루틴끝void = true }
        var 오류들: [BStr] = []
        LLVM대상ARM인가 = false
        LLVM대상X86인가 = false
        if fnd(대상트리플, "aarch64") != nil { LLVM대상ARM인가 = true }
        if fnd(대상트리플, "arm64") != nil { LLVM대상ARM인가 = true }
        if fnd(대상트리플, "x86_64") != nil { LLVM대상X86인가 = true }
        guard let raw = readFile(인자들[1].string), raw.count > 0 else {
            오류출력(cat("읽을 수 없습니다: ", 인자들[1])); return 1
        }
        let 문서 = HMIR채널타입정규화(HMIR파싱(BStr(raw)))
        let 텍스트들 = 문서.텍스트들
        let 결과표시들 = 문서.결과표시들
        let 타입표시들 = 문서.타입표시들
        몸통들 = 문서.몸통들

        let 등록 = HMIR등록(문서)
        cacheOn = true
        cacheValid = false

        // ── 전역 초기화 지표 (worklist) ──
        var 초기화지표: Set<BStr> = []
        var 대기참조들: [BStr] = []
        for 줄3 in 텍스트들 where 줄3.hasPrefix("전역상수 ") || 줄3.hasPrefix("전역변수 ") {
            대기참조들.append(contentsOf: 참조모으기(줄3))
        }
        var 커서 = 0
        while 커서 < 대기참조들.count {
            let 참조 = 대기참조들[커서]
            if !초기화지표.contains(참조), let 지표 = 결과색인[참조] {
                초기화지표.insert(참조)
                대기참조들.append(contentsOf: 참조모으기(텍스트들[지표]))
            }
            커서 += 1
        }

        // ── 서문 ──
        st.출력줄들 = 고정서문줄들(대상트리플, 코루틴끝void)

        // ── 외부함수 선언 ──
        var 선언된심볼: Set<BStr> = []
        for (번, 심볼) in 등록.외부심볼들.enumerated() where !선언된심볼.contains(심볼) {
            선언된심볼.insert(심볼)
            let 서명 = 등록.외부서명들[번]
            let 막대자리 = fnd(서명, "|") ?? 0
            let 선반환내부 = sub(서명, 0, 막대자리)
            let 선인자직렬 = sub(서명, 막대자리 + 1, 서명.count - (막대자리 + 1))
            let 선반환LLVM = 타입LLVM(선반환내부)
            var 선유효 = true
            if 선반환LLVM.count == 0 { 오류들.append(cat("미지원: 외부함수 반환 타입 ", 선반환내부, " (", 심볼, ")")); 선유효 = false }
            var 선인자LLVM: [BStr] = []
            for (선번, a) in commaSplit(선인자직렬).enumerated() {
                let t = 타입LLVM(a)
                if t.count == 0 { 오류들.append(cat("미지원: 외부함수 인자 타입 ", a, " (", 심볼, ")")); 선유효 = false }
                if 선번 > 0 { 선인자LLVM.append(", ") }
                선인자LLVM.append(t)
            }
            var 포직스선언생략 = false
            if 포직스파일ABI && (심볼 == "hmje_posix_open" || 심볼 == "hmje_posix_openat") { 포직스선언생략 = true }
            if 선유효 && !포직스선언생략 {
                st.출력줄들.append(cat("declare ", 선반환LLVM, " @", 심볼, "(", catArr(선인자LLVM), ")"))
            }
        }
        st.출력줄들.append("")

        // ── 전역 ──
        var 전역초기뿌리들: [BStr] = []
        for 번 in 0..<텍스트들.count {
            let 전줄 = 텍스트들[번]
            if 전줄.hasPrefix("외부전역 ") {
                let 외몸 = sub(전줄, 13, 전줄.count - 13)
                if let c = fnd(외몸, ": ") {
                    let 외이름 = sub(외몸, 0, c)
                    let 외표기 = trim(sub(외몸, c + 2, 외몸.count - (c + 2)))
                    let 외내부 = 종류풀기(내부해석(외표기))
                    let 외LL = 타입LLVM(외내부)
                    if 외LL.count == 0 {
                        오류들.append(cat("미지원: 외부전역 타입 ", 외표기, " (", 외이름, ")"))
                    } else {
                        전역타입[외이름] = 외내부
                        전역타입[cat("외부전역:", 외이름)] = "1"
                        st.전역줄들.append(cat("@", 외이름, " = external global ", 외LL))
                    }
                }
            }
            if 전줄.hasPrefix("전역상수 ") || 전줄.hasPrefix("전역변수 ") {
                let 전몸통부 = sub(전줄, 13, 전줄.count - 13)
                var 전이름2: BStr = ""
                if let c = fnd(전몸통부, ": ") { 전이름2 = sub(전몸통부, 0, c) }
                if 전역타입[전이름2] == nil { 오류들.append(cat("미지원: 전역 선언 형태 ", 전줄)); continue }
                let 전내부 = 전역타입.bkg(전이름2)
                var 전값참조 = 등록.전역참조[전이름2] ?? ""
                var 전속성: [BStr] = []
                if let 대괄자리 = fnd(전값참조, " [") {
                    let 속성몸 = sub(전값참조, 대괄자리 + 2, 전값참조.count - (대괄자리 + 2) - 1)
                    전값참조 = sub(전값참조, 0, 대괄자리)
                    for p in commaSplit(속성몸) {
                        let 속성조각 = trim(p)
                        if 속성조각.hasPrefix("섹션 '") && 속성조각.hasSuffix("'") {
                            let 섹션이름 = sub(속성조각, 8, 속성조각.count - 9)
                            전속성.append(cat(", section \"", 타깃섹션이름(섹션이름, 대상트리플), "\""))
                        }
                        if 속성조각.hasPrefix("정렬 ") {
                            전속성.append(cat(", align ", trim(sub(속성조각, 7, 속성조각.count - 7))))
                        }
                    }
                }
                guard let 전값지표 = 결과색인[전값참조] else {
                    오류들.append(cat("미지원: 전역 초기값 참조 ", 전값참조, " (", 전이름2, ")")); continue
                }
                let 전값몸통 = 몸통들[전값지표]
                let 전LLVM타입 = 타입LLVM(전내부)
                var 결합종별: BStr = "constant"
                if 등록.전역종별[전이름2] == "전역변수" { 결합종별 = "global" }
                var 전값텍스트: BStr = ""
                if 전값몸통.hasPrefix("파일데이터 ") {
                    var 데이터경로 = trim(sub(전값몸통, 16, 전값몸통.count - 16))
                    if 데이터경로.hasPrefix("'") || 데이터경로.hasPrefix("\"") { 데이터경로 = sub(데이터경로, 1, 데이터경로.count - 2) }
                    let 데이터내용 = 파일데이터읽기(데이터경로, 데이터루트들)
                    if 데이터내용.count == 0 {
                        오류들.append(cat("미지원: 포함할 파일을 찾을 수 없습니다: ", 데이터경로, " (", 전이름2, ")")); continue
                    }
                    전값텍스트 = cat("c\"", 바이트이스케이프(데이터내용), "\"")
                    결합종별 = cat("private unnamed_addr ", 결합종별)
                } else if 전값몸통.hasPrefix("함수값 ") && 전내부.hasPrefix("fn<") {
                    let 저장 = st
                    st = BKState()
                    st.전역줄들 = 저장.전역줄들
                    st.생성어댑터들 = 저장.생성어댑터들
                    let ok = 함수값생성낮추기(전값몸통, 전내부, "@전역함수값")
                    let 새전역 = st.전역줄들, 새어댑터 = st.생성어댑터들
                    st = 저장
                    if !ok { 오류들.append(cat("전역 함수값의 서명이 정의와 맞지 않습니다: ", 전이름2)); continue }
                    st.전역줄들 = 새전역
                    st.생성어댑터들 = 새어댑터
                    let 전함이름 = trim(sub(전값몸통, BStr("함수값 ").count, 전값몸통.count - BStr("함수값 ").count))
                    let 전함심볼 = 함수심볼(전함이름, 함수타입인자들(전내부))
                    let 전함어댑터 = cat("hmje_closure_adapter__", 맹글이름(전함심볼))
                    전값텍스트 = cat("{ i64 ptrtoint (ptr @", 전함어댑터, " to i64), i64 0, i64 0 }")
                } else {
                    let 접힌값 = 상수접기(전값참조, 전내부, 0)
                    if 접힌값 == BKL.상수접기0나눔 {
                        오류들.append(cat("줄 ", num(전값지표 + 1), ": 0으로 나눌 수 없습니다. (", 전이름2, ")")); continue
                    }
                    if 접힌값.count == 0 {
                        오류들.append(cat("미지원: 전역 초기값 형태 ", 전값몸통, " (", 전이름2, ")")); continue
                    }
                    전값텍스트 = 접힌값
                    전역초기뿌리들.append(전값참조)
                }
                st.전역줄들.append(cat(전역심볼이름(전이름2), " = ", 결합종별, " ", 전LLVM타입, " ", 전값텍스트, catArr(전속성)))
            }
        }
        st.전역줄들.append(contentsOf: 전역문자열데이터모으기(전역초기뿌리들))

        // ── 메인 몸통 지표 ──
        var 메인지표들: [Int] = []
        var 함수안2 = false
        for 번 in 0..<텍스트들.count {
            let 몸줄 = 텍스트들[번]
            if 함수안2 {
                if 몸줄 == "함수끝" { 함수안2 = false }
                continue
            }
            if 몸줄.hasPrefix("함수 ") || 몸줄.hasPrefix("비동기함수 ") { 함수안2 = true; continue }
            var 메인감 = true
            if 몸줄.count == 0 { 메인감 = false }
            if 몸줄.hasPrefix("모듈") || 몸줄.hasPrefix("타입 ") || 몸줄.hasPrefix("종류 ") || 몸줄.hasPrefix("외부전역 ") { 메인감 = false }
            if 몸줄.hasPrefix("전역상수 ") || 몸줄.hasPrefix("전역변수 ") || 몸줄.hasPrefix("외부함수 ") || 몸줄 == "함수끝" { 메인감 = false }
            let 몸결과 = 결과표시들[번]
            if 몸결과.count > 0 && 초기화지표.contains(몸결과) { 메인감 = false }
            if 메인감 { 메인지표들.append(번) }
        }

        // ── 함수·메인 낮추기 ──
        for 전함이름 in 등록.전역이름들 {
            let 전함내부 = 전역타입.bkg(전함이름)
            if 전함내부.hasPrefix("fn<") || 전함내부.hasPrefix("asyncfn<") {
                st.환경포인터[cat("@전역함수:", 전함이름)] = 전역심볼이름(전함이름)
                st.환경내부들[cat("@전역함수:", 전함이름)] = 전함내부
            }
        }
        let 작업수 = 등록.함수시작들.count + 1
        var 작업번 = 0
        작업반복: while 작업번 < 작업수 {
            defer { 작업번 += 1 }
            let 함수출력시작 = st.출력줄들.count
            var 함수실패 = false
            var 현함수이름: BStr = "메인"
            let 작업머리 = cat(num(작업번), "/")
            var 몸지표들: [Int] = []
            var 현반환내부: BStr = "void"
            var 현채널참조표기: BStr = ""
            var 현채널참조내부: BStr = ""
            var 현비동기임 = false
            var 진입색인 = 0
            var 종결됨 = false
            if 작업번 < 등록.함수시작들.count {
                let 시작지표 = 등록.함수시작들[작업번]
                let 머리줄 = 텍스트들[시작지표]
                var 머리접두길이 = 7
                if 머리줄.hasPrefix("비동기함수 ") { 현비동기임 = true; 머리접두길이 = BStr("비동기함수 ").count }
                if 현비동기임 { fatalError("미이식: 비동기 함수 머리 (변환기.hmje)") }
                let 머리2 = sub(머리줄, 머리접두길이, 머리줄.count - 머리접두길이)
                let 머여는자리 = fnd(머리2, "(") ?? 0
                let 머이름 = sub(머리2, 0, 머여는자리)
                현함수이름 = 머이름
                let 머닫는자리 = fnd(머리2, ")") ?? 0
                let 머매개부 = sub(머리2, 머여는자리 + 1, 머닫는자리 - (머여는자리 + 1))
                if let 머화살자리 = fnd(머리2, " -> ") {
                    let 머반환표기 = trim(sub(머리2, 머화살자리 + 4, 머리2.count - (머화살자리 + 4)))
                    var 머채널참조임 = false
                    if 머이름.hasPrefix("HMJE채널") && 머이름.hasSuffix("참조") {
                        let 머채널구조 = sub(머이름, 0, 머이름.count - BStr("참조").count)
                        구조체들[cat("channel:", 맹글이름(머반환표기))] = 머채널구조
                        현반환내부 = cat("struct:", 머채널구조)
                        현채널참조표기 = 머반환표기
                        현채널참조내부 = 현반환내부
                        머채널참조임 = true
                    }
                    if !머채널참조임 { 현반환내부 = 내부해석(머반환표기) }
                }
                var 머매이름들: [BStr] = [], 머매내부들: [BStr] = []
                for 머조각 in commaSplit(머매개부) {
                    let 머콜론자리 = fnd(머조각, ": ") ?? 0
                    var 머매이름 = sub(머조각, 0, 머콜론자리)
                    if 머매이름.hasPrefix("소비하는 ") { 머매이름 = sub(머매이름, 13, 머매이름.count - 13) }
                    let 머매표기 = trim(sub(머조각, 머콜론자리 + 2, 머조각.count - (머콜론자리 + 2)))
                    var 머매내부 = 내부해석(머매표기)
                    if 현채널참조표기.count > 0 && 머매표기 == 현채널참조표기 { 머매내부 = 현채널참조내부 }
                    머매이름들.append(머매이름)
                    머매내부들.append(머매내부)
                }
                let 머심볼 = 함수심볼(머이름, 머매내부들)
                var 머반환간접 = false
                if 현반환내부 != "void" && ABI간접(현반환내부) { 머반환간접 = true }
                var 머반환LLVM = 타입LLVM(현반환내부)
                if 머반환LLVM.count == 0 {
                    오류들.append(cat("미지원: 함수 반환 타입 ", 현반환내부, " (", 머이름, ")")); continue 작업반복
                }
                var 머매LLVM: [BStr] = []
                if 머반환간접 {
                    머매LLVM.append(cat(머반환LLVM, "* sret(", 머반환LLVM, ") %__hmje_return"))
                    머반환LLVM = "void"
                }
                for (i, 머낱내부) in 머매내부들.enumerated() {
                    var 머낱LLVM = 타입LLVM(머낱내부)
                    if 머낱LLVM.count == 0 { 오류들.append(cat("미지원: 함수 매개 타입 ", 머낱내부, " (", 머이름, ")")); 함수실패 = true }
                    if ABI간접(머낱내부) { 머낱LLVM = cat(머낱LLVM, "*") }
                    if 머매LLVM.count > 0 { 머매LLVM.append(", ") }
                    머매LLVM.append(cat(머낱LLVM, " %", 맹글이름(머매이름들[i])))
                }
                if 함수실패 { continue 작업반복 }
                줄(cat("define ", 머반환LLVM, " @", 머심볼, "(", catArr(머매LLVM), ") noredzone {"))
                줄("entry:")
                진입색인 = st.출력줄들.count - 1
                for (i, 슬매내부) in 머매내부들.enumerated() {
                    let 슬열쇠 = cat(작업머리, 머매이름들[i])
                    if ABI간접(슬매내부) {
                        st.환경포인터[슬열쇠] = cat("%", 맹글이름(머매이름들[i]))
                        st.환경내부들[슬열쇠] = 종류풀기(슬매내부)
                    } else {
                        let 슬LL = 타입LLVM(슬매내부)
                        let 슬롯 = 새임시()
                        줄(cat("  ", 슬롯, " = alloca ", 슬LL))
                        줄(cat("  store ", 슬LL, " %", 맹글이름(머매이름들[i]), ", ", 슬LL, "* ", 슬롯))
                        st.환경포인터[슬열쇠] = 슬롯
                        st.환경내부들[슬열쇠] = 종류풀기(슬매내부)
                    }
                }
                var 몸번 = 시작지표 + 1
                while 몸번 < 텍스트들.count && 텍스트들[몸번] != "함수끝" {
                    몸지표들.append(몸번); 몸번 += 1
                }
            } else {
                줄("define i32 @main() noredzone {")
                줄("entry:")
                진입색인 = st.출력줄들.count - 1
                현반환내부 = "@메인"
                몸지표들 = 메인지표들
            }

            // ── 명령 낮추기 ──
            for 낮지표 in 몸지표들 {
                let 낮텍스트 = 텍스트들[낮지표]
                let 낮결과 = 결과표시들[낮지표]
                let 낮타입표시 = 타입표시들[낮지표]
                let 낮몸통 = 몸통들[낮지표]
                var 처리됨 = false
                if 낮텍스트.count == 0 || 낮텍스트 == "위험구역" || 낮텍스트 == "위험구역끝" { 처리됨 = true }
                let 주석들: [(BStr, BStr, Int)] = [("주소고정끝 ", "  ; hmje.unpin ", 16), ("주소고정 ", "  ; hmje.pin ", 13),
                    ("빌림시작 ", "  ; hmje.borrow.begin ", 13), ("빌림끝 ", "  ; hmje.borrow.end ", 10),
                    ("소유권이동 ", "  ; hmje.move ", 16), ("소유권해제 ", "  ; hmje.release ", 16),
                    ("소유권잊음 ", "  ; hmje.forget ", 16), ("소유권넘김 ", "  ; hmje.transfer ", 16)]
                for (머리, 주석, 길이) in 주석들 where !처리됨 && 낮텍스트.hasPrefix(머리) {
                    줄(cat(주석, trim(sub(낮텍스트, 길이, 낮텍스트.count - 길이))))
                    처리됨 = true
                }
                if !처리됨 && 낮텍스트.hasSuffix(":") {
                    let 낮라벨 = 라벨이름(낮텍스트)
                    if !종결됨 { 줄(cat("  br label %", 낮라벨)) }
                    줄(cat(낮라벨, ":"))
                    종결됨 = false
                    처리됨 = true
                }
                if !처리됨 && 종결됨 { 처리됨 = true }
                if !처리됨 {
                    (처리됨, 종결됨) = 비동기명령낮추기(낮결과, 낮텍스트, 낮몸통, 작업머리, 현비동기임, 종결됨)
                }
                if !처리됨 { 처리됨 = 값명령낮추기(낮결과, 낮타입표시, 낮몸통, 작업머리, 진입색인) }
                if !처리됨 && 낮결과.count > 0 { 처리됨 = 커널값낮추기(낮몸통, cat(작업머리, 낮결과)) }
                if !처리됨 {
                    (처리됨, 종결됨) = 문장명령낮추기(낮결과, 낮텍스트, 작업머리, 진입색인, 종결됨)
                }
                if !처리됨 && 낮결과.count == 0 {
                    let r = 커널문장낮추기(낮텍스트, 작업머리)
                    처리됨 = r.0
                }
                if !처리됨 {
                    let 낮결과내부 = 종류풀기(내부해석(낮타입표시))
                    if 낮몸통.hasPrefix("나머지 ") && (낮결과내부 == "f32" || 낮결과내부 == "f64") {
                        오류들.append(cat("줄 ", num(낮지표 + 1), ": % 나머지 연산은 정수 타입에만 사용할 수 있습니다. (", 현함수이름, ")"))
                    } else {
                        오류들.append(cat("미지원(줄 ", num(낮지표 + 1), ", ", 현함수이름, "): ", 낮텍스트))
                    }
                    함수실패 = true
                    break
                }
            }
            if 함수실패 {
                st.출력줄들.removeSubrange(함수출력시작...)
                continue 작업반복
            }
            진입할당정리(진입색인)
            if 작업번 < 등록.함수시작들.count {
                if !종결됨 {
                    if 현반환내부 == "void" {
                        줄("  ret void")
                    } else {
                        오류들.append(cat("미지원: 함수가 반환 없이 끝났습니다 (", 현함수이름, ")"))
                        st.출력줄들.removeSubrange(함수출력시작...)
                        continue 작업반복
                    }
                }
                줄("}")
                줄("")
            } else {
                if 종결됨 {
                    st.라벨번호 += 1
                    줄(cat("main.end.", num(st.라벨번호), ":"))
                }
                줄("  ret i32 0")
                줄("}")
            }
        }

        if 오류들.count > 0 {
            _ = writeFile(인자들[2].string, 파일내용(st.출력줄들, st.전역줄들))
            for e in 오류들 { 오류출력(e) }
            오류출력(cat("미지원 ", num(오류들.count), "건"))
            return 3
        }
        if 포직스파일ABI { 포직스파일ABI추가() }
        if !writeFile(인자들[2].string, 파일내용(st.출력줄들, st.전역줄들)) {
            오류출력(cat("LLVM 출력 실패: ", 인자들[2])); return 1
        }
        return 0
    }
}
