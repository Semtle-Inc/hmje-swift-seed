// 프론트엔드/토크나이저.hmje (소스토큰화줄부터)의 바이트 단위 이식.

public enum TokKind: String {
    case name = "이름"
    case string = "문자열"
    case int = "정수"
    case hexInt = "16진정수"
    case float = "실수"
    case punct = "구두점"
    case op = "연산자"
    case newline = "줄바꿈"
    case indent = "들여쓰기"
    case dedent = "내어쓰기"
    case end = "끝"
}

public struct Token {
    public var kind: TokKind
    public var body: BStr
    public var line: Int
    public var col: Int
    public init(_ kind: TokKind, _ body: BStr, _ line: Int, _ col: Int) {
        self.kind = kind
        self.body = body
        self.line = line
        self.col = col
    }
    /// 범위를 벗어난 첨자에 쓰는 빈 토큰(자립 파서는 그런 읽기를 결과에 쓰지 않는다).
    static let none = Token(.end, "", 0, 0)
}

public struct TokenizeResult {
    public var ok: Bool
    public var tokens: [Token]
    public var error: String
}

@inline(__always) func isSpaceByte(_ b: UInt8) -> Bool { b == 32 || b == 9 }
@inline(__always) func isDigitByte(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }
@inline(__always) func isHexByte(_ b: UInt8) -> Bool {
    isDigitByte(b) || (b >= 65 && b <= 70) || (b >= 97 && b <= 102)
}
@inline(__always) func isPunctByte(_ b: UInt8) -> Bool {
    b == 40 || b == 41 || b == 91 || b == 93 || b == 123 || b == 125 || b == 58 || b == 44 || b == 46
}
@inline(__always) func isOpByte(_ b: UInt8) -> Bool {
    b == 43 || b == 45 || b == 42 || b == 47 || b == 37 || b == 60 || b == 62 || b == 61 || b == 33
        || b == 38 || b == 124 || b == 94 || b == 126
}

/// 토큰문자열줄합치기: 여러 줄 문자열 리터럴은 줄마다 양끝 공백을 걷고 " "로 잇는다.
func joinStringLines(_ body: [UInt8]) -> [UInt8] {
    let n = body.count
    var out: [UInt8] = []
    var pieceStart = 0
    var pos = 0
    while pos < n {
        if body[pos] == 10 {
            var pieceEnd = pos
            while pieceEnd > pieceStart {
                let c = body[pieceEnd - 1]
                if c == 32 || c == 9 || c == 13 { pieceEnd -= 1 } else { break }
            }
            out.append(contentsOf: body[pieceStart..<pieceEnd])
            out.append(32)
            pos += 1
            while pos < n && (body[pos] == 32 || body[pos] == 9) { pos += 1 }
            pieceStart = pos
        } else {
            pos += 1
        }
    }
    out.append(contentsOf: body[pieceStart..<n])
    return out
}

public func tokenize(_ source: String, startLine: Int = 1) -> TokenizeResult {
    tokenize(bytes: Array(source.utf8), startLine: startLine)
}

