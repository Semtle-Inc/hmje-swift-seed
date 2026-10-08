// 정본: HMIR/모형.hmje, LLVM/모형.hmje — 파싱된 HMIR 문서와 함수 단위 변환 상태.

struct BKDoc {
    var 텍스트들: [BStr] = []
    var 결과표시들: [BStr] = []
    var 타입표시들: [BStr] = []
    var 몸통들: [BStr] = []
}

/// 정본: LLVM변환상태 — HMJE는 값으로 넘기고 돌려받지만, 모든 호출부가 돌려받은
/// 상태를 그대로 채택하므로 씨앗은 한 곳(BKL.st)을 제자리에서 고친다.
struct BKState {
    var 임시번호: Int = 0
    var 라벨번호: Int = 0
    var 문자열번호: Int = 0
    var 출력줄들: [BStr] = []
    var 전역줄들: [BStr] = []
    var 값값: [BStr: BStr] = [:]
    var 값내부들: [BStr: BStr] = [:]
    var 환경포인터: [BStr: BStr] = [:]
    var 환경내부들: [BStr: BStr] = [:]
    var 생성어댑터들: Set<BStr> = []
}

/// 정본: LLVM비동기문맥
struct BKAsyncCtx {
    var 손잡이: BStr = ""
    var 약속포인터: BStr = ""
    var 최종라벨: BStr = ""
    var 최종도달불가라벨: BStr = ""
    var 정리라벨: BStr = ""
    var 중단반환라벨: BStr = ""
    var 반환내부: BStr = "void"
}

/// 백엔드 한 번 실행의 전체 문맥. 정본에서 매개로 돌던 등록부 사전들(구조체들·종류기반·
/// 함수반환·전역타입·결과색인·몸통들)과 변환 상태를 한 객체에 둔다.
final class BKL {
    var st = BKState()
    var 구조체들: [BStr: BStr] = [:] { didSet { cacheValid = false } }
    var 종류기반: [BStr: BStr] = [:] { didSet { cacheValid = false } }
    var 함수반환: [BStr: BStr] = [:]
    var 전역타입: [BStr: BStr] = [:]
    var 결과색인: [BStr: Int] = [:]
    var 몸통들: [BStr] = []
    var LLVM대상ARM인가 = false
    var LLVM대상X86인가 = true

    // 등록이 끝난 뒤(구조체들·종류기반이 고정된 뒤)에만 켜는 순수 함수 캐시.
    var cacheOn = false
    var cacheValid = false
    var c내부해석: [BStr: BStr] = [:]
    var c타입LLVM: [BStr: BStr] = [:]
    var cABI크기: [BStr: Int] = [:]
    var c맹글: [BStr: BStr] = [:]

    @inline(__always) func cacheCheck() {
        if !cacheValid {
            c내부해석.removeAll(keepingCapacity: true)
            c타입LLVM.removeAll(keepingCapacity: true)
            cABI크기.removeAll(keepingCapacity: true)
            cacheValid = true
        }
    }
}
