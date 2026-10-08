// 타입 AST + HMIR 생성 단계(M4-hmirgen).
// 정본: 컴파일러.hmje 앱시작의 준비 뒤 구간 — 검사구조체환경/검사함수환경/검사문서생성(타입검사/),
// HMIR증분설정(--캐시끄기: 증분 끔), HMIR문서생성(HMIR생성/), HMIR파일쓰기.

public final class HMIRGenerator {
    public typealias J = JSONValue

    /// 문서 구조체 환경(struct_defs)과 함수 환경(functions). 생성 내내 바뀌지 않는다.
    var structs: J = .null
    var funcs: J = .null
    var structIndex: [BStr: Int] = [:]
    var structVals: [J] = []
    var funcIndex: [BStr: Int] = [:]
    var funcVals: [J] = []

    // HMIR생성/타입.hmje 전역 등록부(각 32칸 상한 그대로)
    var surfaceDynArrays: [BStr] = []
    var fnDisplayNames: [BStr] = []
    var fnDisplayValues: [BStr] = []

    public init() {}

    /// 정본: 검사문서생성 — 준비 문서에서 typed 문서를 만든다.
    public func typedDocument(prepared: J) -> J { tcDocument(prepared) }

    /// typed 문서 → HMIR 줄들. 실패하면 오류 문자열.
    public func generate(typed: J) -> Result<[BStr], HMIRGenError> {
        guard let st = typed.field("statements"), let sd = typed.field("struct_defs"), let fn = typed.field("functions") else {
            return .failure(HMIRGenError(message: "typed AST 환경을 만들지 못했습니다"))
        }
        setEnvironment(structs: sd, funcs: fn)
        let s = documentGenerate(statements: st)
        if !s.ok { return .failure(HMIRGenError(message: s.err.string)) }
        return .success(s.lines.array)
    }

    func setEnvironment(structs sd: J, funcs fn: J) {
        structs = sd
        funcs = fn
        structIndex = [:]
        structVals = sd.objectValues
        for (i, k) in sd.objectKeys.enumerated() where structIndex[k] == nil { structIndex[k] = i }
        funcIndex = [:]
        funcVals = fn.objectValues
        for (i, k) in fn.objectKeys.enumerated() where funcIndex[k] == nil { funcIndex[k] = i }
    }

    /// AST객체필드(상태.구조체들, 이름)
    @inline(__always) func structFields(_ name: BStr) -> J {
        if let i = structIndex[name] { return structVals[i] }
        return .null
    }

    /// AST객체필드(함수들, 이름)
    @inline(__always) func funcOverloads(_ name: BStr) -> J {
        if let i = funcIndex[name] { return funcVals[i] }
        return .null
    }
}

public struct HMIRGenError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// 준비 문서 → (typed 문서, HMIR 줄들). finishpoint 구동기가 쓴다.
public func generateHMIR(prepared: JSONValue) -> (typed: JSONValue, lines: Result<[BStr], HMIRGenError>) {
    let g = HMIRGenerator()
    let typed = g.typedDocument(prepared: prepared)
    return (typed, g.generate(typed: typed))
}

/// 정본: HMIR파일쓰기 — 줄마다 "\n"을 붙여 잇는다.
public func serializeHMIR(_ lines: [BStr]) -> [UInt8] {
    var total = 0
    for l in lines { total += l.count + 1 }
    var out: [UInt8] = []
    out.reserveCapacity(total)
    for l in lines {
        l.withBytes { out.append(contentsOf: $0) }
        out.append(10)
    }
    return out
}