public func tokenize(bytes src: [UInt8], startLine: Int = 1) -> TokenizeResult {
    var tokens: [Token] = []
    tokens.reserveCapacity(src.count / 3)
    var indents: [Int] = [0]
    var pos = 0
    var line = startLine
    var lineStart = 0
    var lineHead = true
    var groupDepth = 0
    let len = src.count
    while pos < len {
        var byte = src[pos]
        if byte == 13 {
            pos += 1
        } else if byte == 10 {
            if groupDepth == 0 { tokens.append(Token(.newline, "", line, 1)) }
            line += 1
            pos += 1
            lineStart = pos
            lineHead = true
        } else {
            if lineHead {
                var indent = 0
                while isSpaceByte(byte) {
                    indent += byte == 9 ? 4 : 1
                    pos += 1
                    byte = pos >= len ? 10 : src[pos]
                }
                if groupDepth == 0 && byte != 10 && byte != 35 {
                    let cur = indents[indents.count - 1]
                    if indent > cur {
                        indents.append(indent)
                        tokens.append(Token(.indent, "", line, 1))
                    } else if indent < cur {
                        while indents.count > 1 && indent < indents[indents.count - 1] {
                            indents.removeLast()
                            tokens.append(Token(.dedent, "", line, 1))
                        }
                        if indent != indents[indents.count - 1] {
                            return TokenizeResult(ok: false, tokens: tokens, error: "들여쓰기 단계가 맞지 않습니다")
                        }
                    }
                }
                lineHead = false
            }
            // `#RRGGBB` 색 리터럴
            var isColor = false
            if byte == 35 && pos + 6 < len {
                var hexCount = 0
                for k in 1...6 where isHexByte(src[pos + k]) { hexCount += 1 }
                if hexCount == 6 { isColor = true }
            }
            if isColor {
                tokens.append(Token(.name, BStr(bytes: src[pos..<(pos + 7)]), line, (pos - lineStart) + 1))
                pos += 7
            } else if byte == 35 {
                while pos < len && src[pos] != 10 { pos += 1 }
            } else if isSpaceByte(byte) {
                pos += 1
            } else {
                let start = pos
                var kind = TokKind.name
                if byte == 34 {
                    kind = .string
                    pos += 1
                    var escape = false
                    var interpDepth = 0
                    var innerString = false
                    var innerEscape = false
                    while pos < len {
                        var cur = src[pos]
                        pos += 1
                        if interpDepth > 0 {
                            if innerString {
                                if innerEscape { innerEscape = false }
                                else if cur == 92 { innerEscape = true }
                                else if cur == 34 { innerString = false }
                            } else if cur == 34 {
                                innerString = true
                            } else if cur == 40 {
                                interpDepth += 1
                            } else if cur == 41 {
                                interpDepth -= 1
                            }
                        } else if escape {
                            if cur == 40 { interpDepth = 1 }
                            escape = false
                        } else if cur == 92 {
                            escape = true
                        } else if cur == 34 {
                            cur = 0
                        }
                        if cur == 0 { break }
                    }
                    if pos > len || src[pos - 1] != 34 {
                        return TokenizeResult(ok: false, tokens: tokens, error: "닫히지 않은 문자열입니다")
                    }
                } else if isDigitByte(byte) {
                    kind = .int
                    while pos < len && isDigitByte(src[pos]) { pos += 1 }
                    var radix: UInt8 = 0
                    if pos < len { radix = src[pos] }
                    if (pos == start + 1 && radix == 120) || (pos == start + 1 && radix == 88) {
                        kind = .hexInt
                        pos += 1
                        while pos < len && isHexByte(src[pos]) { pos += 1 }
                    } else if pos < len && src[pos] == 46 {
                        kind = .float
                        pos += 1
                        while pos < len && isDigitByte(src[pos]) { pos += 1 }
                    }
                    if pos < len {
                        let e = src[pos]
                        if e == 101 || e == 69 {
                            var ds = pos + 1
                            if ds < len {
                                let sign = src[ds]
                                if sign == 43 || sign == 45 { ds += 1 }
                            }
                            if ds < len && isDigitByte(src[ds]) {
                                kind = .float
                                pos = ds + 1
                                while pos < len && isDigitByte(src[pos]) { pos += 1 }
                            }
                        }
                    }
                } else if isPunctByte(byte) {
                    kind = .punct
                    pos += 1
                    if byte == 40 || byte == 91 || byte == 123 {
                        groupDepth += 1
                    } else if byte == 41 || byte == 93 || byte == 125 {
                        if groupDepth > 0 { groupDepth -= 1 }
                    }
                } else if isOpByte(byte) {
                    kind = .op
                    while pos < len && isOpByte(src[pos]) { pos += 1 }
                } else {
                    while pos < len {
                        let c = src[pos]
                        if isSpaceByte(c) || c == 10 || c == 13 || c == 35 || c == 34 || isPunctByte(c) || isOpByte(c) {
                            break
                        }
                        pos += 1
                    }
                }
                var body = Array(src[start..<pos])
                var bodyNewlines = 0
                if kind == .string {
                    bodyNewlines = body.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
                    if bodyNewlines > 0 { body = joinStringLines(body) }
                }
                tokens.append(Token(kind, BStr(body), line, start - lineStart + 1))
                if bodyNewlines > 0 {
                    line += bodyNewlines
                    // 토큰마지막줄시작
                    var p = pos
                    var found = start
                    while p > start {
                        if src[p - 1] == 10 { found = p; break }
                        p -= 1
                    }
                    lineStart = found
                }
            }
        }
    }
    while indents.count > 1 {
        indents.removeLast()
        tokens.append(Token(.dedent, "", line, 1))
    }
    tokens.append(Token(.end, "", line, 1))
    return TokenizeResult(ok: true, tokens: tokens, error: "")
}
