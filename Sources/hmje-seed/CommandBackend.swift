import Foundation
import SeedCore

// hmje-seed hmir2ll <in.hmir> <out.ll> [--target-triple T] [--posix-file-ffi] [--캐시끄기] ...
// 정본 `hmir을llvm으로`(변환기.hmje)와 같은 인자를 받는다.
func commandBackend(_ args: [String]) -> Never {
    // 정본 인자 배열은 [실행본, 입력, 출력, 옵션...]
    let argv = ["hmir을llvm으로"] + Array(args.dropFirst(2))
    let code = HMIRToLLVM.run(argv, readFile: { readFile($0) }, writeFile: { path, bytes in
        FileManager.default.createFile(atPath: path, contents: Data(bytes))
    })
    exit(code)
}
