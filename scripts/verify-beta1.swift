import Foundation

struct Stage: Decodable { let id: String; let source: String; let artifact: String? }
struct Lock: Decodable {
    let version: String; let build: String; let compilerSourceCommit: String
    let packageToolchainCommit: String; let deploymentTarget: String
    let snapshots: [String: String]; let bootstrapStages: [Stage]
}
struct Failure: Error { let message: String }
let fm = FileManager.default
let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let args = CommandLine.arguments
func reject(_ message: String) throws -> Never { throw Failure(message: message) }
guard args.count == 3 else {
    fputs("사용법: swift scripts/verify-beta1.swift <Beta 1 네 도구 폴더> <새 출력 폴더>\n", stderr)
    exit(2)
}
let expected = URL(fileURLWithPath: args[1]).standardizedFileURL
let output = URL(fileURLWithPath: args[2]).standardizedFileURL
if fm.fileExists(atPath: output.path) {
    fputs("출력 폴더가 이미 존재합니다. 새 경로를 지정하십시오.\n", stderr); exit(2)
}
var results: [[String: Any]] = []
var lock: Lock?
var toolchain: [String: String] = [:]
var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HMJE_") }
for key in ["SDKROOT", "MACOSX_DEPLOYMENT_TARGET", "CC", "CFLAGS", "LDFLAGS", "SWIFT_EXEC", "SWIFTFLAGS"] {
    environment.removeValue(forKey: key)
}
environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
let names = ["컴파일러", "hmir을llvm으로", "제품조정기", "프로젝트조정기"]
func run(_ name: String, _ executable: String, _ arguments: [String], cwd: URL? = nil,
         extra: [String: String] = [:]) throws {
    let log = output.appendingPathComponent(name + ".log")
    guard fm.createFile(atPath: log.path, contents: nil) else { try reject("로그 생성 실패: \(name)") }
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    let p = Process(); p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments; p.currentDirectoryURL = cwd ?? repo
    p.environment = environment.merging(extra) { _, new in new }
    p.standardOutput = handle; p.standardError = handle
    let started = Date()
    print("실행: \(name)")
    try p.run(); p.waitUntilExit()
    results.append(["stage": name, "status": p.terminationStatus == 0 ? "passed" : "failed",
                    "exitCode": p.terminationStatus, "seconds": Date().timeIntervalSince(started),
                    "log": log.lastPathComponent])
    if p.terminationStatus != 0 { try reject("\(name) 실패 (종료 코드 \(p.terminationStatus)); \(log.lastPathComponent) 확인") }
}
func writeReport(_ status: String, _ message: String = "") throws {
    var report: [String: Any] = ["schema": "hmje-beta1-seed-verification-v1", "status": status,
        "message": message, "stages": results, "hostTools": toolchain,
        "checkedAt": ISO8601DateFormatter().string(from: Date()),
        "scope": "macos-arm64 compiler tools; IDE and other architectures excluded",
        "comparison": "raw pre-distribution build bytes and signature-normalized signed release copies",
        "distributionSignatureReproduced": false,
        "sourcePrefixMapping": "HMIR source-location records and optional-unwrapping diagnostic filename prefixes only"]
    if let l = lock {
        report["version"] = l.version; report["build"] = l.build
        report["compilerSourceCommit"] = l.compilerSourceCommit
        report["packageToolchainCommit"] = l.packageToolchainCommit
    }
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output.appendingPathComponent("report.json"), options: .atomic)
}
func capture(_ executable: String, _ arguments: [String]) throws -> String {
    let p = Process(); let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
    p.environment = environment; p.standardOutput = pipe; p.standardError = pipe
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    guard p.terminationStatus == 0 else { try reject("도구 정보 읽기 실패: \(executable)") }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
do {
    try fm.createDirectory(at: output, withIntermediateDirectories: true)
    let l = try JSONDecoder().decode(Lock.self, from: Data(contentsOf: repo.appendingPathComponent("reference/versions.json")))
    lock = l
    guard try capture("/usr/bin/uname", ["-sm"]) == "Darwin arm64" else { try reject("macOS ARM64 호스트가 필요합니다") }
    toolchain["swift"] = try capture("/usr/bin/swift", ["--version"])
    toolchain["clang"] = try capture("/usr/bin/clang", ["--version"])
    toolchain["os"] = try capture("/usr/bin/sw_vers", ["-productVersion"])
    toolchain["xcode"] = try capture("/usr/bin/xcode-select", ["-p"])
    toolchain["sdk"] = try capture("/usr/bin/xcrun", ["--sdk", "macosx", "--show-sdk-version"])
    try writeReport("running")
    try run("seed-integrity", "/usr/bin/shasum", ["-a", "256", "-c", "reference/seed-beta1.sha256"])
    try run("source-integrity", "/usr/bin/shasum", ["-a", "256", "-c", "SHA256SUMS"], cwd: repo.appendingPathComponent("reference"))
    guard fm.fileExists(atPath: expected.path) else { try reject("Beta 1 비교 도구 폴더가 없습니다") }
    let manifest = output.appendingPathComponent("beta1-tools.sha256")
    try fm.copyItem(at: repo.appendingPathComponent("reference/beta1-tools.sha256"), to: manifest)
    // Comparison inputs are hashed, never executed or used to generate IR.
    try run("release-integrity", "/usr/bin/shasum", ["-a", "256", "-c", manifest.path], cwd: expected)
    // Read only after the signed comparison inputs pass their fixed hashes.
    // The caller's HMJE_* overrides have already been removed.
    environment["HMJE_RELEASE_SOURCE_PREFIX"] = try capture("/usr/bin/swift", [
        repo.appendingPathComponent("scripts/release-source-prefix.swift").path, expected.path])
    let sources = output.appendingPathComponent("sources")
    try fm.createDirectory(at: sources, withIntermediateDirectories: false)
    for name in l.snapshots.keys.sorted() {
        let tree = sources.appendingPathComponent(name)
        try fm.createDirectory(at: tree, withIntermediateDirectories: false)
        try run("extract-" + name, "/usr/bin/tar", ["-xzf", repo.appendingPathComponent("reference/" + name + ".tar.gz").path, "-C", tree.path])
        if name == "alias-bridge" {
            try run("bootstrap-alias-backport", "/usr/bin/swift", [repo.appendingPathComponent("scripts/backport-numeric-defaults.swift").path, tree.path])
        }
        if name == "none-bridge" {
            try run("bootstrap-none-backport", "/usr/bin/patch", ["--batch", "-p1", "-d", tree.path,
                   "-i", repo.appendingPathComponent("reference/bootstrap-none.patch").path])
        }
        try run("tree-manifest-" + name, "/bin/bash", ["-c", "find . -type f -exec /usr/bin/shasum -a 256 {} +"], cwd: tree)
    }
    var previous = output.appendingPathComponent("seed-gen1")
    try run("seed-gen1", "/bin/bash", [repo.appendingPathComponent("scripts/gen1.sh").path,
          sources.appendingPathComponent("anchor").path, previous.path], extra: ["MACOSX_DEPLOYMENT_TARGET": "26.0"])
    for stage in l.bootstrapStages {
        let next = output.appendingPathComponent(stage.id)
        let buildScript = stage.source == "beta1" ? "scripts/rebuild-beta1.sh" : "scripts/rebuild.sh"
        var arguments = [repo.appendingPathComponent(buildScript).path,
                         sources.appendingPathComponent(stage.source).path, previous.path, next.path]
        if let artifact = stage.artifact { arguments.append(artifact) }
        try run(stage.id, "/bin/bash", arguments, extra: ["MACOSX_DEPLOYMENT_TARGET": l.deploymentTarget])
        if let artifact = stage.artifact {
            for name in names where name != artifact {
                try fm.copyItem(at: previous.appendingPathComponent(name), to: next.appendingPathComponent(name))
            }
        }
        previous = next
        try writeReport("running")
    }
    for name in names {
        try run("fixedpoint-" + name, "/usr/bin/cmp", [output.appendingPathComponent("beta1-gen2/" + name).path,
                    output.appendingPathComponent("beta1-gen3/" + name).path])
    }
    let normalized = output.appendingPathComponent("normalized-release")
    try run("release-normalization", "/bin/bash", [repo.appendingPathComponent("scripts/normalize-reference.sh").path,
            sources.appendingPathComponent("beta1").path, expected.path, normalized.path])
    let unsignedManifest = output.appendingPathComponent("beta1-unsigned-tools.sha256")
    try fm.copyItem(at: repo.appendingPathComponent("reference/beta1-unsigned-tools.sha256"), to: unsignedManifest)
    try run("normalized-release-integrity", "/usr/bin/shasum", ["-a", "256", "-c", unsignedManifest.path], cwd: normalized)
    try run("raw-build-integrity", "/usr/bin/shasum", ["-a", "256", "-c", unsignedManifest.path], cwd: previous)
    for name in names {
        try run("release-match-" + name, "/usr/bin/cmp", [previous.appendingPathComponent(name).path,
                    normalized.appendingPathComponent(name).path])
    }
    for name in l.snapshots.keys.sorted() {
        try run("tree-integrity-after-" + name, "/usr/bin/shasum", ["-a", "256", "-c",
                output.appendingPathComponent("tree-manifest-" + name + ".log").path],
                cwd: sources.appendingPathComponent(name))
    }
    try run("source-integrity-after", "/usr/bin/shasum", ["-a", "256", "-c", "SHA256SUMS"], cwd: repo.appendingPathComponent("reference"))
    try run("seed-integrity-after", "/usr/bin/shasum", ["-a", "256", "-c", "reference/seed-beta1.sha256"])
    try writeReport("verified")
    print("Beta 1 재현 검증 완료: 네 도구 고정점·서명 전 원본 및 서명 정규화 배포 사본 일치")
} catch {
    let message = (error as? Failure)?.message ?? String(describing: error)
    try? writeReport("failed", message)
    fputs(message + "\n", stderr)
    exit(1)
}
