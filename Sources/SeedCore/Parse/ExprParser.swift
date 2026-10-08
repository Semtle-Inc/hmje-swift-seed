// 프론트엔드/표현식파서.hmje의 이식: Pratt 표현식 파서, 문자열 보간, 접미사 도우미.

/// 표현식파싱결과. 자립 파서의 `본문`(디버그용 문자열)은 방출에 쓰이지 않아 뺐다.
struct ER {
    var ok: Bool
    var pos: Int
    var node: ASTValue
    var err: String
    static func success(_ pos: Int, _ node: ASTValue) -> ER { ER(ok: true, pos: pos, node: node, err: "") }
    static func failure(_ pos: Int, _ err: String) -> ER { ER(ok: false, pos: pos, node: .null, err: err) }
}

extension Array where Element == Token {
    /// 범위 밖은 빈 끝 토큰(본문 "").
    @inline(__always) subscript(safe i: Int) -> Token {
        (i >= 0 && i < count) ? self[i] : Token.none
    }
    @inline(__always) func body(_ i: Int) -> BStr { self[safe: i].body }
}

// MARK: - 접미사 도우미

/// 파싱접미사제거
@inline(__always) func stripSuffix(_ s: BStr, _ suffix: BStr) -> BStr {
    if !s.hasSuffix(suffix) { return s }
    return s.sub(0, s.count - suffix.count)
}

/// 파싱조사제거
func stripParticle(_ s: BStr) -> BStr {
    if s.hasSuffix("으로") { return stripSuffix(s, "으로") }
    if s.hasSuffix("이고") { return stripSuffix(s, "이고") }
    if s.hasSuffix("이다") { return stripSuffix(s, "이다") }
    if s.hasSuffix("이면") { return stripSuffix(s, "이면") }
    if s.hasSuffix("에서") { return stripSuffix(s, "에서") }
    if s.hasSuffix("는") || s.hasSuffix("은") || s.hasSuffix("를") || s.hasSuffix("을") || s.hasSuffix("로") {
        return s.sub(0, s.count - 3)
    }
    if s.hasSuffix("일") { return stripSuffix(s, "일") }
    if s.hasSuffix("의") { return stripSuffix(s, "의") }
    if s.hasSuffix("에") { return stripSuffix(s, "에") }
    return s
}

/// 표현식구조갱신바탕정리
func cleanStructUpdateBase(_ n: ASTValue) -> ASTValue {
    if n.kind == "NameExpr" {
        let name = n.str("name")
        if name.hasSuffix("에서"), let node = n.nodeValue {
            return .node(node.replacing("name", with: S(stripSuffix(name, "에서"))))
        }
    }
    return n
}

/// 표현식16진정수문자열: 자연수64로 감싸 계산한 십진 문자열.
func hexLiteralDecimal(_ s: BStr) -> BStr {
    var v: UInt64 = 0
    var i = 2
    while i < s.count {
        let b = UInt64(s[i])
        var d = b &- 48
        if b >= 65 && b <= 70 { d = b &- 55 } else if b >= 97 { d = b &- 87 }
        v = (v << 4) | d
        i += 1
    }
    return BStr(decimal: v)
}

func operatorPrecedence(_ op: BStr) -> Int {
    if op == "||" || op == "또는" { return 1 }
    if op == "&&" || op == "그리고" { return 2 }
    if op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" { return 3 }
    if op == "|" { return 4 }
    if op == "^" { return 5 }
    if op == "&" { return 6 }
    if op == "<<" || op == ">>" { return 7 }
    if op == "+" || op == "-" { return 8 }
    if op == "*" || op == "/" || op == "%" { return 9 }
    return 0
}

/// 표현식이항기호
func binarySymbol(_ op: BStr) -> BStr {
    if op == "그리고" { return "&&" }
    if op == "또는" { return "||" }
    return op
}

/// 파싱기본타입인가
func isPrimitiveTypeName(_ n: BStr) -> Bool {
    let names: [BStr] = [
        "정수", "큰정수", "자연수", "큰자연수", "실수", "문자", "글자", "문자열", "글", "참거짓", "불리언", "불", "주소", "원시주소",
        "작은정수", "중간정수", "작은자연수", "중간자연수",
        "정수8", "정수16", "정수32", "정수64", "정수128",
        "자연수8", "자연수16", "자연수32", "자연수64", "자연수128",
        "실수16", "실수32", "실수64", "실수128",
    ]
    return names.contains(n)
}

