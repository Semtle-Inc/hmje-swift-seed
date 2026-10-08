import Foundation
import SeedCore

/// hmje-seed hmirgen <prepared.json> <out.hmir> [--dump-typed <typed.json>]
func commandHMIRGen(_ args: [String]) {
    guard args.count >= 4 else { fail("쓰임: hmje-seed hmirgen <prepared.json> <out.hmir> [--dump-typed <typed.json>]", code: 2) }
    guard let src = readFile(args[2]) else { fail("읽기 실패: \(args[2])") }
    var typedPath: String? = nil
    var i = 4
    while i < args.count {
        if args[i] == "--dump-typed", i + 1 < args.count { typedPath = args[i + 1]; i += 1 }
        i += 1
    }
    let prepared: JSONValue
    do { prepared = try JSONReader.parse(src) } catch { fail("JSON 파싱 실패: \(error)") }
    let g = HMIRGenerator()
    let typed = g.typedDocument(prepared: prepared)
    if let tp = typedPath {
        FileManager.default.createFile(atPath: tp, contents: Data(JSONWriter.serialize(typed)))
    }
    switch g.generate(typed: typed) {
    case .success(let lines):
        guard FileManager.default.createFile(atPath: args[3], contents: Data(serializeHMIR(lines))) else {
            fail("HMIR 출력 파일을 쓸 수 없습니다")
        }
    case .failure(let e):
        fail(e.message, code: 3)
    }
}
