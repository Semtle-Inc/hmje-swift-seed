// finishpoint — 씨앗 컴파일러의 최상위 입구.
//
// 이름은 2022년 Swift로 쓴 첫 훈민정음 인터프리터(Honnmin V4 ContentView.swift)의
// `finishpoint(text:)`에서 왔다. 그 함수는 코드를 종결 부호 마침표로 문장마다 나누고,
// 문장을 하나씩 실행해 결과를 돌려주는 인터프리터 전체의 입구였다. 이 함수도 같은 자리에
// 선다. 다만 문장을 실행하지 않고, 기계가 실행할 LLVM IR로 번역한다.
//
// 흐름은 자립 컴파일러의 두 도구를 그대로 잇는다.
//   1. `컴파일러`(컴파일러.hmje 앱시작): 적재 → 준비 → 타입 AST → HMIR   (prepareDocument, generateHMIR)
//   2. `hmir을llvm으로`(변환기.hmje): HMIR → LLVM IR                       (HMIRToLLVM)
// 각 단계는 stage0 산출물과 바이트 단위로 같음이 오라클로 검증돼 있다(docs/porting.md).

import Foundation

public struct FinishpointOptions {
    /// 백엔드에 넘길 인자. 정본 제품조정기가 posix-host-exe에서 쓰는 값이 기본이다.
    public var backendFlags: [String] = ["--target-triple", "arm64-apple-darwin", "--posix-file-ffi", "--캐시끄기"]
    /// 중간 HMIR을 프론트엔드 출력 경로(인자 5번)에 실제로 쓸지.
    public var writeHMIR: Bool = true
    public init() {}
}

public enum FinishpointError: Error, CustomStringConvertible {
    case hmir(String)
    case backend(Int32)
    public var description: String {
        switch self {
        case .hmir(let m): return "HMIR 생성 실패: \(m)"
        case .backend(let c): return "LLVM IR 생성 실패(코드 \(c))"
        }
    }
}

/// frontendArgs: 정본 `컴파일러`와 같은 인자(실행본 이름 제외)
///   <source.hmje> <library-root> <platform> <기본동적배열.hmje> <출력.hmir> [--캐시끄기] [--module-map M] [--native-plan N]
/// llvmOutput: LLVM IR을 쓸 경로.
public func finishpoint(frontendArgs: [String], llvmOutput: String, options: FinishpointOptions = FinishpointOptions()) -> Result<Void, FinishpointError> {
    // 1. 적재 + 준비
    let prepared = prepareDocument(args: frontendArgs)

    // 2. 타입 AST + HMIR
    let (_, generated) = generateHMIR(prepared: prepared)
    let lines: [BStr]
    switch generated {
    case .success(let l): lines = l
    case .failure(let e): return .failure(.hmir("\(e)"))
    }
    let hmir = serializeHMIR(lines)
    let hmirPath = frontendArgs.count > 4 ? frontendArgs[4] : "finishpoint.hmir"
    if options.writeHMIR {
        FileManager.default.createFile(atPath: hmirPath, contents: Data(hmir))
    }

    // 3. HMIR → LLVM IR. 백엔드는 입력을 경로로 읽으므로 그 자리에 메모리의 HMIR을 넘긴다.
    let argv = ["hmir을llvm으로", hmirPath, llvmOutput] + options.backendFlags
    let code = HMIRToLLVM.run(argv, readFile: { path in
        if path == hmirPath { return hmir }
        return FileManager.default.contents(atPath: path).map { [UInt8]($0) }
    }, writeFile: { path, bytes in
        FileManager.default.createFile(atPath: path, contents: Data(bytes))
    })
    return code == 0 ? .success(()) : .failure(.backend(code))
}
