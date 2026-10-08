// 프론트엔드/문장파서.hmje 앞부분: 토큰 범위 도우미와 `파싱표현식범위` 계열.
// 문장 끝 조사를 떼고, 자연어 통짜 규칙(채운 고정배열, 기다린 결과, …의 값 등)을
// 먼저 본 뒤 Pratt 파서로 넘긴다. 규칙 순서가 곧 의미이므로 원본 순서를 지킨다.

// MARK: - 토큰 범위 도우미

/// 파싱줄끝
func lineEnd(_ t: [Token], _ start: Int) -> Int {
    var pos = start
    var depth = 0
    while pos < t.count && t[pos].kind != .end {
        if t[pos].kind == .newline && depth == 0 { break }
        let b = t[pos].body
        if b == "(" || b == "[" || b == "{" {
            depth += 1
        } else if depth > 0 {
            if b == ")" || b == "]" || b == "}" { depth -= 1 }
        }
        pos += 1
    }
    return pos
}

/// 파싱최상위쉼표
func topLevelComma(_ t: [Token], _ start: Int, _ end: Int) -> Int {
    var pos = start
    var depth = 0
    while pos < end {
        let b = t[pos].body
        if b == "(" || b == "[" || b == "{" {
            depth += 1
        } else if b == ")" || b == "]" || b == "}" {
            if depth > 0 { depth -= 1 }
        } else if b == "," && depth == 0 {
            return pos
        }
        pos += 1
    }
    return end
}

/// 파싱최상위콜론점
func topLevelColon(_ t: [Token], _ start: Int, _ end: Int) -> Int {
    var pos = start
    var depth = 0
    while pos < end {
        let b = t[pos].body
        if b == "(" || b == "[" || b == "{" {
            depth += 1
        } else if b == ")" || b == "]" || b == "}" {
            if depth > 0 { depth -= 1 }
        } else if depth == 0 && b == ":" {
            return pos
        }
        pos += 1
    }
    return end
}

/// 파싱최상위콜론수
func topLevelColonCount(_ t: [Token], _ start: Int, _ end: Int) -> Int {
    var pos = start
    var depth = 0
    var n = 0
    while pos < end {
        let b = t[pos].body
        if b == "(" || b == "[" || b == "{" {
            depth += 1
        } else if b == ")" || b == "]" || b == "}" {
            if depth > 0 { depth -= 1 }
        } else if depth == 0 && b == ":" {
            n += 1
        }
        pos += 1
    }
    return n
}

/// 파싱토큰범위본문: 원문 열 간격이 있으면 공백 하나로 잇는다.
func tokenRangeText(_ t: [Token], _ start: Int, _ end: Int) -> BStr {
    var out: [UInt8] = []
    var pos = start
    var prevEnd = 0
    while pos < end {
        let tok = t[safe: pos]
        if pos > start && tok.col > prevEnd { out.append(32) }
        tok.body.withBytes { out.append(contentsOf: $0) }
        prevEnd = tok.col + tok.body.count
        pos += 1
    }
    return BStr(out)
}

/// 파싱최상위논리: 깊이 0의 마지막 연산자 자리(없으면 끝).
func topLevelLogic(_ t: [Token], _ start: Int, _ end: Int, _ op: BStr) -> Int {
    var pos = start
    var depth = 0
    var at = end
    while pos < end {
        let b = t[pos].body
        if b == "(" || b == "[" {
            depth += 1
        } else if b == ")" || b == "]" {
            if depth > 0 { depth -= 1 }
        } else if depth == 0 && b == op {
            at = pos
        }
        pos += 1
    }
    return at
}

/// 파싱최상위비교: 깊이 0의 첫 비교 연산자 자리.
func topLevelCompare(_ t: [Token], _ start: Int, _ end: Int) -> Int {
    var pos = start
    var depth = 0
    while pos < end {
        let b = t[pos].body
        if b == "(" || b == "[" {
            depth += 1
        } else if b == ")" || b == "]" {
            if depth > 0 { depth -= 1 }
        } else if depth == 0 {
            if b == "==" || b == "!=" || b == "<" || b == "<=" || b == ">" || b == ">=" { return pos }
        }
        pos += 1
    }
    return end
}

