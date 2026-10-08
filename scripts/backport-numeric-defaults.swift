import Foundation

// Bootstrap-only backport of numeric default recognition from 70597c04.
// The final Beta 1 source is never modified.
guard CommandLine.arguments.count == 2 else { exit(2) }
let file = URL(fileURLWithPath: CommandLine.arguments[1])
    .appendingPathComponent("compiler/Sources/프론트엔드/문장파서.hmje")
do {
    var source = try String(contentsOf: file, encoding: .utf8)
    let changes = [
        ("    만약 타입 == \"자연수8\" 또는 타입 == \"자연수16\" 또는 타입 == \"자연수32\" 또는 타입 == \"자연수64\"이면",
         "    만약 타입 == \"자연수8\" 또는 타입 == \"자연수16\" 또는 타입 == \"자연수32\" 또는 타입 == \"자연수64\" 또는 타입 == \"자연수\" 또는 타입 == \"큰자연수\"이면"),
        ("    만약 타입 == \"정수8\" 또는 타입 == \"정수16\" 또는 타입 == \"정수32\" 또는 타입 == \"정수64\"이면",
         "    만약 타입 == \"정수8\" 또는 타입 == \"정수16\" 또는 타입 == \"정수32\" 또는 타입 == \"정수64\" 또는 타입 == \"정수\" 또는 타입 == \"큰정수\"이면"),
        ("    만약 타입 == \"실수32\" 또는 타입 == \"실수64\"이면",
         "    만약 타입 == \"실수32\" 또는 타입 == \"실수64\" 또는 타입 == \"실수\"이면")
    ]
    // Restrict edits to the numeric-default predicate; reject changed upstream inputs.
    let marker = "함수 파싱기본값숫자타입인가는 (타입: 문자열)를 받아\n"
    guard let begin = source.range(of: marker),
          let end = source.range(of: "\n함수 파싱기본값식은", range: begin.upperBound..<source.endIndex) else { exit(1) }
    var body = String(source[begin.lowerBound..<end.lowerBound])
    for (old, new) in changes {
        guard body.components(separatedBy: old).count == 2 else { exit(1) }
        body = body.replacingOccurrences(of: old, with: new)
    }
    source.replaceSubrange(begin.lowerBound..<end.lowerBound, with: body)
    try source.write(to: file, atomically: true, encoding: .utf8)
    print("숫자 기본값 판별식 3개를 부트스트랩 소스에 적용했습니다.")
} catch {
    fputs("부트스트랩 소스 패치 실패: \(error)\n", stderr); exit(1)
}