@inline(__always) func isExprEndKind(_ k: TokKind) -> Bool { k == .newline || k == .end }

/// 표현식조각끝
func exprPieceEnd(_ t: [Token], _ start: Int) -> Int {
    var pos = start
    var depth = 0
    var cont = true
    while cont && pos < t.count && !isExprEndKind(t[pos].kind) {
        let b = t[pos].body
        if b == "(" || b == "[" || b == "{" {
            depth += 1
        } else if b == ")" || b == "]" || b == "}" {
            if depth == 0 { cont = false } else { depth -= 1 }
        } else if depth == 0 && b == "," {
            cont = false
        }
        if cont { pos += 1 }
    }
    return pos
}

/// 표현식사전조회시작인가
func isDictLookupStart(_ t: [Token], _ start: Int) -> Bool {
    if start >= t.count { return false }
    if t[start].kind != .name { return false }
    if !t[start].body.hasSuffix("에서") { return false }
    if t[start].body.count <= 6 { return false }
    return true
}

/// 표현식호출콜론있는가
func callHasColon(_ t: [Token], _ open: Int) -> Bool {
    var pos = open + 1
    var depth = 1
    while pos < t.count && depth > 0 {
        let b = t[pos].body
        if b == "(" { depth += 1 }
        else if b == ")" { depth -= 1 }
        else if depth == 1 && b == ":" { return true }
        pos += 1
    }
    return false
}

// MARK: - JSON 문자열 (기반 JSON파싱의 문자열 갈래)

/// 텍스트 전체가 JSON 문자열 하나일 때 그 값을 돌려준다.
func jsonParseStringDocument(_ text: BStr) -> BStr? {
    let a = text.bytes
    var i = 0
    func skipWS() { while i < a.count && (a[i] == 32 || a[i] == 9 || a[i] == 10 || a[i] == 13) { i += 1 } }
    skipWS()
    guard i < a.count, a[i] == 34 else { return nil }
    var cur = i + 1
    var out: [UInt8] = []
    func hex4(_ p: Int) -> Int? {
        if p + 4 > a.count { return nil }
        var v = 0
        for k in 0..<4 {
            let c = a[p + k]
            var d: Int
            if c >= 48 && c <= 57 { d = Int(c) - 48 }
            else if c >= 65 && c <= 70 { d = Int(c) - 55 }
            else if c >= 97 && c <= 102 { d = Int(c) - 87 }
            else { return nil }
            v = v * 16 + d
            _ = d
        }
        return v
    }
    var closed = false
    while cur < a.count {
        let c = a[cur]
        if c == 34 { closed = true; cur += 1; break }
        if c < 32 { return nil }
        if c != 92 { out.append(c); cur += 1; continue }
        if cur + 1 >= a.count { return nil }
        let e = a[cur + 1]
        switch e {
        case 34: out.append(34); cur += 2
        case 92: out.append(92); cur += 2
        case 47: out.append(47); cur += 2
        case 98: out.append(8); cur += 2
        case 102: out.append(12); cur += 2
        case 110: out.append(10); cur += 2
        case 114: out.append(13); cur += 2
        case 116: out.append(9); cur += 2
        case 117:
            guard let first = hex4(cur + 2) else { return nil }
            var cp = first
            var next = cur + 6
            if first >= 55296 && first <= 56319 {
                if a.count - next < 2 || a[next] != 92 || a[next + 1] != 117 { return nil }
                guard let second = hex4(next + 2), second >= 56320, second <= 57343 else { return nil }
                cp = 65536 + (first - 55296) * 1024 + (second - 56320)
                next += 6
            } else if first >= 56320 && first <= 57343 {
                return nil
            }
            if cp <= 127 { out.append(UInt8(cp)) }
            else if cp <= 2047 { out.append(UInt8(192 + (cp >> 6))); out.append(UInt8(128 + (cp & 63))) }
            else if cp <= 65535 {
                out.append(UInt8(224 + (cp >> 12))); out.append(UInt8(128 + ((cp >> 6) & 63))); out.append(UInt8(128 + (cp & 63)))
            } else {
                out.append(UInt8(240 + (cp >> 18))); out.append(UInt8(128 + ((cp >> 12) & 63)))
                out.append(UInt8(128 + ((cp >> 6) & 63))); out.append(UInt8(128 + (cp & 63)))
            }
            cur = next
        default: return nil
        }
    }
    if !closed { return nil }
    i = cur
    skipWS()
    if i != a.count { return nil }
    return BStr(out)
}

