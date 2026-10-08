import Foundation
import SeedCore

// hmje-seed finishpoint <정본 컴파일러 인자...> --llvm <out.ll> [--target-triple <트리플>]
// 소스에서 LLVM IR까지 한 번에(적재 → 준비 → 타입 AST → HMIR → LLVM IR).
func commandFinishpoint(_ args: [String]) -> Never {
    var frontend: [String] = []
    var llvm: String? = nil
    var options = FinishpointOptions()
    var i = 0
    while i < args.count {
        if args[i] == "--llvm", i + 1 < args.count { llvm = args[i + 1]; i += 2; continue }
        if args[i] == "--target-triple", i + 1 < args.count { options.backendFlags[1] = args[i + 1]; i += 2; continue }
        frontend.append(args[i]); i += 1
    }
    guard let out = llvm, frontend.count >= 5 else {
        fail("쓰임: hmje-seed finishpoint <source.hmje> <library-root> <platform> <기본동적배열.hmje> <출력.hmir> [옵션...] --llvm <out.ll>", code: 2)
    }
    switch finishpoint(frontendArgs: frontend, llvmOutput: out, options: options) {
    case .success: exit(0)
    case .failure(let e): fail("\(e)")
    }
}