/// 파싱목적격점: 깊이 0의 마지막 목적격 토큰.
func objectParticlePoint(_ t: [Token], _ start: Int, _ end: Int) -> Int {
    var pos = start
    var depth = 0
    var at = end
    while pos < end {
        let b = t[pos].body
        if b == "(" || b == "[" {
            depth += 1
        } else if b == ")" || b == "]" {
            if depth > 0 { depth -= 1 }
        } else if depth == 0 && isObjectParticle(b) {
            at = pos
        }
        pos += 1
    }
    return at
}

/// 파싱다음줄
func nextLine(_ t: [Token], _ start: Int) -> Int {
    var pos = start
    if pos < t.count && t[pos].kind == .newline { pos += 1 }
    while pos < t.count && t[pos].kind == .newline { pos += 1 }
    return pos
}

@inline(__always) func isPunctEnd(_ b: BStr) -> Bool { b == "." || b == "," }
@inline(__always) func isGrammarEnd(_ b: BStr) -> Bool { b == "을" || b == "를" || b == "이면" || b == "이다" }
@inline(__always) func isExistenceEnd(_ b: BStr) -> Bool { b == "있으면" || b == "없으면" }
/// 파싱목적격인가
@inline(__always) func isObjectParticle(_ b: BStr) -> Bool {
    b == "을" || b == "를" || b.hasSuffix("을") || b.hasSuffix("를")
}
@inline(__always) func isDeferredTypeEnd(_ b: BStr) -> Bool { b.hasSuffix("집합이다") || b.hasSuffix("사전이다") }
func isDictSetType(_ typ: BStr) -> Bool {
    typ.hasSuffix("를 찾는 사전") || typ.hasSuffix("을 찾는 사전") || typ.hasSuffix("의 집합")
}
@inline(__always) func isCollectionAddVerb(_ b: BStr) -> Bool { b == "추가한다" || b == "넣는다" }
/// 파싱주격끝인가
@inline(__always) func endsSubject(_ b: BStr) -> Bool { b.hasSuffix("이") || b.hasSuffix("가") }
/// 파싱주격제거
func stripSubject(_ b: BStr) -> BStr { b.hasSuffix("가") ? stripSuffix(b, "가") : stripSuffix(b, "이") }
@inline(__always) func endsComitative(_ b: BStr) -> Bool { b.hasSuffix("와") || b.hasSuffix("과") }
/// 파싱목적격끝인가
@inline(__always) func endsObject(_ b: BStr) -> Bool { b.hasSuffix("을") || b.hasSuffix("를") }
func stripObject(_ b: BStr) -> BStr { b.hasSuffix("를") ? stripSuffix(b, "를") : stripSuffix(b, "을") }
@inline(__always) func isObjectParticleExact(_ b: BStr) -> Bool { b == "을" || b == "를" }
/// 파싱대입조사인가
@inline(__always) func isAssignParticle(_ b: BStr) -> Bool {
    b == "은" || b == "는" || b.hasSuffix("은") || b.hasSuffix("는")
}
@inline(__always) func isBorrowVerb(_ b: BStr) -> Bool { b == "빌려온다" || b == "가져온다" }
func isDeprecatedPrefixNot(_ t: [Token], _ start: Int, _ end: Int) -> Bool {
    end > start + 1 && t.body(start) == "아니다"
}
let deprecatedPrefixNotError = "앞 수식 '아니다 조건'은 폐기되었습니다. '조건이 아니면', '조건이 아니고', '조건이 아닐 동안'을 사용하세요."

func isFunctionModifier(_ b: BStr) -> Bool {
    b.hasPrefix("위험") || b == "공개" || b == "비동기" || b == "비동기인" || b == "비동기이며" || b == "실패할" || b == "수"
        || b == "있고" || b == "프로젝트" || b == "모듈" || b == "파일" || b == "내부"
}

/// 파싱토큰범위복사: 마지막 토큰의 접미사를 떼고, 빈 토큰은 버린다.
func copyRange(_ t: [Token], _ start: Int, _ end: Int, _ suffix: BStr) -> [Token] {
    var out: [Token] = []
    var i = start
    while i < end {
        var tok = t[safe: i]
        if i + 1 == end && suffix.count > 0 {
            tok.body = tok.body == suffix ? "" : stripSuffix(tok.body, suffix)
        }
        if tok.body.count > 0 { out.append(tok) }
        i += 1
    }
    return out
}

