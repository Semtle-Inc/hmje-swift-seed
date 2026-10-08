import Foundation
import SeedCore

// hmje-seed plan <hmjec-selfhost> <project-root> <artifact> <target> <out-dir> <platform> [옵션...]
// 정본 프로젝트조정기와 같은 인자 순서(출력·캐시 뿌리 대신 out-dir 하나). 계획만 만들고 컴파일하지 않는다.
// out-dir에 entry.hmje, modules.tsv, native.tsv, modules/<FNV>.hmje를 쓰고
// 프론트엔드로 넘길 나머지 옵션을 한 줄에 하나씩 out-dir/options에 쓴다.
func commandPlan(_ args: [String]) -> Never {
    guard args.count >= 6 else {
        fail("쓰임: hmje-seed plan <hmjec-selfhost> <project-root> <artifact> <target> <out-dir> <platform> [옵션...]", code: 2)
    }
    let r = coordinateProjectPlan(selfhost: args[0], projectRoot: args[1], artifact: args[2], target: args[3],
                                  platform: args[5], options: Array(args.dropFirst(6)), outDir: args[4])
    switch r {
    case .success(let p):
        let body = p.extraOptions.map { $0 + "\n" }.joined()
        FileManager.default.createFile(atPath: args[4] + "/options", contents: body.data(using: .utf8))
        exit(0)
    case .failure(.failed(let m, let code)):
        fail(m, code: code)
    }
}