// MARK: - 문자열 리터럴·보간

/// 파싱문자열합치기
func concatStringNodes(_ l: ASTValue, _ r: ASTValue) -> ASTValue {
    if l.isNull { return r }
    if r.isNull { return l }
    return CallExpr("문자열붙인값", [l, r])
}

/// 파싱문자열조각
func stringPieceNode(_ body: BStr, _ start: Int, _ len: Int) -> ASTValue {
    if len == 0 { return .null }
    guard let v = jsonParseStringDocument("\"" + body.sub(start, len) + "\"") else { return .null }
    return N("StringLiteral", [("value", S(v))])
}

/// 파싱문자열JSON안전화: `\(`의 역슬래시를 한 번 더 이스케이프한다.
func jsonSafeInterp(_ body: BStr) -> BStr {
    let a = body.bytes
    var out: [UInt8] = []
    var start = 0
    var pos = 0
    while pos + 1 < a.count {
        if a[pos] == 92 && a[pos + 1] == 40 {
            out.append(contentsOf: a[start..<pos])
            out.append(92)
            start = pos
            pos += 2
        } else {
            pos += 1
        }
    }
    out.append(contentsOf: a[start..<a.count])
    return BStr(out)
}

/// 파싱일반문자열
func plainStringNode(_ body: BStr) -> ASTValue {
    guard let v = jsonParseStringDocument(jsonSafeInterp(body)) else { return .null }
    return N("StringLiteral", [("value", S(v))])
}

/// 파싱보간문자열
func interpolatedStringNode(_ body: BStr) -> ASTValue {
    let a = body.bytes
    let len = a.count
    var pos = 1
    var pieceStart = 1
    var result: ASTValue = .null
    var hasInterp = false
    while pos + 1 < len {
        let b = a[pos]
        if b == 92 && a[pos + 1] == 40 {
            hasInterp = true
            result = concatStringNodes(result, stringPieceNode(body, pieceStart, pos - pieceStart))
            var cursor = pos + 2
            var depth = 1
            var inString = false
            var escape = false
            while depth > 0 && cursor < len - 1 {
                let c = a[cursor]
                if inString {
                    if escape { escape = false }
                    else if c == 92 { escape = true }
                    else if c == 34 { inString = false }
                } else if c == 34 {
                    inString = true
                } else if c == 40 {
                    depth += 1
                } else if c == 41 {
                    depth -= 1
                }
                cursor += 1
            }
            if depth != 0 { return .null }
            let exprSource = body.sub(pos + 2, cursor - pos - 3)
            let e = sourceExpressionParse(exprSource)
            if !e.ok { return .null }
            result = concatStringNodes(result, CallExpr("문자열로만들기", [e.node]))
            pos = cursor
            pieceStart = pos
        } else if b == 92 {
            pos += 2
        } else {
            pos += 1
        }
    }
    if !hasInterp {
        guard let v = jsonParseStringDocument(body) else { return .null }
        return N("StringLiteral", [("value", S(v))])
    }
    result = concatStringNodes(result, stringPieceNode(body, pieceStart, len - pieceStart - 1))
    return result
}

/// 소스표현식파싱
func sourceExpressionParse(_ source: BStr) -> ER {
    let tk = tokenize(bytes: source.bytes)
    if !tk.ok { return .failure(0, tk.error) }
    let t = tk.tokens
    if t.count >= 2 && t[0].kind == .string && isExprEndKind(t[1].kind) {
        let n = interpolatedStringNode(t[0].body)
        if n.isNull { return .failure(0, "문자열 이스케이프가 올바르지 않습니다") }
        return .success(1, n)
    }
    let r = parseExpression(t, 0, 1)
    if !r.ok { return r }
    if r.pos < t.count && t[r.pos].kind != .newline && t[r.pos].kind != .end {
        return .failure(r.pos, "표현식 뒤에 남은 토큰이 있습니다")
    }
    return r
}