@inline(__always) func isGlobalKind(_ b: BStr) -> Bool { b == "상수" || b == "변수" }

/// 파싱이다제거
func stripIda(_ b: BStr) -> BStr {
    var r = stripSuffix(b, "이다")
    while r.hasSuffix(" ") { r = r.sub(0, r.count - 1) }
    return r
}

// MARK: - 범위 표현식

/// 파싱범위소비검사
func checkRangeConsumed(_ r: ER, _ pieces: [Token], _ t: [Token], _ start: Int, _ end: Int) -> ER {
    if !r.ok { return r }
    if r.pos + 1 == pieces.count { return r }
    return .failure(start, "이해할 수 없는 문법입니다: " + tokenRangeText(t, start, end).string)
}

/// 파싱그대로표현식범위
func parseVerbatimRange(_ t: [Token], _ start: Int, _ end: Int) -> ER {
    var pieces: [Token] = []
    var i = start
    while i < end {
        if t[i].body.count > 0 { pieces.append(t[i]) }
        i += 1
    }
    pieces.append(Token(.end, "", t[safe: start].line, 1))
    let r = parseExpression(pieces, 0, 1)
    return checkRangeConsumed(r, pieces, t, start, end)
}

/// 파싱정확표현식범위: 마지막 토큰의 `이면`만 뗀다.
func parseExactRange(_ t: [Token], _ start: Int, _ end: Int) -> ER {
    var pieces: [Token] = []
    var i = start
    while i < end {
        var tok = t[i]
        if i + 1 == end && tok.body.hasSuffix("이면") { tok.body = stripSuffix(tok.body, "이면") }
        if tok.body.count > 0 { pieces.append(tok) }
        i += 1
    }
    pieces.append(Token(.end, "", t[safe: start].line, 1))
    let r = parseExpression(pieces, 0, 1)
    return checkRangeConsumed(r, pieces, t, start, end)
}

/// 파싱반복정수식
func intLiteralNode(_ v: Int) -> ASTValue { IntLit(v) }

func castNatural64(_ e: ASTValue) -> ASTValue {
    N("CastExpr", [("type_name", S("자연수64")), ("expr", e), ("compiler_generated", B(false))])
}

