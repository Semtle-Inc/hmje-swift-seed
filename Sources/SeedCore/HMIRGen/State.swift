// HMIR생성/모형.hmje — 생성 상태와 기본 연산.
// 구조체들(상태.구조체들)은 생성기의 structs로 대신한다(문서 전체에서 한 값).

extension HMIRGenerator {

    struct HState {
        var lines: LineVec
        var tmp: Int
        var tmpPrefix: BStr
        var label: Int
        var indent: Int
        var sym: SymTab
        var ownVals: [BStr]
        var ownTypes: [BStr]
        var endCtx: J
        var ok: Bool
        var err: BStr
    }

    /// 정본: HMIR표현식결과
    struct HRes {
        var st: HState
        var val: BStr
        var ty: BStr
    }

    // 정본: HMIR생성시작
    func stateStart() -> HState {
        HState(lines: .empty(), tmp: 0, tmpPrefix: "%", label: 0, indent: 1, sym: .empty(),
               ownVals: [], ownTypes: [], endCtx: .null, ok: true, err: "")
    }

    // 정본: HMIR줄추가
    @inline(__always) func addLine(_ s: HState, _ line: BStr) -> HState {
        var r = s
        r.lines.sharedAppend(line)
        return r
    }

    // 정본: HMIR실패
    func fail(_ s: HState, _ err: BStr) -> HState {
        var r = s
        r.ok = false
        r.err = err
        return r
    }

    // 정본: HMIR다음임시
    func nextTemp(_ s: HState) -> HRes {
        var r = s
        r.tmp = s.tmp + 1
        return HRes(st: r, val: hcat(s.tmpPrefix, hDec(r.tmp)), ty: "")
    }

    // 정본: HMIR문맥변경
    func ctxChange(_ s: HState, _ indent: Int, _ sym: SymTab) -> HState {
        var r = s
        r.indent = indent
        r.sym = sym
        return r
    }

    // 정본: HMIR임시소유문맥변경
    func ownCtxChange(_ s: HState, _ vals: [BStr], _ types: [BStr]) -> HState {
        var r = s
        r.ownVals = vals
        r.ownTypes = types
        return r
    }

    // 정본: HMIR임시소유추가
    func ownAdd(_ s: HState, _ v: BStr, _ t: BStr) -> HState {
        var r = s
        r.ownVals.append(v)
        r.ownTypes.append(t)
        return r
    }

    // 정본: HMIR임시소유길이복원
    func ownRestoreLen(_ s: HState, _ n: Int) -> HState {
        var r = s
        r.ownVals = Array(s.ownVals[0..<n])
        r.ownTypes = Array(s.ownTypes[0..<n])
        return r
    }

    // 정본: HMIR끝맥락변경
    func endCtxChange(_ s: HState, _ c: J) -> HState {
        var r = s
        r.endCtx = c
        return r
    }

    // 정본: HMIR다음표지
    func nextLabel(_ s: HState, _ head: BStr) -> HRes {
        var r = s
        r.label = s.label + 1
        return HRes(st: r, val: hcat(".", head, "_", hDec(r.label)), ty: "")
    }

    // 정본: HMIR심볼추가
    @inline(__always) func symAdd(_ s: HState, _ name: BStr, _ type: BStr) -> HState {
        var r = s
        r.sym.sharedAppend(name, type)
        return r
    }

    // 정본: HMIR심볼타입
    @inline(__always) func symType(_ s: HState, _ name: BStr) -> BStr { s.sym.lookup(name) }

    // 정본: HMIR들여쓰기문자열
    func ind(_ s: HState) -> BStr {
        switch s.indent {
        case 0: return ""
        case 1: return "  "
        case 2: return "    "
        case 3: return "      "
        case 4: return "        "
        default:
            return BStr([UInt8](repeating: 32, count: s.indent * 2))
        }
    }

    // 정본: HMIR표현식오류
    func exprError(_ s: HState, _ err: BStr) -> HRes { HRes(st: fail(s, err), val: "", ty: "") }
}
