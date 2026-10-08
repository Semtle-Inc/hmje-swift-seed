import Foundation

// Change only source-location metadata and the filename prefix of optional-unwrapping
// diagnostics. Instructions, types, symbols and source files remain unchanged.
let args = CommandLine.arguments
guard args.count == 4 else { fputs("usage: map-source-prefix.swift <hmir> <source-root> <release-root>\n", stderr); exit(2) }
do {
    let file = URL(fileURLWithPath: args[1])
    let from = args[2] + "/"
    let to = args[3] + "/"
    guard from != to, !args[2].contains("\n"), !args[3].contains("\n") else {
        throw NSError(domain: "prefix", code: 1)
    }
    let original = try String(contentsOf: file, encoding: .utf8)
    let location = try NSRegularExpression(pattern: "^\\s*원본위치 [0-9]+ ")
    let diagnostic = try NSRegularExpression(pattern: "^\\s*선택값검사 %[A-Za-z0-9_]+, \\\"")
    var counts = ["locations": 0, "diagnostics": 0]
    let lines = try original.components(separatedBy: "\n").map { line -> String in
        guard let found = line.range(of: from) else { return line }
        let head = String(line[..<found.lowerBound])
        let range = NSRange(head.startIndex..., in: head)
        let kind: String
        if location.firstMatch(in: head, range: range)?.range == range { kind = "locations" }
        else if diagnostic.firstMatch(in: head, range: range)?.range == range { kind = "diagnostics" }
        else { throw NSError(domain: "Unexpected source-prefix occurrence", code: 2) }
        let suffix = String(line[found.upperBound...])
        guard (suffix.hasPrefix("compiler/") || suffix.hasPrefix("library/")),
              !suffix.contains(from) else { throw NSError(domain: "Invalid source-location prefix", code: 3) }
        counts[kind, default: 0] += 1
        return head + to + suffix
    }
    guard counts["locations", default: 0] > 0 else { throw NSError(domain: "No source locations mapped", code: 4) }
    try FileManager.default.copyItem(at: file, to: URL(fileURLWithPath: file.path + ".unmapped"))
    try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    print("source prefix: \(counts["locations"]!) location records, \(counts["diagnostics"]!) diagnostic prefixes")
} catch { fputs("source prefix mapping failed: \(error)\n", stderr); exit(1) }
