import Foundation

// Read source-location metadata from comparison inputs; never execute them.
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("사용법: release-source-prefix.swift <Beta 1 네 도구 폴더>\n", stderr)
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1])
let tools = ["컴파일러", "hmir을llvm으로", "제품조정기", "프로젝트조정기"]
do {
    var candidates = Set<String>()
    for tool in tools {
        let data = try Data(contentsOf: root.appendingPathComponent(tool))
        for bytes in data.split(separator: 0) {
            guard let text = String(bytes: bytes, encoding: .utf8),
                  text.hasPrefix("/"),
                  let marker = text.range(of: "/compiler/Sources/") else { continue }
            let prefix = String(text[..<marker.lowerBound])
            guard !prefix.isEmpty,
                  !prefix.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { continue }
            candidates.insert(prefix)
        }
    }
    guard candidates.count == 1, let prefix = candidates.first else {
        throw NSError(domain: "배포 도구의 소스 접두 경로를 하나로 식별할 수 없습니다", code: 1)
    }
    print(prefix)
} catch {
    fputs("배포 소스 경로 읽기 실패: \(error)\n", stderr)
    exit(1)
}