/// 파싱표현식범위
func parseRange(_ t: [Token], _ start: Int, _ end: Int) -> ER {
    var realEnd = end
    while realEnd > start && isPunctEnd(t[realEnd - 1].body) { realEnd -= 1 }
    while realEnd > start && isGrammarEnd(t[realEnd - 1].body) { realEnd -= 1 }
    // `값으로 채운 타입 N개의 고정배열`
    var fillAt = start
    while fillAt < realEnd && t[fillAt].body != "채운" { fillAt += 1 }
    var fillEndBody = t.body(realEnd - 1)
    if realEnd > start {
        fillEndBody = stripSuffix(stripSuffix(stripSuffix(stripSuffix(fillEndBody, "이고"), "이다"), "을"), "를")
    }
    if fillAt > start && fillAt + 1 < realEnd && fillEndBody == "고정배열" {
        var vals: [Token] = Array(t[start..<fillAt])
        var last = vals[vals.count - 1]
        last.body = stripSuffix(stripSuffix(last.body, "으로"), "로")
        vals[vals.count - 1] = last
        let vp = parseRange(vals, 0, vals.count)
        if !vp.ok { return vp }
        var typ = tokenRangeText(t, fillAt + 1, realEnd)
        typ = stripSuffix(stripSuffix(stripSuffix(stripSuffix(typ, "이고"), "이다"), "을"), "를")
        return .success(realEnd - start, N("FixedArrayFillExpr", [("value", vp.node), ("type_name", S(typ))]))
    }
    var awaitEnd = false
    if realEnd > start && stripParticle(t[realEnd - 1].body) == "결과" { awaitEnd = true }
    if realEnd == start + 3 && t[start].body.hasSuffix("에서") && t[start + 1].body == "받은" && stripParticle(t[start + 2].body) == "값" {
        let recv = NameExpr(stripSuffix(t[start].body, "에서"))
        return .success(realEnd - start, N("ChannelReceiveExpr", [("receiver", recv)]))
    }
    if realEnd == start + 4 && t[start].body.hasSuffix("에서") && t[start + 1].body == "받기를" && t[start + 2].body == "기다린" && awaitEnd {
        let recv = NameExpr(stripSuffix(t[start].body, "에서"))
        return .success(realEnd - start, N("ChannelAsyncReceiveExpr", [("receiver", recv)]))
    }
    if realEnd >= start + 5 && t[realEnd - 3].body == "보내기를" && t[realEnd - 2].body == "기다린" && awaitEnd {
        var senderName = stripSuffix(t[realEnd - 4].body, "으로")
        senderName = stripSuffix(senderName, "로")
        var vals: [Token] = []
        var i = start
        while i < realEnd - 4 {
            var tok = t[i]
            if i + 1 == realEnd - 4 { tok.body = stripSuffix(stripSuffix(tok.body, "을"), "를") }
            vals.append(tok)
            i += 1
        }
        let vp = parseVerbatimRange(vals, 0, vals.count)
        if !vp.ok { return vp }
        return .success(realEnd - start, N("ChannelAsyncSendExpr", [("value", vp.node), ("sender", NameExpr(senderName))]))
    }
    if realEnd >= start + 4 && t[realEnd - 2].body == "보내본" && awaitEnd {
        var senderName = stripSuffix(t[realEnd - 3].body, "으로")
        senderName = stripSuffix(senderName, "로")
        var vals: [Token] = []
        var i = start
        while i < realEnd - 3 {
            var tok = t[i]
            if i + 1 == realEnd - 3 { tok.body = stripSuffix(stripSuffix(tok.body, "을"), "를") }
            vals.append(tok)
            i += 1
        }
        let vp = parseVerbatimRange(vals, 0, vals.count)
        if !vp.ok { return vp }
        return .success(realEnd - start, N("ChannelTrySendExpr", [("value", vp.node), ("sender", NameExpr(senderName))]))
    }
    if realEnd >= start + 3 && t[realEnd - 2].body == "기다린" && awaitEnd {
        let call = parseRange(t, start, realEnd - 2)
        if !call.ok { return call }
        if call.node.kind != "CallExpr" { return .failure(start, "기다린 결과의 앞은 비동기 호출이어야 합니다") }
        return .success(realEnd - start, N("AwaitExpr", [("call", call.node)]))
    }
    if realEnd == start + 1 && t[start].kind == .string {
        let n = interpolatedStringNode(t[start].body)
        if n.isNull { return .failure(start, "문자열 이스케이프가 올바르지 않습니다") }
        return .success(1, n)
    }
    if realEnd == start + 2 && t[start].body == "파일" && t[start + 1].kind == .string {
        guard let path = jsonParseStringDocument(t[start + 1].body) else {
            return .failure(start, "파일 경로가 올바르지 않습니다")
        }
        return .success(2, N("FileDataExpr", [("path", S(path))]))
    }
    if realEnd == start + 3 && t[start].body == "함수" && t[start + 1].body.hasSuffix("의") && stripParticle(t[start + 2].body) == "주소" {
        let name = stripSuffix(t[start + 1].body, "의")
        return .success(3, N("FunctionAddressExpr", [("name", S(name)), ("entry_param_types", .array([]))]))
    }
    if realEnd == start + 4 && t[start].body.hasSuffix("에서") && t[start + 1].body == "마지막" && t[start + 2].body == "값을" && t[start + 3].body == "꺼낸다" {
        let name = stripSuffix(t[start].body, "에서")
        return .success(4, N("DynamicArrayPopExpr", [("name", S(name))]))
    }
    var ordAt = start
    while ordAt < realEnd && t[ordAt].body != "번째" { ordAt += 1 }
    if ordAt < realEnd && t[start].body.hasSuffix("의") && ordAt + 2 < realEnd && stripParticle(t[ordAt + 2].body) == "값" {
        let baseName = stripSuffix(t[start].body, "의")
        let idx = parseRange(t, start + 1, ordAt)
        if !idx.ok { return idx }
        let node = N("MemoryReadExpr", [("base", NameExpr(baseName)), ("index", idx.node), ("value_type", S(t[ordAt + 1].body))])
        return .success(realEnd - start, node)
    }
    // 두 토큰짜리 자연어 속성
    if realEnd >= start + 3 {
        let tail = stripParticle(t[realEnd - 1].body)
        let mid = t[realEnd - 2].body
        var callName: BStr = ""
        if tail == "길이" && mid == "바이트" { callName = "문자열바이트길이" }
        else if tail == "주소" && mid == "데이터" { callName = "문자열주소" }
        else if tail == "종류" && mid == "확장자" { callName = "객체확장자종류" }
        else if tail == "값" || tail == "요소" {
            if mid == "마지막" { callName = "마지막값" }
            else if mid == "첫" || mid == "첫번째" { callName = "첫번째값" }
        }
        if callName.count > 0 && t[realEnd - 3].body.hasSuffix("의") {
            let baseToks = copyRange(t, start, realEnd - 2, "의")
            if baseToks.count > 0 {
                let base = parseVerbatimRange(baseToks, 0, baseToks.count)
                if !base.ok { return base }
                return .success(realEnd - start, CallExpr(callName, [base.node]))
            }
        }
    }
    // `X의 N번째 연결 대상 이름|식별자|ID|관계|특징`
    if realEnd >= start + 6 && t[realEnd - 2].body == "대상" && t[realEnd - 3].body == "연결" && t[realEnd - 4].body == "번째" && t[start].body.hasSuffix("의") {
        let tail = stripParticle(stripIda(stripSuffix(t[realEnd - 1].body, "이고")))
        var callName: BStr = ""
        if tail == "이름" { callName = "객체연결대상이름문자열" }
        else if tail == "식별자" || tail == "ID" { callName = "객체연결대상ID" }
        else if tail == "관계" { callName = "객체연결대상관계" }
        else if tail == "특징" { callName = "객체연결대상특징" }
        if callName.count > 0 {
            let baseToks = copyRange(t, start, start + 1, "의")
            let idxToks = copyRange(t, start + 1, realEnd - 4, "")
            if baseToks.count > 0 && idxToks.count > 0 {
                let base = parseVerbatimRange(baseToks, 0, baseToks.count)
                if !base.ok { return base }
                let idx = parseVerbatimRange(idxToks, 0, idxToks.count)
                if !idx.ok { return idx }
                let sub = N("BinaryExpr", [("left", idx.node), ("op", S("-")), ("right", IntLit(1))])
                return .success(realEnd - start, CallExpr(callName, [base.node, castNatural64(sub)]))
            }
        }
    }
    // `X의 연결 대상 수`
    if realEnd >= start + 4 && stripParticle(t[realEnd - 1].body) == "수" && t[realEnd - 2].body == "대상" && t[realEnd - 3].body == "연결" && t[realEnd - 4].body.hasSuffix("의") {
        let baseToks = copyRange(t, start, realEnd - 3, "의")
        if baseToks.count > 0 {
            let base = parseVerbatimRange(baseToks, 0, baseToks.count)
            if !base.ok { return base }
            return .success(realEnd - start, CallExpr("객체연결대상수", [base.node]))
        }
    }
    // `X의 길이|용량|최솟값|최댓값` (바탕이 여러 토큰)
    if realEnd >= start + 3 && t[realEnd - 2].body.hasSuffix("의") {
        let tail = stripParticle(t[realEnd - 1].body)
        var name: BStr = ""
        if tail == "길이" { name = "자연어길이" }
        else if tail == "용량" { name = "자연어용량" }
        else if tail == "최솟값" { name = "최솟값" }
        else if tail == "최댓값" { name = "최댓값" }
        if name.count > 0 {
            let baseToks = copyRange(t, start, realEnd - 1, "의")
            if baseToks.count > 0 {
                let base = parseVerbatimRange(baseToks, 0, baseToks.count)
                if !base.ok { return base }
                return .success(realEnd - start, CallExpr(name, [base.node]))
            }
        }
    }
    // `첫 번째 값`
    if realEnd >= start + 4 && t[realEnd - 3].body == "첫" && t[realEnd - 2].body == "번째" && t[realEnd - 4].body.hasSuffix("의") {
        let tail = stripParticle(t[realEnd - 1].body)
        if tail == "값" || tail == "요소" {
            let baseToks = copyRange(t, start, realEnd - 3, "의")
            if baseToks.count > 0 {
                let base = parseVerbatimRange(baseToks, 0, baseToks.count)
                if !base.ok { return base }
                return .success(realEnd - start, CallExpr("첫번째값", [base.node]))
            }
        }
    }
    // `이름의 N번째 [요소|값]`: 1기반 순번 첨자
    if realEnd >= start + 2 && t[start].kind == .name && t[start].body.hasSuffix("의") && t[start].body.count > 3 {
        var ordEnd = realEnd
        let ordTail = stripParticle(t[realEnd - 1].body)
        if ordTail == "요소" || ordTail == "값" { ordEnd = realEnd - 1 }
        if ordEnd > start + 1 {
            let ordLast = stripParticle(t[ordEnd - 1].body)
            var idxToks: [Token] = []
            var matched = false
            if ordLast == "번째" {
                if ordEnd > start + 2 {
                    matched = true
                    idxToks = copyRange(t, start + 1, ordEnd - 1, "")
                }
            } else if ordLast.hasSuffix("번째") {
                matched = true
                idxToks = copyRange(t, start + 1, ordEnd - 1, "")
                var orig = t[ordEnd - 1]
                orig.body = stripSuffix(ordLast, "번째")
                idxToks.append(orig)
            }
            if matched {
                let idx = parseVerbatimRange(idxToks, 0, idxToks.count)
                if !idx.ok { return idx }
                let base = NameExpr(stripSuffix(t[start].body, "의"))
                return .success(realEnd - start, N("IndexAccessExpr", [("base", base), ("index", idx.node), ("natural", B(true))]))
            }
        }
    }
    if realEnd == start + 3 && t[start].body.hasSuffix("에서") && stripParticle(t[start + 2].body) == "값" {
        let addr = NameExpr(stripSuffix(t[start].body, "에서"))
        return .success(3, N("OffsetMemoryReadExpr", [("address", addr), ("value_type", S(t[start + 1].body))]))
    }
    if realEnd >= start + 4 && t[realEnd - 3].body == "에서" && stripParticle(t[realEnd - 1].body) == "값" {
        let ap = parseRange(t, start, realEnd - 3)
        if !ap.ok { return ap }
        return .success(realEnd - start, N("OffsetMemoryReadExpr", [("address", ap.node), ("value_type", S(t[realEnd - 2].body))]))
    }
    // 넓은 오프셋 읽기: 타입이 여러 토큰
    if realEnd >= start + 4 && stripParticle(t[realEnd - 1].body) == "값" {
        var fromAt = start
        var found = false
        while fromAt + 2 < realEnd - 1 && !found {
            if t[fromAt].body.hasSuffix("에서") { found = true } else { fromAt += 1 }
        }
        if found {
            var typeOK = true
            var tp = fromAt + 1
            while tp < realEnd - 1 {
                if t[tp].kind != .name { typeOK = false }
                if t[tp].body.hasSuffix("의") && tp + 2 > realEnd - 1 { typeOK = false }
                tp += 1
            }
            if typeOK {
                let addrToks = copyRange(t, start, fromAt + 1, "에서")
                if addrToks.count > 0 {
                    let ap = parseVerbatimRange(addrToks, 0, addrToks.count)
                    if ap.ok {
                        let typ = tokenRangeText(t, fromAt + 1, realEnd - 1)
                        return .success(realEnd - start, N("OffsetMemoryReadExpr", [("address", ap.node), ("value_type", S(typ))]))
                    }
                }
            }
        }
    }
    // `X가 비었는지`
    if realEnd >= start + 2 && stripParticle(t[realEnd - 1].body) == "비었는지" && endsSubject(t[realEnd - 2].body) {
        var toks = copyRange(t, start, realEnd - 1, "")
        if toks.count > 0 {
            toks[toks.count - 1].body = stripSubject(toks[toks.count - 1].body)
            let base = parseVerbatimRange(toks, 0, toks.count)
            if !base.ok { return base }
            return .success(realEnd - start, CallExpr("자연어비었는지", [base.node]))
        }
    }
    // `A에 B가 포함되는지`
    if realEnd >= start + 3 && stripParticle(t[realEnd - 1].body) == "포함되는지" && endsSubject(t[realEnd - 2].body) {
        var at = start
        while at + 1 < realEnd - 1 && !t[at].body.hasSuffix("에") { at += 1 }
        if t[at].body.hasSuffix("에") && at + 1 < realEnd - 1 {
            let colToks = copyRange(t, start, at + 1, "에")
            var valToks = copyRange(t, at + 1, realEnd - 1, "")
            if colToks.count > 0 && valToks.count > 0 {
                valToks[valToks.count - 1].body = stripSubject(valToks[valToks.count - 1].body)
                let col = parseVerbatimRange(colToks, 0, colToks.count)
                if !col.ok { return col }
                let val = parseVerbatimRange(valToks, 0, valToks.count)
                if !val.ok { return val }
                return .success(realEnd - start, CallExpr("포함되는지", [col.node, val.node]))
            }
        }
    }
    // `이름 관계를 설명으로 등록한 값`
    if realEnd >= start + 5 && stripIda(stripParticle(t[realEnd - 1].body)) == "값" && t[realEnd - 2].body == "등록한" {
        if t[realEnd - 3].body == "설명으로" || t[realEnd - 3].body == "설명로" {
            var relAt = start
            while relAt + 1 < realEnd - 3 && t[relAt].body != "관계를" && t[relAt].body != "관계을" { relAt += 1 }
            if t[relAt].body == "관계를" || t[relAt].body == "관계을" {
                let nameToks = copyRange(t, start, relAt, "")
                let descToks = copyRange(t, relAt + 1, realEnd - 3, "")
                if nameToks.count > 0 && descToks.count > 0 {
                    let nm = parseVerbatimRange(nameToks, 0, nameToks.count)
                    if !nm.ok { return nm }
                    let ds = parseVerbatimRange(descToks, 0, descToks.count)
                    if !ds.ok { return ds }
                    return .success(realEnd - start, CallExpr("객체관계등록값", [nm.node, ds.node]))
                }
            }
        }
    }
    // `바탕에 연결된 객체들|파일들`
    if realEnd >= start + 3 && t[realEnd - 2].body == "연결된" && t[realEnd - 3].body.hasSuffix("에") {
        let tail = stripIda(stripParticle(t[realEnd - 1].body))
        var fn: BStr = ""
        if tail == "객체들" { fn = "객체연결대상들" } else if tail == "파일들" { fn = "객체연결파일들" }
        if fn != "" {
            let baseToks = copyRange(t, start, realEnd - 2, "에")
            let base = parseVerbatimRange(baseToks, 0, baseToks.count)
            if !base.ok { return base }
            return .success(realEnd - start, N("CallExpr", [("name", S(fn)), ("args", .array([base.node]))]))
        }
    }
    // `바탕에서 관계로 나가는|들어오는|연결된 관계들|객체들`
    if realEnd >= start + 4 {
        let tail = stripIda(stripParticle(t[realEnd - 1].body))
        let dir = t[realEnd - 2].body
        var callName: BStr = ""
        if tail == "관계들" {
            if dir == "나가는" { callName = "객체나가는엣지들" }
            else if dir == "들어오는" { callName = "객체들어오는엣지들" }
            else if dir == "연결된" { callName = "객체연결엣지들" }
        } else if tail == "객체들" {
            if dir == "나가는" { callName = "객체나가는객체들" }
            else if dir == "들어오는" { callName = "객체들어오는객체들" }
            else if dir == "연결된" { callName = "객체연결객체들" }
        }
        if callName.count > 0 {
            var at = start
            while at + 1 < realEnd - 2 && !t[at].body.hasSuffix("에서") { at += 1 }
            if t[at].body.hasSuffix("에서") && at + 1 < realEnd - 2 {
                var relP: BStr = "로"
                if t[realEnd - 3].body.hasSuffix("으로") { relP = "으로" }
                let baseToks = copyRange(t, start, at + 1, "에서")
                let relToks = copyRange(t, at + 1, realEnd - 2, relP)
                if baseToks.count > 0 && relToks.count > 0 {
                    let base = parseVerbatimRange(baseToks, 0, baseToks.count)
                    if !base.ok { return base }
                    let rel = parseVerbatimRange(relToks, 0, relToks.count)
                    if !rel.ok { return rel }
                    return .success(realEnd - start, CallExpr(callName, [base.node, rel.node]))
                }
            }
        }
    }
    // `바탕에서 "이름"을 연다`
    if realEnd >= start + 4 && t[realEnd - 1].body == "연다" && t[realEnd - 3].kind == .string && isObjectParticle(t[realEnd - 2].body) {
        var at = start
        while at + 1 < realEnd - 3 && !t[at].body.hasSuffix("에서") { at += 1 }
        if t[at].body.hasSuffix("에서") && at + 1 == realEnd - 3 {
            let baseToks = copyRange(t, start, at + 1, "에서")
            if baseToks.count > 0 {
                let base = parseVerbatimRange(baseToks, 0, baseToks.count)
                if !base.ok { return base }
                let nameNode = plainStringNode(t[realEnd - 3].body)
                if nameNode.isNull { return .failure(start, "문자열 이스케이프가 올바르지 않습니다") }
                return .success(realEnd - start, CallExpr("객체연결대상열기", [base.node, nameNode]))
            }
        }
    }
    // `X의 N번째 바이트`
    if realEnd >= start + 4 && stripParticle(t[realEnd - 1].body) == "바이트" && t[realEnd - 2].body == "번째" && t[start].body.hasSuffix("의") {
        let baseToks = copyRange(t, start, start + 1, "의")
        let idxToks = copyRange(t, start + 1, realEnd - 2, "")
        if baseToks.count > 0 && idxToks.count > 0 {
            let base = parseVerbatimRange(baseToks, 0, baseToks.count)
            if !base.ok { return base }
            let idx = parseVerbatimRange(idxToks, 0, idxToks.count)
            if !idx.ok { return idx }
            let sub = N("BinaryExpr", [("left", idx.node), ("op", S("-")), ("right", IntLit(1))])
            return .success(realEnd - start, CallExpr("문자열바이트", [base.node, castNatural64(sub)]))
        }
    }
    // `바탕에 값을 붙인 값`
    if realEnd >= start + 4 && stripIda(stripParticle(t[realEnd - 1].body)) == "값" && t[realEnd - 2].body == "붙인" && endsObject(t[realEnd - 3].body) {
        var at = start
        while at + 1 < realEnd - 2 && !t[at].body.hasSuffix("에") { at += 1 }
        if t[at].body.hasSuffix("에") && at + 1 < realEnd - 2 {
            var objP: BStr = "를"
            if t[realEnd - 3].body.hasSuffix("을") { objP = "을" }
            let baseToks = copyRange(t, start, at + 1, "에")
            let valToks = copyRange(t, at + 1, realEnd - 2, objP)
            if baseToks.count > 0 && valToks.count > 0 {
                let base = parseVerbatimRange(baseToks, 0, baseToks.count)
                if !base.ok { return base }
                let val = parseVerbatimRange(valToks, 0, valToks.count)
                if !val.ok { return val }
                return .success(realEnd - start, CallExpr("문자열붙인값", [base.node, val.node]))
            }
        }
    }
    if realEnd == start + 2 && t[start].body == "빈" && stripIda(stripParticle(t[start + 1].body)) == "문자열" {
        return .success(2, CallExpr("빈문자열", []))
    }
    if realEnd == start + 2 && t[start].body == "새" && stripIda(stripParticle(t[start + 1].body)) == "객체" {
        return .success(2, CallExpr("객체만들기", []))
    }
    // `A의 B의 C` 필드 사슬
    if realEnd >= start + 3 {
        var chainOK = true
        var i = start
        while i < realEnd {
            if t[i].kind != .name { chainOK = false }
            if i + 1 < realEnd {
                if !t[i].body.hasSuffix("의") || t[i].body.count <= 3 { chainOK = false }
            }
            i += 1
        }
        let lastSeg = stripParticle(t[realEnd - 1].body)
        if lastSeg.count == 0 || lastSeg.hasSuffix("의") { chainOK = false }
        if chainOK {
            var node = NameExpr(stripSuffix(t[start].body, "의"))
            var at = start + 1
            while at < realEnd {
                var field = t[at].body
                if at + 1 < realEnd { field = stripSuffix(field, "의") } else { field = lastSeg }
                node = N("FieldAccessExpr", [("base", node), ("field", S(field))])
                at += 1
            }
            return .success(realEnd - start, node)
        }
    }
    var pieces: [Token] = []
    var p = start
    while p < realEnd {
        var tok = t[p]
        if tok.kind != .newline && tok.kind != .indent && tok.kind != .dedent {
            if p + 1 == realEnd { tok.body = stripParticle(tok.body) }
            if tok.body.count > 0 { pieces.append(tok) }
        }
        p += 1
    }
    pieces.append(Token(.end, "", t[safe: start].line, 1))
    let r = parseExpression(pieces, 0, 1)
    return checkRangeConsumed(r, pieces, t, start, realEnd)
}
