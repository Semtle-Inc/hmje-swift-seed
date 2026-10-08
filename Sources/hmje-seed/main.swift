import Foundation
import SeedCore

func readFile(_ path: String) -> [UInt8]? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    return [UInt8](d)
}

func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

let args = CommandLine.arguments
let usage = """
hmje-seed \(Seed.version)
쓰임:
  hmje-seed finishpoint <컴파일러 인자...> --llvm <out.ll>   소스 → LLVM IR 전체(적재·준비·타입·HMIR·LLVM)
  hmje-seed plan <hmjec-selfhost> <project-root> <artifact> <target> <out-dir> <platform> [옵션...]  프로젝트 계획(정본 프로젝트조정기)
  hmje-seed parse <file.hmje> [out.json]      파싱 AST(hmje-parsed-ast-v1) 방출
  hmje-seed check-parse <index.txt> <astdir>  오라클 파싱 AST와 파일별 대조
  hmje-seed json-diff <a.json> <b.json>       두 JSON의 의미 비교(첫 차이 경로)
  hmje-seed hmir2ll <in.hmir> <out.ll> [옵션]  HMIR → LLVM IR (백엔드)
  hmje-seed hmirgen <prepared.json> <out.hmir> [--dump-typed <typed.json>]  타입 AST + HMIR 생성
  hmje-seed json-roundtrip <in.json> <out.json> 공통 JSONValue로 읽고 정본 형식으로 다시 쓰기
  hmje-seed prepare <프론트엔드 인자...> --dump-prepared <out.json>  적재+준비 문서 방출
"""

guard args.count >= 2 else {
    print(usage)
    exit(0)
}

switch args[1] {
case "finishpoint": commandFinishpoint(Array(args.dropFirst(2)))
case "plan": commandPlan(Array(args.dropFirst(2)))
case "hmir2ll": commandBackend(args)
case "prepare": commandPrepare(Array(args.dropFirst(2)))
case "hmirgen":
    commandHMIRGen(args)

case "json-roundtrip":
    guard args.count >= 4, let src = readFile(args[2]) else { fail(usage, code: 2) }
    do {
        let v = try JSONReader.parse(src)
        let out = JSONWriter.serialize(v)
        FileManager.default.createFile(atPath: args[3], contents: Data(out))
    } catch { fail("JSON 파싱 실패: \(error)") }

case "parse":
    guard args.count >= 3 else { fail(usage, code: 2) }
    guard let src = readFile(args[2]) else { fail("읽기 실패: \(args[2])") }
    let r = parseSource(bytes: src)
    if !r.ok { fail(r.error) }
    let doc = ASTJSON.document(r.statements)
    if args.count >= 4 {
        do { try doc.write(toFile: args[3], atomically: true, encoding: .utf8) } catch { fail("파싱 AST 쓰기 실패") }
    } else {
        FileHandle.standardOutput.write(doc.data(using: .utf8)!)
    }

case "check-parse":
    guard args.count >= 4 else { fail(usage, code: 2) }
    guard let idx = readFile(args[2]) else { fail("읽기 실패: \(args[2])") }
    let astDir = args[3]
    let filter = args.count >= 5 ? args[4] : nil
    var pass = 0, total = 0
    for rawLine in String(decoding: idx, as: UTF8.self).split(separator: "\n") {
        let parts = rawLine.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let n = String(parts[0]), path = String(parts[1])
        if let f = filter, !path.contains(f), n != f { continue }
        total += 1
        let name = (path as NSString).lastPathComponent
        guard let src = readFile(path) else { print("FAIL \(n) \(name): 소스 읽기 실패"); continue }
        let r = parseSource(bytes: src)
        if !r.ok { print("FAIL \(n) \(name): 파싱 실패: \(r.error)"); continue }
        let doc = ASTJSON.document(r.statements)
        guard let oracleBytes = readFile("\(astDir)/\(n).json") else { print("FAIL \(n) \(name): 오라클 없음"); continue }
        do {
            let mine = try JSONCheck.parse(Array(doc.utf8))
            let theirs = try JSONCheck.parse(oracleBytes)
            if let d = JSONCheck.firstDifference(mine, theirs, "$") {
                print("FAIL \(n) \(name): \(d)")
            } else {
                print("PASS \(n) \(name)")
                pass += 1
            }
        } catch {
            print("FAIL \(n) \(name): \(error)")
        }
    }
    print("\(pass)/\(total) PASS")
    exit(pass == total ? 0 : 1)

case "json-diff":
    guard args.count >= 4 else { fail(usage, code: 2) }
    guard let a = readFile(args[2]), let b = readFile(args[3]) else { fail("읽기 실패") }
    do {
        if let d = JSONCheck.firstDifference(try JSONCheck.parse(a), try JSONCheck.parse(b), "$") {
            print(d)
            exit(1)
        }
        print("같음")
    } catch {
        fail("\(error)")
    }

default:
    fail(usage, code: 2)
}