// MARK: - Pratt 파서

/// 표현식토큰범위파싱
func parseTokenRangeExpr(_ t: [Token], _ start: Int, _ end: Int) -> ER {
    var pieces: [Token] = []
    var i = start
    while i < end {
        var tok = t[i]
        if i + 1 == end { tok.body = stripParticle(tok.body) }
        pieces.append(tok)
        i += 1
    }
    pieces.append(Token(.end, "", t[safe: start].line, 1))
    return parseExpression(pieces, 0, 1)
}

/// 표현식파싱
func parseExpression(_ t: [Token], _ start: Int, _ minPrec: Int) -> ER {
    var bufEnd = start
    while bufEnd < t.count && !isExprEndKind(t[bufEnd].kind) { bufEnd += 1 }
    var placed = start
    while placed < bufEnd && t[placed].body != "놓인" { placed += 1 }
    if placed > start && placed + 1 < bufEnd && t[placed - 1].body.hasSuffix("에") {
        let bufExpr = parseTokenRangeExpr(t, start, placed)
        if !bufExpr.ok { return bufExpr }
        var isArray = false
        var structName = t[placed + 1].body
        if placed + 3 == bufEnd && t[placed + 2].body == "배열" && structName.hasSuffix("의") {
            isArray = true
            structName = stripSuffix(structName, "의")
        }
        if placed + 2 == bufEnd || isArray {
            return .success(bufEnd - start, N("OverlayBindExpr", [
                ("buffer", bufExpr.node), ("struct_name", S(structName)), ("is_array", B(isArray)),
            ]))
        }
    }
    if bufEnd >= start + 3 && t[bufEnd - 1].body == "본다" && t[bufEnd - 2].body.hasPrefix("버퍼뷰") {
        var obj = start
        while obj < bufEnd - 2 && !t[obj].body.hasSuffix("을") && !t[obj].body.hasSuffix("를") { obj += 1 }
        if obj < bufEnd - 2 {
            let base = parseTokenRangeExpr(t, start, obj + 1)
            if !base.ok { return base }
            if obj + 1 < bufEnd - 2 && t[bufEnd - 3].body == "바이트" {
                let length = parseTokenRangeExpr(t, obj + 1, bufEnd - 3)
                if !length.ok { return length }
                let cast = N("CastExpr", [("type_name", S("자연수64")), ("expr", length.node), ("compiler_generated", B(false))])
                let fields: ASTValue = .object([("기준주소", base.node), ("길이", cast)])
                return .success(bufEnd - start, N("StructInitExpr", [
                    ("name", S("버퍼뷰")), ("fields", fields), ("unsafe", B(true)), ("base", .null), ("compiler_generated", B(false)),
                ]))
            }
            if obj + 1 == bufEnd - 2 {
                return .success(bufEnd - start, N("ArrayBufferViewExpr", [("array", base.node)]))
            }
        }
    }
    if isDictLookupStart(t, start) {
        let dictEnd = exprPieceEnd(t, start)
        if dictEnd >= start + 3 && stripParticle(t[dictEnd - 1].body) == "값" && t[dictEnd - 2].body.hasSuffix("의") {
            let keyEnd = dictEnd - 2
            var keyToks: [Token] = []
            var k = start + 1
            while k < keyEnd { keyToks.append(t[k]); k += 1 }
            if t[keyEnd].body != "의" {
                var last = t[keyEnd]
                let kb = stripSuffix(last.body, "의")
                if kb.count > 0 {
                    last.body = kb
                    keyToks.append(last)
                }
            }
            if keyToks.count > 0 {
                keyToks.append(Token(.end, "", t[start].line, 1))
                let keyParse = parseExpression(keyToks, 0, 1)
                if keyParse.ok {
                    let dictName = stripSuffix(t[start].body, "에서")
                    return .success(dictEnd, CallExpr("사전에서값", [NameExpr(dictName), keyParse.node]))
                }
            }
        }
    }
    // 오프셋 메모리 읽기 `주소에서 타입 값`
    do {
        var mp = start
        var depth = 0
        var cont = true
        while cont && mp + 2 < t.count {
            var isMarker = false
            let b = t[mp].body
            if b == "(" || b == "[" {
                depth += 1
            } else if b == ")" || b == "]" {
                if depth > 0 { depth -= 1 } else { cont = false }
            } else if depth == 0 && b == "," {
                cont = false
            } else if depth == 0 && operatorPrecedence(b) > 0 && operatorPrecedence(b) < 4 {
                cont = false
            } else if depth == 0 {
                if b == "에서" || b.hasSuffix("에서") { isMarker = true }
            }
            if isMarker && stripParticle(t[mp + 2].body) == "값" {
                var addr: [Token] = []
                var a = start
                while a < mp { addr.append(t[a]); a += 1 }
                if t[mp].body != "에서" {
                    var orig = t[mp]
                    orig.body = orig.body.sub(0, orig.body.count - 6)
                    addr.append(orig)
                }
                addr.append(Token(.end, "", t[start].line, 1))
                let ap = parseExpression(addr, 0, 1)
                if !ap.ok { return ap }
                let memNode = N("OffsetMemoryReadExpr", [("address", ap.node), ("value_type", S(t[mp + 1].body))])
                let after = mp + 3
                if after < t.count && operatorPrecedence(t[after].body) > 0 {
                    let op = binarySymbol(t[after].body)
                    let right = parseExpression(t, after + 1, operatorPrecedence(op) + 1)
                    if !right.ok { return right }
                    return .success(right.pos, N("BinaryExpr", [("left", memNode), ("op", S(op)), ("right", right.node)]))
                }
                return .success(mp + 3, memNode)
            }
            if cont { mp += 1 }
        }
    }
    let leftResult = parsePrefix(t, start)
    if !leftResult.ok { return leftResult }
    var pos = leftResult.pos
    var leftNode = leftResult.node
    while pos < t.count {
        let op = binarySymbol(t[pos].body)
        let prec = operatorPrecedence(op)
        if prec == 0 || prec < minPrec { break }
        let right = parseExpression(t, pos + 1, prec + 1)
        if !right.ok { return right }
        leftNode = N("BinaryExpr", [("left", leftNode), ("op", S(op)), ("right", right.node)])
        pos = right.pos
    }
    return .success(pos, leftNode)
}

