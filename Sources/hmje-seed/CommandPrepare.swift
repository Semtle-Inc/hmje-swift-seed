import Foundation
import SeedCore

/// hmje-seed prepare <프론트엔드 인자...> --dump-prepared <out.json> [--dump-stages <접두>]
func commandPrepare(_ argv: [String]) {
    var fwd: [String] = []
    var out: String? = nil
    var stagePrefix: String? = nil
    var i = 0
    while i < argv.count {
        if argv[i] == "--dump-prepared", i + 1 < argv.count { out = argv[i + 1]; i += 2; continue }
        if argv[i] == "--dump-stages", i + 1 < argv.count { stagePrefix = argv[i + 1]; i += 2; continue }
        fwd.append(argv[i]); i += 1
    }
    guard let outPath = out else { fail("쓰임: hmje-seed prepare <entry> <library-root> darwin <기본동적배열.hmje> <out.hmir> [옵션] --dump-prepared <out.json>", code: 2) }
    var opts = PrepareOptions()
    if let p = stagePrefix {
        opts.onStage = { name, v in
            FileManager.default.createFile(atPath: "\(p).\(name).json", contents: Data(JSONWriter.serialize(v)))
        }
    }
    let doc = prepareDocument(args: fwd, options: opts)
    if !FileManager.default.createFile(atPath: outPath, contents: Data(JSONWriter.serialize(doc))) {
        fail("준비 덤프 쓰기 실패: \(outPath)")
    }
}