/// 표현식앞파싱
func parsePrefix(_ t: [Token], _ start: Int) -> ER {
    if start >= t.count { return .failure(start, "표현식이 필요합니다") }
    let tok = t[start]
    var result = ER.failure(start, "표현식 시작 토큰이 올바르지 않습니다")
    if tok.body == "-" || tok.body == "!" || tok.body == "~" {
        let operand = parseExpression(t, start + 1, 10)
        if !operand.ok { return operand }
        result = .success(operand.pos, N("UnaryExpr", [("op", S(tok.body)), ("operand", operand.node)]))
    } else if tok.body == "(" {
        let inner = parseExpression(t, start + 1, 1)
        if !inner.ok { return inner }
        if t.body(inner.pos) != ")" || inner.pos >= t.count { return .failure(inner.pos, "닫는 괄호가 필요합니다") }
        result = .success(inner.pos + 1, inner.node)
    } else if tok.body == "[" {
        var pos = start + 1
        var items: [ASTValue] = []
        if !(pos < t.count && t[pos].body == "]") {
            while true {
                let item = parseExpression(t, pos, 1)
                if !item.ok { return item }
                items.append(item.node)
                pos = item.pos
                if pos < t.count && t[pos].body == "," { pos += 1 } else { break }
            }
        }
        if !(pos < t.count && t[pos].body == "]") { return .failure(pos, "닫는 대괄호가 필요합니다") }
        result = .success(pos + 1, N("ArrayLiteral", [("elements", .array(items))]))
    } else if tok.kind == .int || tok.kind == .hexInt {
        var body = tok.body
        if tok.kind == .hexInt { body = hexLiteralDecimal(tok.body) }
        result = .success(start + 1, N("IntLiteral", [("value", .int(body))]))
    } else if tok.kind == .float {
        result = .success(start + 1, N("FloatLiteral", [("value", .float(tok.body))]))
    } else if tok.kind == .string {
        let sn = plainStringNode(tok.body)
        if sn.isNull { return .failure(start, "문자열 이스케이프가 올바르지 않습니다") }
        result = .success(start + 1, sn)
    } else if tok.body == "함수" && start + 2 < t.count && t[start + 1].body.hasSuffix("의") && t[start + 2].body == "주소" {
        let name = stripSuffix(t[start + 1].body, "의")
        result = .success(start + 3, N("FunctionAddressExpr", [("name", S(name)), ("entry_param_types", .array([]))]))
    } else if tok.kind == .name {
        if start + 1 < t.count && tok.body.hasSuffix("의") && t[start + 1].body == "주소" {
            let name = tok.body.sub(0, tok.body.count - 3)
            result = .success(start + 2, N("AddressOfExpr", [("name", S(name))]))
        } else if start + 1 < t.count && tok.body.hasSuffix("의") && t[start + 1].kind == .name {
            let baseName = tok.body.sub(0, tok.body.count - 3)
            let field = t[start + 1].body
            let base = NameExpr(baseName)
            let objCall = objectPropertyCall(field)
            if objCall.count > 0 {
                result = .success(start + 2, CallExpr(objCall, [base]))
            } else {
                result = .success(start + 2, N("FieldAccessExpr", [("base", base), ("field", S(field))]))
            }
        } else if tok.body == "없음" {
            result = .success(start + 1, N("OptionalNoneExpr", []))
        } else if tok.body == "참" || tok.body == "거짓" {
            result = .success(start + 1, N("BoolLiteral", [("value", B(tok.body == "참"))]))
        } else {
            result = .success(start + 1, NameExpr(tok.body))
        }
    }
    if !result.ok { return result }
    return parsePostfix(t, result)
}

/// AST객체속성호출
func objectPropertyCall(_ field: BStr) -> BStr {
    if field == "식별자" || field == "ID" { return "객체ID" }
    if field == "크기" { return "객체크기" }
    if field == "권한" { return "객체권한" }
    if field == "특징" { return "객체특징" }
    if field == "연결 대상 수" { return "객체연결대상수" }
    if field == "확장자 종류" { return "객체확장자종류" }
    if field == "이름" { return "객체이름" }
    if field == "형식" { return "객체형식" }
    return ""
}

/// 표현식채운인자
func parseFillArgument(_ t: [Token], _ pos0: Int) -> ER {
    var endp = pos0
    var depth = 0
    var fillAt = pos0
    var found = false
    while endp < t.count {
        let b = t[endp].body
        let argEnd = b == ")" || b == ","
        if depth == 0 && argEnd { break }
        if b == "(" || b == "[" { depth += 1 }
        if b == ")" || b == "]" { depth -= 1 }
        if depth == 0 && b == "채운" && !found {
            fillAt = endp
            found = true
        }
        endp += 1
    }
    if !found || fillAt <= pos0 || fillAt + 1 >= endp { return .failure(pos0, "채운 인자가 아닙니다") }
    if t.body(endp - 1) != "고정배열" { return .failure(pos0, "채운 인자가 아닙니다") }
    var vals: [Token] = Array(t[pos0..<fillAt])
    var last = vals[vals.count - 1]
    last.body = stripSuffix(stripSuffix(last.body, "으로"), "로")
    vals[vals.count - 1] = last
    let vp = parseExpression(vals, 0, 1)
    if !vp.ok { return vp }
    let typ = tokenRangeText(t, fillAt + 1, endp)
    return .success(endp, N("FixedArrayFillExpr", [("value", vp.node), ("type_name", S(typ))]))
}

/// 표현식뒤파싱
func parsePostfix(_ t: [Token], _ input: ER) -> ER {
    var result = input
    while true {
        if result.pos < t.count && t[result.pos].body == "(" {
            let hasColon = callHasColon(t, result.pos)
            var pos = result.pos + 1
            var argNodes: [ASTValue] = []
            var fieldKeys: [BStr] = []
            var fieldNodes: [ASTValue] = []
            var named = false
            var updateBase: ASTValue = .null
            if !(pos < t.count && t[pos].body == ")") {
                while true {
                    var fieldName: BStr = ""
                    if pos + 1 < t.count && t[pos].kind == .name && t[pos + 1].body == ":" {
                        named = true
                        fieldName = t[pos].body
                        pos += 2
                    } else if named {
                        return .failure(pos, "이름 붙은 인자와 위치 인자를 섞을 수 없습니다")
                    }
                    let argStart = pos
                    var arg = parseFillArgument(t, pos)
                    if !arg.ok { arg = parseExpression(t, pos, 1) }
                    if !arg.ok { return arg }
                    if (!hasColon || named) && arg.pos == argStart + 1 && t[safe: argStart].kind == .string {
                        let interp = interpolatedStringNode(t[argStart].body)
                        if !interp.isNull { arg = .success(arg.pos, interp) }
                    }
                    if named {
                        fieldKeys.append(fieldName)
                        fieldNodes.append(arg.node)
                    } else if argNodes.count == 0 && t.body(arg.pos - 1).hasSuffix("에서") {
                        updateBase = cleanStructUpdateBase(arg.node)
                    } else {
                        argNodes.append(arg.node)
                    }
                    pos = arg.pos
                    if pos < t.count && t[pos].body == "," { pos += 1 } else { break }
                }
            }
            if !(pos < t.count && t[pos].body == ")") { return .failure(pos, "호출의 닫는 괄호가 필요합니다") }
            if result.node.kind != "NameExpr" { return .failure(result.pos, "호출 대상은 함수 이름이어야 합니다") }
            let callee = result.node.str("name")
            if named {
                let fields: ASTValue = .object(Array(zip(fieldKeys, fieldNodes)))
                result = .success(pos + 1, N("StructInitExpr", [
                    ("name", S(callee)), ("fields", fields), ("unsafe", B(false)), ("base", updateBase), ("compiler_generated", B(false)),
                ]))
            } else if isPrimitiveTypeName(callee) && argNodes.count == 1 {
                result = .success(pos + 1, N("CastExpr", [("type_name", S(callee)), ("expr", argNodes[0]), ("compiler_generated", B(false))]))
            } else {
                result = .success(pos + 1, CallExpr(callee, argNodes))
            }
        } else if result.pos < t.count && t[result.pos].body == "." {
            if result.pos + 1 >= t.count || t[result.pos + 1].kind != .name {
                return .failure(result.pos + 1, "필드 이름이 필요합니다")
            }
            var field = t[result.pos + 1].body
            if result.pos + 2 < t.count {
                let nb = t[result.pos + 2].body
                if nb == "있으면" || nb == "없으면" || nb == "아니면" || nb == "아니거나" {
                    if field.hasSuffix("이") || field.hasSuffix("가") { field = field.sub(0, field.count - 3) }
                }
            }
            result = .success(result.pos + 2, N("FieldAccessExpr", [("base", result.node), ("field", S(field))]))
        } else if result.pos < t.count && t[result.pos].body == "[" {
            let idx = parseExpression(t, result.pos + 1, 1)
            if !idx.ok { return idx }
            if !(idx.pos < t.count && t[idx.pos].body == "]") { return .failure(idx.pos, "첨자의 닫는 대괄호가 필요합니다") }
            result = .success(idx.pos + 1, N("IndexAccessExpr", [("base", result.node), ("index", idx.node), ("natural", B(false))]))
        } else if result.pos < t.count && t[result.pos].body == "!" {
            result = .success(result.pos + 1, N("OptionalUnwrapExpr", [("expr", result.node)]))
        } else if (t.body(result.pos) == "을" || t.body(result.pos) == "를") && result.pos + 1 < t.count
                    && t[result.pos + 1].body == "시도한" && stripParticle(t.body(result.pos + 2)) == "값" {
            result = .success(result.pos + 3, N("TryExpr", [("expr", result.node)]))
        } else {
            break
        }
    }
    return result
}
