// 프론트엔드/문장파서.hmje의 문장 파서(파싱한문장·파싱블록·소스문장파싱) 이식.
// 문장 규칙의 순서가 곧 우선순위다. 원본의 갈래 순서를 그대로 따른다.

/// 문장파싱결과
struct SR {
    var ok: Bool
    var pos: Int
    var stmts: [LineStmt]
    var err: String
    static func success(_ pos: Int, _ stmts: [LineStmt]) -> SR { SR(ok: true, pos: pos, stmts: stmts, err: "") }
    static func failure(_ pos: Int, _ err: String) -> SR { SR(ok: false, pos: pos, stmts: [], err: err) }
}

public struct ParseResult {
    public var ok: Bool
    public var statements: [LineStmt]
    public var error: String
}

/// 소스문장파싱: 파일 하나를 줄 문장 목록으로.
public func parseSource(_ source: String, startLine: Int = 1) -> ParseResult {
    parseSource(bytes: Array(source.utf8), startLine: startLine)
}

/// `env`: 정본 소스문장파싱줄부터환경의 초기환경(적재기가 넘기는 의존 모듈 문장들).
public func parseSource(bytes: [UInt8], startLine: Int = 1, env initialEnv: [LineStmt] = []) -> ParseResult {
    let tk = tokenize(bytes: bytes, startLine: startLine)
    if !tk.ok { return ParseResult(ok: false, statements: [], error: tk.error) }
    let t = tk.tokens
    var pos = 0
    var stmts: [LineStmt] = []
    var env: [LineStmt] = initialEnv
    while pos < t.count && t[pos].kind != .end {
        if t[pos].kind == .newline {
            pos += 1
        } else {
            let one = parseStatement(t, pos, env)
            if !one.ok {
                let detail = "\(t[pos].line) (\(t[pos].kind.rawValue) `\(t[pos].body)`): \(one.err)"
                return ParseResult(ok: false, statements: [], error: detail)
            }
            stmts.append(contentsOf: one.stmts)
            env.append(contentsOf: one.stmts)
            pos = one.pos
        }
    }
    return ParseResult(ok: true, statements: stmts, error: "")
}

// MARK: - 도우미

let defineFields = ["mutable", "name", "type_name", "expr", "retain_borrowed_owner", "compiler_generated"]

/// 파싱반복정의문장
func defineStmt(_ line: Int, _ mutable: Bool, _ name: BStr, _ type: ASTValue, _ expr: ASTValue, generated: Bool = false) -> LineStmt {
    LineStmt(line, ASTNode("Define", [
        ("mutable", B(mutable)), ("name", S(name)), ("type_name", type), ("expr", expr),
        ("retain_borrowed_owner", B(false)), ("compiler_generated", B(generated)),
    ]))
}

/// 파싱반복대입문장
func assignNameStmt(_ line: Int, _ name: BStr, _ expr: ASTValue) -> LineStmt {
    LineStmt(line, ASTNode("Assign", [("target", N("NameTarget", [("name", S(name))])), ("expr", expr)]))
}

func exprStmt(_ line: Int, _ e: ASTValue) -> LineStmt { LineStmt(line, ASTNode("ExprStmt", [("expr", e)])) }

func stmt(_ line: Int, _ n: ASTValue) -> LineStmt { LineStmt(line, n.nodeValue!) }

/// 파싱표준입력호출식
func stdinCall(_ name: BStr) -> ASTValue { CallExpr(name, [], generated: true) }

/// 파싱매개변수
func parseParams(_ t: [Token], _ start: Int, _ end: Int) -> [ASTValue] {
    var params: [ASTValue] = []
    var pos = start
    while pos < end {
        var consuming = false
        if t[pos].body == "소비하는" {
            consuming = true
            pos += 1
        }
        if pos + 2 >= end || t.body(pos + 1) != ":" { return params }
        let name = t[pos].body
        pos += 2
        let typeStart = pos
        while pos < end && t[pos].body != "," { pos += 1 }
        let typ = tokenRangeText(t, typeStart, pos)
        params.append(N("Parameter", [("name", S(name)), ("type_name", S(typ)), ("consuming", B(consuming)), ("compiler_generated", B(false))]))
        if pos < end && t[pos].body == "," { pos += 1 }
    }
    return params
}

/// 파싱환경타입: 환경(뒤에서부터)의 같은 이름 Define의 타입 표기.
func envType(_ env: [LineStmt], _ name: BStr) -> BStr {
    var i = env.count
    while i > 0 {
        i -= 1
        let n = env[i].node
        if n.kind == "Define" && n.str("name") == name {
            if case .str(let s) = n["type_name"] { return s }
        }
    }
    return ""
}

/// 파싱대상변환
func toTarget(_ e: ASTValue) -> ASTValue {
    switch e.kind {
    case "NameExpr": return N("NameTarget", [("name", S(e.str("name")))])
    case "FieldAccessExpr": return N("FieldTarget", [("base", toTarget(e["base"])), ("field", S(e.str("field")))])
    case "IndexAccessExpr": return N("IndexTarget", [("base", toTarget(e["base"])), ("index", e["index"]), ("natural", e["natural"])])
    case "OffsetMemoryReadExpr": return N("OffsetMemoryTarget", [("address", e["address"]), ("value_type", e["value_type"])])
    case "MemoryReadExpr": return N("MemoryTarget", [("base", e["base"]), ("index", e["index"]), ("value_type", e["value_type"])])
    default: return .null
    }
}

/// 파싱대입조사점: 깊이 0의 마지막 은/는 후보(`또는` 제외).
func assignParticlePoint(_ t: [Token], _ start: Int, _ end: Int) -> Int {
    var pos = start
    var depth = 0
    var at = end
    while pos < end {
        let b = t[pos].body
        if b == "(" || b == "[" {
            depth += 1
        } else if b == ")" || b == "]" {
            if depth > 0 { depth -= 1 }
        } else if depth == 0 && b != "또는" && isAssignParticle(b) {
            at = pos
        }
        pos += 1
    }
    return at
}

func isDefaultNumericType(_ t: BStr) -> Bool {
    let names: [BStr] = ["자연수8", "자연수16", "자연수32", "자연수64", "정수8", "정수16", "정수32", "정수64", "실수32", "실수64"]
    return names.contains(t)
}

/// 자연수64파싱
func parseUInt64(_ s: BStr) -> UInt64? {
    if s.count == 0 { return nil }
    var v: UInt64 = 0
    for i in 0..<s.count {
        let c = s[i]
        if c < 48 || c > 57 { return nil }
        let (m, o1) = v.multipliedReportingOverflow(by: 10)
        let (a, o2) = m.addingReportingOverflow(UInt64(c - 48))
        if o1 || o2 { return nil }
        v = a
    }
    return v
}

/// 파싱기본값식: 값 없는 선언의 기본값.
func defaultValueExpr(_ typ: BStr) -> ASTValue {
    if typ.count == 0 { return .null }
    if typ.hasSuffix("?") { return N("OptionalNoneExpr", []) }
    if typ.hasSuffix("의 배열") {
        let elem = typ.sub(0, typ.count - "의 배열".utf8.count)
        if elem.contains(".") { return .null }
        if elem.contains(" ") {
            if defaultValueExpr(elem).isNull { return .null }
        }
        return N("ArrayLiteral", [("elements", .array([]))])
    }
    if typ.hasSuffix("개의 고정배열") {
        let parts = typ.split(" ")
        if parts.count < 3 { return .null }
        let countText = stripSuffix(parts[parts.count - 2], "개의")
        guard let n = parseUInt64(countText) else { return .null }
        var elem = parts[0]
        var i = 1
        while i < parts.count - 2 {
            elem = elem + " " + parts[i]
            i += 1
        }
        let ed = defaultValueExpr(elem)
        if ed.isNull { return .null }
        return N("ArrayLiteral", [("elements", .array(Array(repeating: ed, count: Int(n))))])
    }
    if typ == "문자열" { return N("StringLiteral", [("value", S(""))]) }
    if typ == "참거짓" { return N("BoolLiteral", [("value", B(false))]) }
    if typ == "문자" { return N("StringLiteral", [("value", S(" "))]) }
    if typ == "주소" || isDefaultNumericType(typ) {
        return N("CastExpr", [("type_name", S(typ)), ("expr", IntLit(0)), ("compiler_generated", B(false))])
    }
    return .null
}

/// 규칙정의환경: 함수 본문으로 물려주는 환경(규칙 선언만).
func ruleDefinitionEnv(_ env: [LineStmt]) -> [LineStmt] {
    env.filter { $0.node.kind == "LoopModifierDef" || $0.node.kind == "BlockModifierDef" }
}

/// 파싱블록
func parseBlock(_ t: [Token], _ start: Int, _ env: [LineStmt]) -> SR {
    if start >= t.count || t[start].kind != .indent { return .failure(start, "들여쓰기 블록이 필요합니다") }
    var pos = start + 1
    var stmts: [LineStmt] = []
    var ctx = env
    while pos < t.count && t[pos].kind != .dedent {
        if t[pos].kind == .newline {
            pos += 1
        } else {
            let one = parseStatement(t, pos, ctx)
            if !one.ok {
                return .failure(one.pos, "\(t[pos].line) (\(t[pos].kind.rawValue) `\(t[pos].body)`): \(one.err)")
            }
            stmts.append(contentsOf: one.stmts)
            ctx.append(contentsOf: one.stmts)
            pos = one.pos
        }
    }
    if pos >= t.count || t[pos].kind != .dedent { return .failure(pos, "블록 내어쓰기가 필요합니다") }
    return .success(pos + 1, stmts)
}

/// 파싱사전리터럴문장들
func dictionaryLiteralStmts(_ t: [Token], _ start: Int, _ end: Int, _ line: Int, _ name: BStr, _ mutable: Bool, _ typ: BStr) -> [LineStmt] {
    var out: [LineStmt] = []
    if end < start + 2 { return out }
    if t[start].body != "[" { return out }
    if t[end - 1].body != "]" { return out }
    let innerStart = start + 1
    let innerEnd = end - 1
    var keys: [ASTValue] = []
    var vals: [ASTValue] = []
    var emptyDict = false
    if innerEnd == innerStart + 1 && t[innerStart].body == ":" { emptyDict = true }
    if !emptyDict {
        if innerEnd <= innerStart { return out }
        var itemStart = innerStart
        var failed = false
        while !failed && itemStart < innerEnd {
            let itemEnd = topLevelComma(t, itemStart, innerEnd)
            let colon = topLevelColon(t, itemStart, itemEnd)
            let colons = topLevelColonCount(t, itemStart, itemEnd)
            if colons != 1 { failed = true }
            else if colon == itemStart { failed = true }
            else if colon + 1 >= itemEnd { failed = true }
            else {
                let k = parseVerbatimRange(t, itemStart, colon)
                let v = parseVerbatimRange(t, colon + 1, itemEnd)
                if !k.ok { failed = true }
                else if !v.ok { failed = true }
                else {
                    keys.append(k.node)
                    vals.append(v.node)
                }
            }
            itemStart = itemEnd + 1
        }
        if failed { return out }
        if keys.count == 0 { return out }
    }
    var dictMutable = mutable
    if keys.count > 0 { dictMutable = true }
    out.append(defineStmt(line, dictMutable, name, S(typ), N("DeferredDefaultExpr", [])))
    for i in 0..<keys.count {
        let call = CallExpr("넣은것", [NameExpr(name), keys[i], vals[i]])
        out.append(assignNameStmt(line, name, call))
    }
    return out
}

// MARK: - 반복

/// 파싱각항목점
func forEachItemPoint(_ t: [Token], _ head: Int, _ end: Int) -> Int {
    if head >= end { return end }
    if t[head].body == "각각의" {
        if head + 1 < end && t[head + 1].body == "원소" { return head + 2 }
        return end
    }
    return head + 1
}

/// 파싱각반복머리종류
func forEachHeaderKind(_ t: [Token], _ start: Int, _ end: Int, _ head: Int, _ item: Int) -> Int {
    if head <= start || item >= end { return 0 }
    let before = t[head - 1].body
    let itemWord = t[item].body
    if before.hasSuffix("에서") {
        if itemWord.hasSuffix("마다") { return 3 }
        if item + 1 < end && t[item + 1].body == "위치마다" { return 3 }
        return 0
    }
    if !before.hasSuffix("의") { return 0 }
    if item + 1 < end && itemWord.hasSuffix("에") && t[item + 1].body == "대해" { return 1 }
    if item + 2 < end && t[item + 1].body == "위치에" && t[item + 2].body == "대해" { return 4 }
    if item + 1 == end && itemWord.hasSuffix("마다") { return 2 }
    return 0
}

/// 파싱각반복머리끝
func forEachHeaderEnd(_ kind: Int, _ item: Int, _ end: Int) -> Int {
    if kind == 4 { return item + 3 }
    if kind == 1 { return item + 2 }
    if kind == 2 { return item + 1 }
    return end
}

/// 파싱각머리점찾기
func findForEachHead(_ t: [Token], _ start: Int, _ end: Int) -> Int {
    var p = start
    var result = end
    while p < end && result == end {
        if t[p].body == "각" || t[p].body == "각각의" {
            let item = forEachItemPoint(t, p, end)
            if forEachHeaderKind(t, start, end, p, item) != 0 { result = p }
        }
        if result == end { p += 1 }
    }
    return result
}

/// 파싱표준입력줄반복
func stdinLineLoop(_ line: Int, _ item: BStr, _ body: [LineStmt]) -> [LineStmt] {
    let optName = "표준입력" + item + "선택값"
    let read = stdinCall("입력줄읽기")
    var loopBody: [LineStmt] = []
    loopBody.append(defineStmt(line, false, item, S("문자열"), N("OptionalUnwrapExpr", [("expr", NameExpr(optName))])))
    loopBody.append(contentsOf: body)
    loopBody.append(assignNameStmt(line, optName, read))
    var out: [LineStmt] = []
    out.append(defineStmt(line, true, optName, S("문자열?"), read))
    let cond = N("OptionalHasValueCondition", [("expr", NameExpr(optName)), ("has_value", B(true))])
    out.append(LineStmt(line, ASTNode("While", [("condition", cond), ("body", .stmts(loopBody))])))
    return out
}

/// 파싱단순각반복
func simpleForEach(_ t: [Token], _ start: Int, _ end: Int, _ head: Int, _ item: Int, _ kind: Int, _ body: SR) -> SR {
    let line = t[start].line
    let arr = parseRange(t, start, head)
    if !arr.ok { return .failure(start, arr.err) }
    var arrName: BStr = ""
    if arr.node.kind == "NameExpr" { arrName = arr.node.str("name") }
    var itemName: BStr = ""
    var posName: ASTValue = .null
    if kind == 4 {
        itemName = stripSuffix(stripSuffix(t[item].body, "과"), "와")
        posName = S("위치")
    } else if kind == 3 {
        if end == item + 2 && t[item + 1].body == "위치마다" {
            itemName = stripSuffix(stripSuffix(t[item].body, "과"), "와")
            posName = S("위치")
        } else {
            itemName = stripSuffix(t[item].body, "마다")
        }
    } else if kind == 2 {
        itemName = stripSuffix(t[item].body, "마다")
    } else {
        itemName = stripSuffix(t[item].body, "에")
    }
    if arrName == "표준입력" {
        if !posName.isNull { return .failure(start, "표준입력 순회는 위치를 지원하지 않습니다") }
        return .success(body.pos, stdinLineLoop(line, itemName, body.stmts))
    }
    let fe = ASTNode("ForEach", [("array", arr.node), ("item_name", S(itemName)), ("position_name", posName), ("body", .stmts(body.stmts))])
    return .success(body.pos, [LineStmt(line, fe)])
}

// MARK: - 함수값

/// 파싱함수값닫기점
func functionValueClose(_ t: [Token], _ start: Int, _ end: Int) -> Int {
    if end < start + 6 { return end }
    if t[start].body != "상수" && t[start].body != "변수" { return end }
    let nameTok = t[start + 1]
    if nameTok.kind != .name || nameTok.body.count <= 3 { return end }
    if !nameTok.body.hasSuffix("은") && !nameTok.body.hasSuffix("는") { return end }
    if t[start + 2].body != "(" { return end }
    var depth = 1
    var close = start + 3
    while close < end && depth > 0 {
        if t[close].body == "(" { depth += 1 } else if t[close].body == ")" { depth -= 1 }
        if depth > 0 { close += 1 }
    }
    if close + 2 >= end { return end }
    if t[close + 1].body != "를" && t[close + 1].body != "을" { return end }
    if t[close + 2].body != "받아" { return end }
    return close
}

/// 파싱함수값비동기인가
func functionValueIsAsync(_ t: [Token], _ start: Int, _ end: Int) -> Bool {
    let len = end - start
    if len == 3 && t[start].body == "비동기로" && t[start + 1].body == "반환하지" && t[start + 2].body == "않음" { return true }
    if len >= 3 && t[end - 1].body == "반환" && t[end - 2].body == "비동기로" { return true }
    return false
}

/// 파싱함수값반환타입
func functionValueReturnType(_ t: [Token], _ start: Int, _ end: Int) -> BStr {
    let len = end - start
    if len <= 0 { return "" }
    if len == 3 && t[start].body == "비동기로" && t[start + 1].body == "반환하지" && t[start + 2].body == "않음" { return "없음" }
    if len == 2 && t[start].body == "반환하지" && t[start + 1].body == "않음" { return "없음" }
    if t[end - 1].body != "반환" { return tokenRangeText(t, start, end) }
    var typeEnd = end - 1
    if typeEnd > start + 1 && t[typeEnd - 1].body == "비동기로" { typeEnd -= 1 }
    if typeEnd <= start { return "" }
    let last = t[typeEnd - 1].body
    if last == "를" || last == "을" { return tokenRangeText(t, start, typeEnd - 1) }
    if !last.hasSuffix("를") && !last.hasSuffix("을") { return "" }
    let body = tokenRangeText(t, start, typeEnd)
    return body.sub(0, body.count - 3)
}

// MARK: - 경우

/// 파싱토큰이어짐인가
func tokensContiguous(_ t: [Token], _ start: Int, _ end: Int) -> Bool {
    var pos = start + 1
    while pos < end {
        let prev = t[pos - 1]
        if t[pos].line != prev.line || t[pos].col != prev.col + prev.body.count { return false }
        pos += 1
    }
    return true
}

/// 파싱경우값끝인가
func isCaseValueEnd(_ tok: Token) -> Bool {
    if tok.body == "인" { return true }
    if tok.kind == .name && tok.body.hasSuffix("인") && tok.body.count > 3 { return true }
    return false
}

/// 파싱경우주격토큰인가
func isCaseSubjectToken(_ t: [Token], _ pos: Int, _ start: Int) -> Bool {
    let tok = t[pos]
    if tok.kind != .name { return false }
    if !tok.body.hasSuffix("이") && !tok.body.hasSuffix("가") { return false }
    if tok.body.count == 3 && pos == start { return false }
    if pos + 1 >= t.count { return false }
    let next = t[pos + 1]
    if next.line == tok.line && next.col <= tok.col + tok.body.count { return false }
    return true
}

/// 파싱경우토큰들자르기
func caseTrim(_ t: [Token], _ start: Int, _ end: Int, _ suffix: BStr) -> [Token] {
    var out: [Token] = []
    var pos = start
    while pos < end {
        var tok = t[pos]
        if pos + 1 == end { tok.body = stripSuffix(tok.body, suffix) }
        if tok.body.count > 0 { out.append(tok) }
        pos += 1
    }
    return out
}

/// 파싱경우값토큰들
func caseValueTokens(_ t: [Token], _ start: Int, _ end: Int) -> [Token] {
    if end <= start { return [] }
    if t[end - 1].body == "인" { return caseTrim(t, start, end - 1, "") }
    return caseTrim(t, start, end, "인")
}

/// 파싱경우주어토큰들
func caseSubjectTokens(_ t: [Token], _ start: Int, _ subj: Int) -> [Token] {
    if t[subj].body.hasSuffix("가") { return caseTrim(t, start, subj + 1, "가") }
    return caseTrim(t, start, subj + 1, "이")
}

func caseCompare(_ subject: ASTValue, _ value: ASTValue) -> ASTValue {
    N("CompareCondition", [("left", subject), ("op", S("==")), ("right", value)])
}

// MARK: - 표면 문법 감지 (씨앗 범위 밖)

/// 자립 파서는 모든 문장을 먼저 UI·DB·라우트·채널·배열파이프라인 표면 파서에 보인다.
/// 씨앗은 그 표면 문법을 구현하지 않는다(컴파일러 소스가 쓰지 않는다). 대신 확실히
/// 인식되는 머리를 만나면 조용히 다른 AST를 내지 않도록 실패시킨다.
func surfaceSyntaxGuard(_ t: [Token], _ start: Int, _ end: Int) -> String? {
    var h = start
    if h < end && t[h].body == "공개" { h += 1 }
    if end >= h + 4 && t[h].body == "화면을" && t[h + 1].body == "표시하는" && t[h + 2].body == "함수" {
        return "UI 표면 문법(화면을 표시하는 함수)은 씨앗 파서가 지원하지 않습니다"
    }
    if end == h + 2 && t[h].body == "화면" && t[h + 1].body.hasSuffix("의") {
        return "UI 표면 문법(화면 선언)은 씨앗 파서가 지원하지 않습니다"
    }
    var i = start
    while i < end {
        if t[i].body == "조회한다" || t[i].body == "조회하여" { return "DB 표면 문법은 씨앗 파서가 지원하지 않습니다" }
        i += 1
    }
    // 라우트 장착(`앱에 묶음을 연결한다`): 라우트 파서는 마침표 하나만 뗀다.
    var routeEnd = end
    if routeEnd > start && t[routeEnd - 1].body == "." { routeEnd -= 1 }
    if routeEnd > start + 2 && t[routeEnd - 1].body == "연결한다" && (t[start].body.hasSuffix("에") || t[start].body.hasSuffix("의")) {
        return "라우트 표면 문법은 씨앗 파서가 지원하지 않습니다"
    }
    // 채널: 채널구두끝인가(마침표·쉼표)를 뗀 자리.
    var realEnd = end
    while realEnd > start && isPunctEnd(t[realEnd - 1].body) { realEnd -= 1 }
    if realEnd >= start + 10 && t[start].body == "상수" && t[start + 1].body == "(" {
        var close = start + 2
        while close < realEnd && t[close].body != ")" { close += 1 }
        if close + 5 < realEnd && t[close + 1].body == "는" && t[close + 2].body == "용량"
            && t[realEnd - 2].body.hasSuffix("의") && t[realEnd - 1].body == "채널이다" {
            return "채널 표면 문법(채널 생성)은 씨앗 파서가 지원하지 않습니다"
        }
    }
    if realEnd == start + 2 && t[realEnd - 1].body == "닫는다" { return "채널 표면 문법은 씨앗 파서가 지원하지 않습니다" }
    if realEnd >= start + 3 && t[realEnd - 1].body == "보낸다" { return "채널 표면 문법은 씨앗 파서가 지원하지 않습니다" }
    return nil
}

// MARK: - 파싱한문장

func parseStatement(_ t: [Token], _ start: Int, _ env: [LineStmt]) -> SR {
    let line = t[start].line
    let end = lineEnd(t, start)
    var out: [LineStmt] = []
    if let e = surfaceSyntaxGuard(t, start, end) { return .failure(start, e) }

    // 제네릭 머리 `… 임의의 타입 T에 대해`
    var anyAt = start
    while anyAt < end && t[anyAt].body != "임의의" { anyAt += 1 }
    var genericLine = false
    if anyAt < end && anyAt + 3 < end && t[anyAt + 1].body == "타입" {
        if t[end - 1].body == "대해" || t[end - 1].body == "," { genericLine = true }
    }
    if genericLine {
        let gType = stripSuffix(t[anyAt + 2].body, "에")
        var traits: [ASTValue] = []
        var sat = start
        while sat < anyAt && t[sat].body != "만족하는" { sat += 1 }
        if sat < anyAt { traits.append(S(stripParticle(tokenRangeText(t, start, sat)))) }
        let next = parseStatement(t, nextLine(t, end), env)
        if !next.ok || next.stmts.count == 0 { return next }
        let first = next.stmts[0]
        var types: [ASTValue] = [S(gType)]
        if case .array(let old) = first.node["type_params"] { types.append(contentsOf: old) }
        var node = first.node.replacing("type_params", with: .array(types))
        var constraints: [ASTValue] = [.array([S(gType), .array(traits)])]
        if case .array(let old) = first.node["type_constraints"] { constraints.append(contentsOf: old) }
        node = node.replacing("type_constraints", with: .array(constraints))
        out.append(LineStmt(first.line, node))
        return .success(next.pos, out)
    }
    if end == start + 3 && t[start].body == "반복을" && t[end - 2].body == "계속한다" {
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Continue", []))])
    }
    if end == start + 4 && t[start].body == "다음" && t[start + 1].body == "반복으로" && t[end - 2].body == "넘어간다" {
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Continue", []))])
    }
    if end == start + 3 && t[start].body == "반복을" && t[end - 2].body == "종료한다" {
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Break", []))])
    }
    if end == start + 2 && t[start].body == "반환한다" {
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Return", [
            ("expr", .null), ("type_name", .null), ("compiler_generated", B(false)), ("opaque_trait_name", .null),
        ]))])
    }
    if end >= start + 3 && t[start].body == "블록" && t[start + 1].body == "수식어" {
        return .failure(start, "블록 수식어 선언은 씨앗 파서가 지원하지 않습니다")
    }
    if end >= start + 3 && t[start].body == "반복" && t[start + 1].body == "수식어" {
        return .failure(start, "반복 수식어 선언은 씨앗 파서가 지원하지 않습니다")
    }
    if t[start].kind == .string && start + 2 < end && t[start + 2].body == "가져온다" {
        guard let path = jsonParseStringDocument(t[start].body) else {
            return .failure(start, "가져오기 경로 문자열이 올바르지 않습니다")
        }
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Import", [("path", S(path))]))])
    }
    if end == start + 3 && t[start + 1].body == "가져온다" {
        let module = stripParticle(t[start].body)
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("ModuleImport", [("module_name", S(module))]))])
    }
    // 전역 선언 수식자
    var gAt = start
    var gVis = "module"
    var scanning = true
    while gAt < end && scanning {
        let b = t[gAt].body
        if b == "공개" { gVis = "public"; gAt += 1 }
        else if b == "프로젝트" { gVis = "project"; gAt += 1 }
        else if b == "파일" { gVis = "file"; gAt += 1 }
        else if b == "모듈" { gVis = "module"; gAt += 1 }
        else if b == "내부" { gAt += 1 }
        else { scanning = false }
    }
    if end >= start + 5 && t[start].body == "외부" && t[start + 1].body == "전역" && t[start + 2].body == "심볼" {
        let name = stripParticle(t[start + 3].body)
        var typeEnd = end
        while typeEnd > start + 5 && isPunctEnd(t[typeEnd - 1].body) { typeEnd -= 1 }
        let typ = stripParticle(tokenRangeText(t, start + 4, typeEnd))
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("ExternalGlobal", [("name", S(name)), ("type_name", S(typ))]))])
    }
    if end >= gAt + 5 && t[gAt].body == "전역" && isGlobalKind(t[gAt + 1].body) {
        let name = stripParticle(t[gAt + 2].body)
        var exprStart = gAt + 3
        var section: ASTValue = .null
        var align: ASTValue = .null
        if exprStart + 2 < end && t[exprStart].body == "섹션" && t[exprStart + 1].kind == .string && t[exprStart + 2].body == "에" {
            guard let sv = jsonParseStringDocument(t[exprStart + 1].body) else {
                return .failure(exprStart, "전역 섹션 문자열이 올바르지 않습니다")
            }
            section = S(sv)
            exprStart += 3
        }
        if exprStart + 2 < end && t[exprStart].kind == .int && t[exprStart + 1].body == "로" && t[exprStart + 2].body == "정렬한" {
            guard let av = parseUInt64(t[exprStart].body) else {
                return .failure(exprStart, "전역 정렬값이 올바르지 않습니다")
            }
            align = .int(BStr(decimal: av))
            exprStart += 3
        }
        let comma = topLevelComma(t, gAt + 3, end)
        var exprEnd = comma
        if exprEnd > gAt + 3 && t[exprEnd - 1].body == "이고" { exprEnd -= 1 }
        var defExpr: ASTValue = .null
        var defType: BStr = ""
        if comma >= end && end > exprStart + 1 && t[end - 2].body.hasSuffix("이다") {
            defType = stripIda(tokenRangeText(t, exprStart, end - 1))
            defExpr = defaultValueExpr(defType)
        }
        var ge = ER.success(exprStart, defExpr)
        if defExpr.isNull { ge = parseRange(t, exprStart, exprEnd) }
        if !ge.ok { return .failure(start, ge.err) }
        var typeEnd = end
        while typeEnd > comma + 1 && isPunctEnd(t[typeEnd - 1].body) { typeEnd -= 1 }
        var gType = stripParticle(tokenRangeText(t, comma + 1, typeEnd))
        if !defExpr.isNull { gType = defType }
        let node = ASTNode("GlobalDefine", [
            ("mutable", B(t[gAt + 1].body == "변수")), ("name", S(name)), ("type_name", S(gType)), ("expr", ge.node),
            ("section", section), ("alignment", align), ("visibility", Visibility(gVis)),
        ])
        return .success(nextLine(t, end), [LineStmt(line, node)])
    }
    // 블록 문장들
    let blockKinds: [(BStr, NodeKind)] = [("위험", "UnsafeBlock"), ("선점금지", "PreemptDisableBlock"), ("동시", "ConcurrentBlock")]
    for (word, kind) in blockKinds where end == start + 2 && t[start].body == word && t[start + 1].body == "작업은" {
        let body = parseBlock(t, nextLine(t, end), env)
        if !body.ok { return body }
        return .success(body.pos, [LineStmt(line, ASTNode(kind, [("body", .stmts(body.stmts))]))])
    }
    if end == start + 2 && t[start].body == "비동기" && t[start + 1].body == "작업은" {
        let body = parseBlock(t, nextLine(t, end), env)
        if !body.ok { return body }
        let valueName = "__비동기작업값_" + BStr(decimal: line)
        let funcName = "__비동기작업함수_" + BStr(decimal: line)
        let fv = ASTNode("FunctionValueDefine", [
            ("mutable", B(false)), ("name", S(valueName)), ("function_name", S(funcName)), ("params", .array([])),
            ("return_type", .null), ("body", .stmts(body.stmts)), ("compiler_generated", B(true)), ("is_async", B(true)),
        ])
        let call = CallExpr(valueName, [], generated: true)
        let startTask = ASTNode("UnstructuredTaskStart", [("call", call), ("compiler_generated", B(true))])
        return .success(body.pos, [LineStmt(line, fv), LineStmt(line, startTask)])
    }
    if end >= start + 5 && t[start].body == "제한" && t[start + 1].body == "시간이" && t[end - 2].body == "밀리초인" && t[end - 1].body == "작업은" {
        let ms = parseRange(t, start + 2, end - 2)
        if !ms.ok { return .failure(start, ms.err) }
        let body = parseBlock(t, nextLine(t, end), env)
        if !body.ok { return body }
        return .success(body.pos, [LineStmt(line, ASTNode("DeadlineBlock", [("milliseconds", ms.node), ("body", .stmts(body.stmts))]))])
    }
    if end == start + 2 && t[start].body == "시도할" && t[start + 1].body == "작업은" {
        let body = parseBlock(t, nextLine(t, end), env)
        if !body.ok { return body }
        var next = body.pos
        var failure: ASTValue = .null
        var finally: ASTValue = .null
        if next < t.count && t[next].body == "실패하면" {
            let fe = lineEnd(t, next)
            let fb = parseBlock(t, nextLine(t, fe), env)
            if !fb.ok { return fb }
            failure = .stmts(fb.stmts)
            next = fb.pos
        }
        if next < t.count && t[next].body == "끝으로" {
            let fe = lineEnd(t, next)
            let fb = parseBlock(t, nextLine(t, fe), env)
            if !fb.ok { return fb }
            finally = .stmts(fb.stmts)
            next = fb.pos
        }
        return .success(next, [LineStmt(line, ASTNode("TryBlock", [("body", .stmts(body.stmts)), ("failure_body", failure), ("finally_body", finally)]))])
    }
    // 특성
    let traitAt = gAt
    let traitVis = gVis
    if traitAt < end && t[traitAt].body == "특성" {
        var sat = traitAt + 1
        while sat < end && t[sat].body != "만족하는" { sat += 1 }
        var traitName: BStr = ""
        var ni = traitAt + 1
        while ni < sat {
            var piece = t[ni].body
            if ni + 1 == sat { piece = stripParticle(piece) }
            if traitName.count > 0 { traitName = traitName + " " }
            traitName = traitName + piece
            ni += 1
        }
        let selfType = stripParticle(t[end - 1].body)
        var reqs: [ASTValue] = []
        var supers: [ASTValue] = []
        var assocTypes: [ASTValue] = []
        var assocBounds: [ASTValue] = []
        var rp = nextLine(t, end)
        if rp >= t.count || t[rp].kind != .indent { return .failure(start, "특성 요구 블록이 필요합니다") }
        rp += 1
        while rp < t.count && t[rp].kind != .dedent {
            let re = lineEnd(t, rp)
            var paren = rp
            while paren < re && t[paren].body != "(" { paren += 1 }
            if paren == re {
                var mustAt = rp
                while mustAt < re && t[mustAt].body != "만족해야" { mustAt += 1 }
                if mustAt < re {
                    if mustAt == rp || mustAt + 1 >= re || t[mustAt + 1].body != "하고" {
                        return .failure(rp, "상위 특성 요구 문법이 올바르지 않습니다")
                    }
                    supers.append(S(stripParticle(tokenRangeText(t, rp, mustAt))))
                    rp = nextLine(t, re)
                    continue
                }
                var anyP = rp
                while anyP < re && t[anyP].body != "임의의" { anyP += 1 }
                if anyP + 2 >= re || t[anyP + 1].body != "타입" {
                    return .failure(rp, "특성 연관 타입 문법이 올바르지 않습니다")
                }
                let assocName = stripParticle(t[anyP + 2].body)
                assocTypes.append(S(assocName))
                var aSat = rp
                while aSat < anyP && t[aSat].body != "만족하는" { aSat += 1 }
                if aSat < anyP {
                    let at = stripParticle(tokenRangeText(t, rp, aSat))
                    assocBounds.append(.array([S(assocName), .array([S(at)])]))
                }
                rp = nextLine(t, re)
                continue
            }
            var close = paren + 1
            while close < re && t[close].body != ")" { close += 1 }
            let rparams = parseParams(t, paren + 1, close)
            var takeAt = close + 1
            while takeAt < re && t[takeAt].body != "받아" { takeAt += 1 }
            var retAt = takeAt + 1
            while retAt < re && t[retAt].body != "반환하는" { retAt += 1 }
            var fnAt = retAt + 1
            while fnAt < re && t[fnAt].body != "함수" { fnAt += 1 }
            let rret = stripParticle(tokenRangeText(t, takeAt + 1, retAt))
            let rname = stripParticle(t[safe: fnAt + 1].body)
            reqs.append(N("TraitRequirement", [("name", S(rname)), ("params", .array(rparams)), ("return_type", S(rret))]))
            rp = nextLine(t, re)
        }
        let node = ASTNode("TraitDef", [
            ("name", S(traitName)), ("self_type", S(selfType)), ("supertraits", .array(supers)), ("associated_types", .array(assocTypes)),
            ("associated_type_bounds", .array(assocBounds)), ("requirements", .array(reqs)), ("visibility", Visibility(traitVis)),
        ])
        return .success(rp + 1, [LineStmt(line, node)])
    }
    // 열거형
    if end > start + 1 && t[end - 1].body == "종류는" {
        var eVis = "module"
        var nameAt = end - 2
        if end > start + 2 && t[end - 2].body == "공개" {
            eVis = "public"
            nameAt = end - 3
        } else if end > start + 3 && t[end - 2].body == "내부" {
            let scope = t[end - 3].body
            if scope == "프로젝트" { eVis = "project" }
            else if scope == "파일" { eVis = "file" }
            else if scope == "모듈" { eVis = "module" }
            else { return .failure(end - 3, "열거형 접근 수준이 올바르지 않습니다") }
            nameAt = end - 4
        }
        if nameAt < start || !t[nameAt].body.hasSuffix("의") { return .failure(start, "열거형 선언 이름이 올바르지 않습니다") }
        let eName = stripSuffix(t[nameAt].body, "의")
        var base: ASTValue = .null
        if nameAt > start { base = S(tokenRangeText(t, start, nameAt)) }
        var ep = nextLine(t, end)
        if ep >= t.count || t[ep].kind != .indent { return .failure(ep, "열거형 종류 블록이 필요합니다") }
        ep += 1
        var cases: [ASTValue] = []
        while ep < t.count && t[ep].kind != .dedent {
            if t[ep].kind == .newline {
                ep += 1
            } else {
                let ce = lineEnd(t, ep)
                var cre = ce
                while cre > ep && isPunctEnd(t[cre - 1].body) { cre -= 1 }
                var eq = ep
                while eq < cre && t[eq].body != "=" { eq += 1 }
                var nameEnd = cre
                if eq < cre { nameEnd = eq }
                let cname = tokenRangeText(t, ep, nameEnd)
                if cname.count == 0 { return .failure(ep, "열거형 종류 이름이 필요합니다") }
                var cval: ASTValue = .null
                if eq < cre {
                    if eq + 1 >= cre { return .failure(eq, "열거형 종류 값이 필요합니다") }
                    let cv = parseRange(t, eq + 1, cre)
                    if !cv.ok { return .failure(eq + 1, cv.err) }
                    cval = cv.node
                }
                cases.append(.array([S(cname), cval]))
                ep = nextLine(t, ce)
            }
        }
        if ep >= t.count || t[ep].kind != .dedent { return .failure(ep, "열거형 내어쓰기가 필요합니다") }
        if cases.count == 0 { return .failure(start, "열거형에는 종류가 하나 이상 필요합니다") }
        let node = ASTNode("EnumDef", [("name", S(eName)), ("base_type", base), ("cases", .array(cases)), ("visibility", Visibility(eVis))])
        return .success(ep + 1, [LineStmt(line, node)])
    }
    // 외부 함수
    var extFn = start
    while extFn < end && t[extFn].body != "함수" { extFn += 1 }
    var extImpl = start
    while extImpl < end && t[extImpl].body != "외부에서" { extImpl += 1 }
    var isExternal = extImpl < end
    if t[start].body == "외부" { isExternal = true }
    if gAt < extFn && t[gAt].body == "외부" { isExternal = true }
    if extFn < end && isExternal {
        let name = stripParticle(t[safe: extFn + 1].body)
        var paren = extFn + 2
        while paren < end && t[paren].body != "(" { paren += 1 }
        var close = paren
        var params: [ASTValue] = []
        if paren < end {
            close = paren + 1
            while close < end && t[close].body != ")" { close += 1 }
            if close >= end { return .failure(start, "외부 함수 매개변수 목록이 올바르지 않습니다") }
            params = parseParams(t, paren + 1, close)
        } else {
            close = extFn + 1
        }
        var takeAt = close + 1
        while takeAt < end && t[takeAt].body != "받아" { takeAt += 1 }
        var retAt = takeAt + 1
        if takeAt >= end { retAt = close + 1 }
        while retAt < end && !t[retAt].body.hasPrefix("반환") { retAt += 1 }
        var retTypeStart = takeAt + 1
        if takeAt >= end { retTypeStart = close + 1 }
        var retType: ASTValue = .null
        if retAt > retTypeStart && retAt < end {
            retType = S(stripParticle(tokenRangeText(t, retTypeStart, retAt)))
        }
        var preRet = start
        while preRet < extFn && t[preRet].body != "반환하는" { preRet += 1 }
        if retType.isNull && preRet > start && preRet < extFn {
            var ts = start
            while ts < preRet && isFunctionModifier(t[ts].body) { ts += 1 }
            if ts < preRet { retType = S(stripParticle(tokenRangeText(t, ts, preRet))) }
        }
        var extName = name
        if extImpl + 1 < end && t[extImpl + 1].kind == .string {
            if let v = jsonParseStringDocument(t[extImpl + 1].body) { extName = v }
        }
        var unsafe = false, isAsync = false, canFail = false
        var vis = "module"
        var mi = start
        while mi < extFn {
            let b = t[mi].body
            if b.hasPrefix("위험") { unsafe = true }
            if b == "비동기인" || b == "비동기" || b == "비동기이며" { isAsync = true }
            if b == "실패할" { canFail = true }
            if b == "프로젝트" { vis = "project" }
            if b == "공개" { vis = "public" }
            if b == "파일" { vis = "file" }
            if b == "모듈" { vis = "module" }
            mi += 1
        }
        let node = ASTNode("FunctionDef", [
            ("name", S(name)), ("params", .array(params)), ("body", .stmts([])), ("return_type", retType), ("external_name", S(extName)),
            ("unsafe", B(unsafe)), ("can_fail", B(canFail)), ("type_params", .array([])), ("type_constraints", .array([])),
            ("visibility", Visibility(vis)), ("compiler_generated", B(false)), ("is_async", B(isAsync)), ("opaque_trait_name", .null),
        ])
        return .success(nextLine(t, end), [LineStmt(line, node)])
    }
    // 일반 함수
    var fnAt = start
    var headScan = true
    while fnAt < end && headScan {
        if isFunctionModifier(t[fnAt].body) {
            fnAt += 1
        } else {
            var rf = fnAt + 1
            while rf < end && t[rf].body != "반환하는" && t[rf].body != "함수" { rf += 1 }
            if rf < end && t[rf].body == "반환하는" { fnAt = rf + 1 } else { headScan = false }
        }
    }
    if fnAt < end && t[fnAt].body == "함수" && t.body(end - 2) != "반환한다" {
        let name = stripParticle(t[safe: fnAt + 1].body)
        let open = fnAt + 2
        var params: [ASTValue] = []
        if open < end && t[open].body == "(" {
            var close = open + 1
            while close < end && t[close].body != ")" { close += 1 }
            params = parseParams(t, open + 1, close)
        }
        let fenv = ruleDefinitionEnv(env)
        let body = parseBlock(t, nextLine(t, end), fenv)
        if !body.ok {
            if body.pos < t.count {
                let bt = t[body.pos]
                return .failure(body.pos, "\(bt.line) (\(bt.kind.rawValue) `\(bt.body)`): \(body.err)")
            }
            return body
        }
        var unsafe = false, isAsync = false, canFail = false
        var retType: ASTValue = .null
        var preRet = start
        while preRet < fnAt && t[preRet].body != "반환하는" { preRet += 1 }
        if preRet > start && preRet < fnAt {
            var ts = start
            while ts < preRet && isFunctionModifier(t[ts].body) { ts += 1 }
            if ts < preRet { retType = S(stripParticle(tokenRangeText(t, ts, preRet))) }
        }
        var vis = "module"
        var mi = start
        while mi < fnAt {
            let b = t[mi].body
            if b.hasPrefix("위험") { unsafe = true }
            if b == "공개" { vis = "public" }
            if b == "비동기인" || b == "비동기" || b == "비동기이며" { isAsync = true }
            if b == "실패할" { canFail = true }
            if b == "프로젝트" { vis = "project" }
            if b == "파일" { vis = "file" }
            mi += 1
        }
        let node = ASTNode("FunctionDef", [
            ("name", S(name)), ("params", .array(params)), ("body", .stmts(body.stmts)), ("return_type", retType), ("external_name", .null),
            ("unsafe", B(unsafe)), ("can_fail", B(canFail)), ("type_params", .array([])), ("type_constraints", .array([])),
            ("visibility", Visibility(vis)), ("compiler_generated", B(false)), ("is_async", B(isAsync)), ("opaque_trait_name", .null),
        ])
        return .success(body.pos, [LineStmt(line, node)])
    }
    // 구조체
    var sAt = start
    var sVis = "module"
    var sScan = true
    while sAt < end && sScan {
        let b = t[sAt].body
        if b == "공개" { sVis = "public"; sAt += 1 }
        else if b == "프로젝트" { sVis = "project"; sAt += 1 }
        else if b == "파일" { sVis = "file"; sAt += 1 }
        else if b == "모듈" { sVis = "module"; sAt += 1 }
        else if b == "내부" { sAt += 1 }
        else { sScan = false }
    }
    var packed = false
    var endian: ASTValue = .null
    if sAt < end && t[sAt].body.hasPrefix("리틀엔디안") {
        endian = S("little"); sAt += 1
    } else if sAt < end && t[sAt].body.hasPrefix("빅엔디안") {
        endian = S("big"); sAt += 1
    }
    if sAt < end && t[sAt].body == "밀착된" {
        packed = true; sAt += 1
    }
    if sAt + 2 == end && t[sAt].body == "구조체" && t[sAt + 1].kind == .name {
        let name = stripParticle(t[sAt + 1].body)
        var pos = nextLine(t, end)
        if pos >= t.count || t[pos].kind != .indent { return .failure(pos, "구조체 필드 블록이 필요합니다") }
        pos += 1
        var keys: [BStr] = []
        var vals: [ASTValue] = []
        var metas: [ASTValue] = []
        while pos < t.count && t[pos].kind != .dedent {
            if t[pos].kind == .newline {
                pos += 1
                continue
            }
            let fe = lineEnd(t, pos)
            let head = memberHeadPoint(t, pos, fe)
            if head < fe && t[head].body == "초기화는" {
                return .failure(pos, "구조체 초기화 선언은 씨앗 파서가 지원하지 않습니다")
            }
            if t[pos].kind == .indent { return .failure(pos, "구조체 멤버의 들여쓰기가 올바르지 않습니다") }
            var fs = pos
            while fs < fe {
                var nameAt = fs
                var fVis = "module"
                if nameAt + 2 < fe && t[nameAt].body == "타입" && t[nameAt + 1].body == "내부" {
                    nameAt += 2; fVis = "type"
                } else if nameAt + 2 < fe && t[nameAt].body == "모듈" && t[nameAt + 1].body == "내부" {
                    nameAt += 2
                } else if nameAt + 2 < fe && t[nameAt].body == "프로젝트" && t[nameAt + 1].body == "내부" {
                    nameAt += 2; fVis = "project"
                } else if nameAt + 2 < fe && t[nameAt].body == "파일" && t[nameAt + 1].body == "내부" {
                    nameAt += 2; fVis = "file"
                } else if nameAt + 1 < fe && t[nameAt].body == "공개" {
                    nameAt += 1; fVis = "public"
                }
                let fname = stripParticle(t[nameAt].body)
                if keys.contains(fname) { return .failure(nameAt, "중복된 구조체 필드: \(fname)") }
                let ts = nameAt + 1
                var n = ts
                while n < fe && t[n].body != "," && t[n].body != "." { n += 1 }
                let typ = stripParticle(tokenRangeText(t, ts, n))
                keys.append(fname)
                vals.append(S(typ))
                metas.append(N("StructFieldMetadata", [("name", S(fname)), ("type_name", S(typ)), ("visibility", Visibility(fVis))]))
                fs = n + 1
            }
            pos = nextLine(t, fe)
        }
        if pos >= t.count || t[pos].kind != .dedent { return .failure(pos, "구조체 내어쓰기가 필요합니다") }
        let node = ASTNode("StructDef", [
            ("name", S(name)), ("fields", .object(Array(zip(keys, vals)))), ("packed", B(packed)), ("endian", endian),
            ("type_params", .array([])), ("type_constraints", .array([])), ("visibility", Visibility(sVis)),
            ("field_metadata", .array(metas)), ("initializers", .array([])), ("member_functions", .array([])),
            ("compiler_generated", B(false)), ("compiler_generated_fields", .array([])),
        ])
        return .success(pos + 1, [LineStmt(line, node)])
    }
    // 각 반복
    let feHead = findForEachHead(t, start, end)
    let feItem = forEachItemPoint(t, feHead, end)
    let feKind = forEachHeaderKind(t, start, end, feHead, feItem)
    if feKind != 0 {
        let body = parseBlock(t, nextLine(t, end), env)
        if !body.ok { return body }
        let headEnd = forEachHeaderEnd(feKind, feItem, end)
        if headEnd == end { return simpleForEach(t, start, end, feHead, feItem, feKind, body) }
        return .failure(start, "반복 수식어 전개는 씨앗 파서가 지원하지 않습니다")
    }
    // 지역 함수값
    let fvClose = functionValueClose(t, start, end)
    if fvClose < end {
        let fvName = stripSuffix(stripSuffix(t[start + 1].body, "은"), "는")
        let fvParams = parseParams(t, start + 3, fvClose)
        let retStart = fvClose + 3
        let retType = functionValueReturnType(t, retStart, end)
        let isAsync = functionValueIsAsync(t, retStart, end)
        var retVal: ASTValue = .null
        if retType.count > 0 { retVal = S(retType) }
        let body = parseBlock(t, nextLine(t, end), env)
        if !body.ok { return body }
        let fnName = "__함수값_" + fvName + "_" + BStr(decimal: line)
        let node = ASTNode("FunctionValueDefine", [
            ("mutable", B(t[start].body == "변수")), ("name", S(fvName)), ("function_name", S(fnName)), ("params", .array(fvParams)),
            ("return_type", retVal), ("body", .stmts(body.stmts)), ("compiler_generated", B(false)), ("is_async", B(isAsync)),
        ])
        return .success(body.pos, [LineStmt(line, node)])
    }
    // 만약
    if t[start].body == "만약" {
        if isDeprecatedPrefixNot(t, start + 1, end) { return .failure(start, deprecatedPrefixNotError) }
        let cond = parseNaturalCondition(t, start + 1, end)
        if cond.isNull { return .failure(start, "조건식을 해석할 수 없습니다") }
        let body = parseBlock(t, nextLine(t, end), env)
        if !body.ok { return body }
        var branches: [ASTValue] = [.array([cond, .stmts(body.stmts)])]
        var next = body.pos
        var elseBody: ASTValue = .null
        while next + 1 < t.count && t[next].body == "그렇지" && t[next + 1].body == "않고" {
            let oe = lineEnd(t, next)
            if isDeprecatedPrefixNot(t, next + 2, oe) { return .failure(next, deprecatedPrefixNotError) }
            let oc = parseNaturalCondition(t, next + 2, oe)
            if oc.isNull { return .failure(next, "그렇지 않고 조건을 해석할 수 없습니다") }
            let ob = parseBlock(t, nextLine(t, oe), env)
            if !ob.ok { return ob }
            branches.append(.array([oc, .stmts(ob.stmts)]))
            next = ob.pos
        }
        if next < t.count && t[next].body == "아니면" {
            let ee = lineEnd(t, next)
            let eb = parseBlock(t, nextLine(t, ee), env)
            if !eb.ok { return eb }
            elseBody = .stmts(eb.stmts)
            next = eb.pos
        }
        return .success(next, [LineStmt(line, ASTNode("If", [("branches", .array(branches)), ("else_body", elseBody)]))])
    }
    // 경우
    var caseHead = false
    if end >= start + 3 && t[end - 1].body == "경우" { caseHead = isCaseValueEnd(t[end - 2]) }
    var subjAt = start
    var subjScan = caseHead
    while subjAt < end - 2 && subjScan {
        if isCaseSubjectToken(t, subjAt, start) { subjScan = false } else { subjAt += 1 }
    }
    if caseHead && !subjScan {
        let subjToks = caseSubjectTokens(t, start, subjAt)
        let firstToks = caseValueTokens(t, subjAt + 1, end - 1)
        if subjToks.count == 0 || firstToks.count == 0 { return .failure(start, "경우 문장의 대상과 값을 해석할 수 없습니다") }
        let subj = parseVerbatimRange(subjToks, 0, subjToks.count)
        if !subj.ok { return .failure(start, subj.err) }
        let firstVal = parseVerbatimRange(firstToks, 0, firstToks.count)
        if !firstVal.ok { return .failure(start, firstVal.err) }
        var target = subj.node
        if subj.node.kind != "NameExpr" {
            let hidden = "__경우대상_" + BStr(decimal: line)
            out.append(defineStmt(line, false, hidden, .null, subj.node, generated: true))
            target = NameExpr(hidden, generated: true)
        }
        let firstBody = parseBlock(t, nextLine(t, end), env)
        if !firstBody.ok { return firstBody }
        var branches: [ASTValue] = [.array([caseCompare(target, firstVal.node), .stmts(firstBody.stmts)])]
        var next = firstBody.pos
        var elseBody: ASTValue = .null
        var scanning = true
        while next < t.count && scanning {
            let ne = lineEnd(t, next)
            var nextHead = false
            if ne >= next + 2 && t[ne - 1].body == "경우" { nextHead = true }
            if !nextHead {
                scanning = false
            } else if ne == next + 3 && t[next].body == "그" && t[next + 1].body == "밖의" {
                let eb = parseBlock(t, nextLine(t, ne), env)
                if !eb.ok { return eb }
                elseBody = .stmts(eb.stmts)
                next = eb.pos
                scanning = false
            } else if isCaseValueEnd(t[ne - 2]) && tokensContiguous(t, next, ne - 1) {
                let vt = caseValueTokens(t, next, ne - 1)
                if vt.count == 0 {
                    scanning = false
                } else {
                    let v = parseVerbatimRange(vt, 0, vt.count)
                    if !v.ok { return .failure(next, v.err) }
                    let b = parseBlock(t, nextLine(t, ne), env)
                    if !b.ok { return b }
                    branches.append(.array([caseCompare(target, v.node), .stmts(b.stmts)]))
                    next = b.pos
                }
            } else {
                scanning = false
            }
        }
        out.append(LineStmt(line, ASTNode("Switch", [("branches", .array(branches)), ("else_body", elseBody)])))
        return .success(next, out)
    }
    // 동안
    if end > start + 1 && t[end - 1].body == "동안" {
        if isDeprecatedPrefixNot(t, start, end - 1) { return .failure(start, deprecatedPrefixNotError) }
        let cond = parseWhileCondition(t, start, end - 1)
        if cond.isNull { return .failure(start, "반복 조건을 해석할 수 없습니다") }
        let body = parseBlock(t, nextLine(t, end), env)
        if !body.ok { return body }
        return .success(body.pos, [LineStmt(line, ASTNode("While", [("condition", cond), ("body", .stmts(body.stmts))]))])
    }
    // 반환
    var retAt = start
    while retAt < end && t[retAt].body != "반환한다" { retAt += 1 }
    if retAt < end && retAt >= start + 1 {
        let pp = objectParticlePoint(t, start, retAt)
        var exprEnd = retAt - 1
        var typeStart = retAt - 1
        if pp < retAt {
            exprEnd = pp + 1
            typeStart = pp + 1
            if t[pp].body == "을" || t[pp].body == "를" { exprEnd = pp }
        }
        let typ = stripParticle(tokenRangeText(t, typeStart, retAt))
        var e = parseRange(t, start, exprEnd)
        var retTypeText = typ
        if !e.ok && pp < retAt {
            var rs = start
            var found = false
            while !found && rs < pp {
                if isObjectParticle(t[rs].body) {
                    var rEnd = rs + 1
                    if isObjectParticleExact(t[rs].body) { rEnd = rs }
                    let rt = stripParticle(tokenRangeText(t, rs + 1, retAt))
                    if rEnd > start && isDictSetType(rt) {
                        let re = parseRange(t, start, rEnd)
                        if re.ok {
                            e = re
                            retTypeText = rt
                            found = true
                        }
                    }
                }
                rs += 1
            }
        }
        if !e.ok { return .failure(start, e.err) }
        var retType: ASTValue = .null
        if retTypeText.count > 0 { retType = S(retTypeText) }
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Return", [
            ("expr", e.node), ("type_name", retType), ("compiler_generated", B(false)), ("opaque_trait_name", .null),
        ]))])
    }
    if end == start + 6 && t[start].body == "변수" && isBorrowVerb(t[start + 4].body) {
        let name = stripParticle(t[start + 1].body)
        let addrName = stripSuffix(stripSuffix(t[start + 2].body, "에서"), "를")
        let typ = stripParticle(t[start + 3].body)
        let kind: NodeKind = t[start + 4].body == "가져온다" ? "TakeDefine" : "BorrowDefine"
        return .success(nextLine(t, end), [LineStmt(line, ASTNode(kind, [("name", S(name)), ("address", NameExpr(addrName)), ("type_name", S(typ))]))])
    }
    if end > start + 6 && t[start].body == "변수" && isBorrowVerb(t[end - 2].body) {
        let verb = t[end - 2].body
        var boundary = start + 2
        var particle: BStr = ""
        var depth = 0
        var scan = start + 2
        while scan < end - 2 {
            let b = t[scan].body
            if b == "(" || b == "[" || b == "{" {
                depth += 1
            } else if b == ")" || b == "]" || b == "}" {
                if depth > 0 { depth -= 1 }
            } else if depth == 0 && particle.count == 0 {
                if verb == "빌려온다" && b.hasSuffix("에서") { particle = "에서"; boundary = scan }
                else if verb == "가져온다" && b.hasSuffix("을") { particle = "을"; boundary = scan }
                else if verb == "가져온다" && b.hasSuffix("를") { particle = "를"; boundary = scan }
            }
            scan += 1
        }
        if particle.count > 0 && boundary + 1 < end - 2 {
            let addrToks = copyRange(t, start + 2, boundary + 1, particle)
            if addrToks.count > 0 {
                let addr = parseVerbatimRange(addrToks, 0, addrToks.count)
                if !addr.ok { return .failure(start, addr.err) }
                let name = stripParticle(t[start + 1].body)
                let typ = stripParticle(tokenRangeText(t, boundary + 1, end - 2))
                let kind: NodeKind = verb == "가져온다" ? "TakeDefine" : "BorrowDefine"
                return .success(nextLine(t, end), [LineStmt(line, ASTNode(kind, [("name", S(name)), ("address", addr.node), ("type_name", S(typ))]))])
            }
        }
    }
    var ownEnd = end
    while ownEnd > start && isPunctEnd(t[ownEnd - 1].body) { ownEnd -= 1 }
    if ownEnd >= start + 4 && t[start].body == "상수" && t[ownEnd - 1].body == "참조한다" && isAssignParticle(t[start + 1].body) && isObjectParticle(t[ownEnd - 2].body) {
        let name = stripParticle(t[start + 1].body)
        var p: BStr = "를"
        if t[ownEnd - 2].body.hasSuffix("을") { p = "을" }
        let rt = copyRange(t, start + 2, ownEnd - 1, p)
        if rt.count > 0 {
            let r = parseVerbatimRange(rt, 0, rt.count)
            if !r.ok { return .failure(start, r.err) }
            return .success(nextLine(t, end), [LineStmt(line, ASTNode("ReferenceDefine", [("name", S(name)), ("expr", r.node)]))])
        }
    }
    if ownEnd == start + 4 && t[start].body == "변수" && t[ownEnd - 1].body == "옮긴다" && isAssignParticle(t[start + 1].body)
        && t[start + 2].kind == .name && isObjectParticle(t[start + 2].body) {
        let name = stripParticle(t[start + 1].body)
        let src = stripParticle(t[start + 2].body)
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("MoveDefine", [("source", S(src)), ("name", S(name))]))])
    }
    if ownEnd == start + 3 && t[ownEnd - 1].body == "옮긴다" && t[start].kind == .name && isObjectParticle(t[start].body)
        && t[start + 1].kind == .name && t[start + 1].body.hasSuffix("로") {
        let src = stripParticle(t[start].body)
        let name = stripParticle(t[start + 1].body)
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("MoveDefine", [("source", S(src)), ("name", S(name))]))])
    }
    if ownEnd == start + 3 && t[ownEnd - 1].body == "고정한다" && t[start + 1].body == "주소를" && t[start].kind == .name
        && t[start].body.hasSuffix("의") && t[start].body.count > 3 {
        let name = stripSuffix(t[start].body, "의")
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("PinAddress", [("name", S(name))]))])
    }
    if end == start + 3 && isObjectParticle(t[start].body) && t[start + 1].body == "해제한다" {
        let name = stripParticle(t[start].body)
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("ManualRelease", [("name", S(name))]))])
    }
    if end >= start + 4 && t[end - 2].body == "해제한다" && t[end - 3].body == "메모리를" && t[end - 4].body.hasSuffix("의") {
        let at = copyRange(t, start, end - 3, "의")
        if at.count > 0 {
            let a = parseVerbatimRange(at, 0, at.count)
            if !a.ok { return .failure(start, a.err) }
            return .success(nextLine(t, end), [exprStmt(line, CallExpr("메모리해제", [a.node]))])
        }
    }
    if end >= start + 7 && t[end - 2].body == "복사한다" && t[end - 3].body == "메모리를" && t[end - 4].body == "바이트" {
        var fromAt = start
        while fromAt < end - 4 && !t[fromAt].body.hasSuffix("에서") { fromAt += 1 }
        var toAt = fromAt + 1
        var toP: BStr = ""
        while toAt < end - 4 && toP.count == 0 {
            if t[toAt].body.hasSuffix("으로") { toP = "으로" }
            else if t[toAt].body.hasSuffix("로") { toP = "로" }
            else { toAt += 1 }
        }
        if fromAt < end - 4 && toP.count > 0 && toAt + 1 < end - 4 {
            let st = copyRange(t, start, fromAt + 1, "에서")
            let dt = copyRange(t, fromAt + 1, toAt + 1, toP)
            let zt = copyRange(t, toAt + 1, end - 4, "")
            if st.count > 0 && dt.count > 0 && zt.count > 0 {
                let s = parseVerbatimRange(st, 0, st.count)
                if !s.ok { return .failure(start, s.err) }
                let d = parseVerbatimRange(dt, 0, dt.count)
                if !d.ok { return .failure(start, d.err) }
                let z = parseVerbatimRange(zt, 0, zt.count)
                if !z.ok { return .failure(start, z.err) }
                return .success(nextLine(t, end), [exprStmt(line, CallExpr("메모리복사", [d.node, s.node, castNatural64(z.node)]))])
            }
        }
    }
    if end == start + 3 && isObjectParticle(t[start].body) && t[start + 1].body == "잊는다" {
        let name = stripParticle(t[start].body)
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Forget", [("name", S(name))]))])
    }
    if end >= start + 4 && t[end - 2].body == "입력받는다" {
        var inStart = start
        var inKind: BStr = ""
        if t[start].body == "변수" || t[start].body == "상수" {
            inKind = t[start].body
            inStart = start + 1
        }
        if end == inStart + 4 {
            let name = stripSuffix(stripSuffix(t[inStart].body, "을"), "를")
            let typ = stripSuffix(stripSuffix(t[inStart + 1].body, "으로"), "로")
            var reader: BStr = ""
            if typ == "문자열" { reader = "입력줄읽기" }
            if typ == "자연수64" { reader = "입력자연수64읽기" }
            if typ == "정수64" { reader = "입력정수64읽기" }
            if typ == "실수64" { reader = "입력실수64읽기" }
            if reader.count > 0 {
                let call = stdinCall(reader)
                if inKind.count == 0 {
                    out.append(assignNameStmt(line, name, call))
                } else {
                    out.append(defineStmt(line, inKind == "변수", name, S(typ + "?"), call))
                }
                return .success(nextLine(t, end), out)
            }
        }
    }
    if end >= start + 6 && t[end - 2].body == "할당한다" && t[end - 3].body == "메모리를" && t[end - 4].body == "바이트" {
        if t[start].body == "상수" || t[start].body == "변수" {
            let name = stripParticle(t[start + 1].body)
            let size = parseRange(t, start + 2, end - 4)
            if !size.ok { return .failure(start, size.err) }
            let call = CallExpr("메모리할당", [castNatural64(size.node)])
            return .success(nextLine(t, end), [defineStmt(line, t[start].body == "변수", name, S("주소"), call)])
        }
    }
    if end >= start + 4 {
        var defStart = start
        var mutable = false
        if t[start].body == "상수" || t[start].body == "변수" {
            mutable = t[start].body == "변수"
            defStart = start + 1
        }
        let nameTok = t[defStart].body
        if isAssignParticle(nameTok) && defStart + 2 < end {
            let name = stripSuffix(stripSuffix(nameTok, "은"), "는")
            var call: BStr = ""
            var typ: BStr = ""
            var exprEnd = end - 2
            var tailP: BStr = ""
            if t[end - 2].body == "객체이다" && t[end - 3].body.hasSuffix("의") {
                call = "객체열기"; typ = "객체?"; tailP = "의"
            } else if t[end - 2].body == "읽는다" && end >= start + 5 {
                if t[end - 3].body == "문자열로" || t[end - 3].body == "문자열으로" {
                    call = "객체문자열읽기"; typ = "문자열"; exprEnd = end - 3; tailP = "를"
                    if t[end - 4].body.hasSuffix("을") { tailP = "을" }
                }
            }
            if call.count > 0 && exprEnd > defStart + 1 {
                let vt = copyRange(t, defStart + 1, exprEnd, tailP)
                if vt.count > 0 {
                    let v = parseVerbatimRange(vt, 0, vt.count)
                    if !v.ok { return .failure(start, v.err) }
                    return .success(nextLine(t, end), [defineStmt(line, mutable, name, S(typ), CallExpr(call, [v.node]))])
                }
            }
        }
    }
    if end >= start + 3 && t[end - 2].body == "끝낸다" {
        if t[end - 3].body == "사용을" || t[end - 3].body == "사용를" {
            let ct = copyRange(t, start, end - 3, "")
            if ct.count > 0 {
                let c = parseVerbatimRange(ct, 0, ct.count)
                if !c.ok { return .failure(start, c.err) }
                let args: [ASTValue] = [.array([S("대상"), c.node])]
                return .success(nextLine(t, end), [LineStmt(line, ASTNode("Execute", [("name", S("객체닫기")), ("args", .array(args)), ("is_try", B(false))]))])
            }
        }
    }
    if end >= start + 4 && t[end - 2].body == "쓴다" {
        var tgtStart = end, tgtEnd = end, valStart = end, valEnd = end
        var matched = false
        var at = start
        while at + 1 < end - 2 && !t[at].body.hasSuffix("에") { at += 1 }
        if t[at].body.hasSuffix("에") && at + 2 < end - 2 {
            if t[at + 1].body == "문자열로" || t[at + 1].body == "문자열으로" {
                matched = true
                tgtStart = start; tgtEnd = at + 1; valStart = at + 2; valEnd = end - 2
            }
        }
        if !matched && t[end - 3].body.hasSuffix("에") {
            var oa = start
            while oa + 1 < end - 3 && !endsObject(t[oa].body) { oa += 1 }
            if endsObject(t[oa].body) && oa + 1 <= end - 3 {
                matched = true
                valStart = start; valEnd = oa + 1; tgtStart = oa + 1; tgtEnd = end - 2
            }
        }
        if matched {
            var vp: BStr = "를"
            if t[valEnd - 1].body.hasSuffix("을") { vp = "을" }
            let tt = copyRange(t, tgtStart, tgtEnd, "에")
            let vt = copyRange(t, valStart, valEnd, vp)
            if tt.count > 0 && vt.count > 0 {
                let tg = parseVerbatimRange(tt, 0, tt.count)
                if !tg.ok { return .failure(start, tg.err) }
                var v = parseVerbatimRange(vt, 0, vt.count)
                if !v.ok { return .failure(start, v.err) }
                if vt.count == 1 && vt[0].kind == .string {
                    let interp = interpolatedStringNode(vt[0].body)
                    if !interp.isNull { v = .success(v.pos, interp) }
                }
                let args: [ASTValue] = [.array([S("대상"), tg.node]), .array([S("내용"), v.node])]
                return .success(nextLine(t, end), [LineStmt(line, ASTNode("Execute", [("name", S("객체문자열쓰기")), ("args", .array(args)), ("is_try", B(false))]))])
            }
        }
    }
    if end >= start + 5 && t[end - 2].body == "연결한다" {
        var relEnd = end - 2
        var strong = false
        if t[relEnd - 1].body == "강하게" { strong = true; relEnd -= 1 }
        var oa = start
        while oa + 1 < relEnd && !endsObject(t[oa].body) { oa += 1 }
        var ba = oa + 1
        while ba + 1 < relEnd && !t[ba].body.hasSuffix("에") { ba += 1 }
        if endsObject(t[oa].body) && t[safe: ba].body.hasSuffix("에") && ba + 1 < relEnd {
            var op: BStr = "를"
            if t[oa].body.hasSuffix("을") { op = "을" }
            var rp: BStr = "로"
            if t[relEnd - 1].body.hasSuffix("으로") { rp = "으로" }
            let tt = copyRange(t, start, oa + 1, op)
            let bt = copyRange(t, oa + 1, ba + 1, "에")
            let rt = copyRange(t, ba + 1, relEnd, rp)
            if tt.count > 0 && bt.count > 0 && rt.count > 0 {
                let tg = parseVerbatimRange(tt, 0, tt.count)
                if !tg.ok { return .failure(start, tg.err) }
                let bs = parseVerbatimRange(bt, 0, bt.count)
                if !bs.ok { return .failure(start, bs.err) }
                let rl = parseVerbatimRange(rt, 0, rt.count)
                if !rl.ok { return .failure(start, rl.err) }
                let fn: BStr = strong ? "객체를관계로강하게연결" : "객체를관계로연결"
                let args: [ASTValue] = [.array([S("대상"), tg.node]), .array([S("기준"), bs.node]), .array([S("관계"), rl.node])]
                return .success(nextLine(t, end), [LineStmt(line, ASTNode("Execute", [("name", S(fn)), ("args", .array(args)), ("is_try", B(true))]))])
            }
        }
    }
    if end >= start + 5 && t[end - 2].body == "연결한다" {
        var relEnd = end - 2
        var strong = false
        if t[relEnd - 1].body == "강하게" { strong = true; relEnd -= 1 }
        var ca = start
        while ca + 1 < relEnd && !endsComitative(t[ca].body) { ca += 1 }
        var oa = ca + 1
        while oa + 1 < relEnd && !endsObject(t[oa].body) { oa += 1 }
        if endsComitative(t[ca].body) && endsObject(t[safe: oa].body) && oa + 1 < relEnd {
            var cp: BStr = "과"
            if t[ca].body.hasSuffix("와") { cp = "와" }
            var op: BStr = "를"
            if t[oa].body.hasSuffix("을") { op = "을" }
            var rp: BStr = "로"
            if t[relEnd - 1].body.hasSuffix("으로") { rp = "으로" }
            let lt = copyRange(t, start, ca + 1, cp)
            let rt2 = copyRange(t, ca + 1, oa + 1, op)
            let relT = copyRange(t, oa + 1, relEnd, rp)
            if lt.count > 0 && rt2.count > 0 && relT.count > 0 {
                let l = parseVerbatimRange(lt, 0, lt.count)
                if !l.ok { return .failure(start, l.err) }
                let r = parseVerbatimRange(rt2, 0, rt2.count)
                if !r.ok { return .failure(start, r.err) }
                let rl = parseVerbatimRange(relT, 0, relT.count)
                if !rl.ok { return .failure(start, rl.err) }
                let fn: BStr = strong ? "객체와객체를관계로강하게연결" : "객체와객체를관계로연결"
                let args: [ASTValue] = [.array([S("왼쪽"), l.node]), .array([S("오른쪽"), r.node]), .array([S("관계"), rl.node])]
                return .success(nextLine(t, end), [LineStmt(line, ASTNode("Execute", [("name", S(fn)), ("args", .array(args)), ("is_try", B(true))]))])
            }
        }
    }
    if end >= start + 5 && t[end - 2].body == "해제한다" && t[end - 4].body == "임시" && t[end - 3].body.hasSuffix("상태를") {
        let tt = copyRange(t, start, end - 4, "의")
        if tt.count > 0 && t[end - 5].body.hasSuffix("의") {
            let tg = parseVerbatimRange(tt, 0, tt.count)
            if !tg.ok { return .failure(start, tg.err) }
            let args: [ASTValue] = [.array([S("대상"), tg.node])]
            return .success(nextLine(t, end), [LineStmt(line, ASTNode("Execute", [("name", S("객체임시상태해제하기")), ("args", .array(args)), ("is_try", B(false))]))])
        }
    }
    if end >= start + 3 && t[end - 2].body == "저장한다" {
        var p: BStr = "를"
        if t[end - 3].body.hasSuffix("을") { p = "을" }
        let tt = copyRange(t, start, end - 2, p)
        if tt.count > 0 {
            let tg = parseVerbatimRange(tt, 0, tt.count)
            if !tg.ok { return .failure(start, tg.err) }
            let args: [ASTValue] = [.array([S("대상"), tg.node])]
            return .success(nextLine(t, end), [LineStmt(line, ASTNode("Execute", [("name", S("객체저장하기")), ("args", .array(args)), ("is_try", B(false))]))])
        }
    }
    if end >= start + 4 && t[end - 2].body == "넘긴다" && t[start + 1].body == "소유권을" && t[start].body.hasSuffix("의") {
        let name = stripSuffix(t[start].body, "의")
        var target = tokenRangeText(t, start + 2, end - 2)
        if target.hasSuffix("에게") { target = stripSuffix(target, "에게") } else { target = stripSuffix(target, "에") }
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("TransferOwnership", [("name", S(name)), ("target", S(target))]))])
    }
    // 정의
    let first = t[start].body
    if first == "단" || first == "자" || first == "상수" || first == "변수" {
        let mutable = first == "변수" || first == "자"
        let name = stripParticle(t[safe: start + 1].body)
        let comma = topLevelComma(t, start + 2, end)
        var exprEnd = end
        var typeVal: ASTValue = .null
        var deferred = false
        if comma < end {
            exprEnd = comma
            if exprEnd > start + 2 && t[exprEnd - 1].body == "이고" { exprEnd -= 1 }
            var typeStart = comma + 1
            if typeStart + 1 < end && t[typeStart].body == "타입은" { typeStart += 1 }
            var n = typeStart
            while n < end && t[n].body != "." { n += 1 }
            let typ = stripParticle(tokenRangeText(t, typeStart, n))
            typeVal = S(typ)
            let dict = dictionaryLiteralStmts(t, start + 2, exprEnd, line, name, mutable, typ)
            if dict.count > 0 { return .success(nextLine(t, end), dict) }
        } else if end > start + 3 && isDeferredTypeEnd(t[end - 2].body) {
            typeVal = S(stripParticle(tokenRangeText(t, start + 2, end - 1)))
            deferred = true
        }
        var defaultNode: ASTValue = .null
        if !deferred && comma >= end && end > start + 3 && t[end - 2].body.hasSuffix("이다") {
            let dt = stripIda(tokenRangeText(t, start + 2, end - 1))
            defaultNode = defaultValueExpr(dt)
            if !defaultNode.isNull { typeVal = S(dt) }
        }
        var exprNode: ASTValue
        if deferred {
            exprNode = N("DeferredDefaultExpr", [])
        } else if !defaultNode.isNull {
            exprNode = defaultNode
        } else {
            let e = parseRange(t, start + 2, exprEnd)
            if !e.ok { return .failure(start, e.err) }
            exprNode = e.node
        }
        return .success(nextLine(t, end), [defineStmt(line, mutable, name, typeVal, exprNode)])
    }
    if end >= start + 3 && t[end - 2].body == "붙인다" && t[start].kind == .name && t[start].body.hasSuffix("에") {
        let name = stripSuffix(t[start].body, "에")
        let e = parseRange(t, start + 1, end - 2)
        if !e.ok { return .failure(start, e.err) }
        return .success(nextLine(t, end), [assignNameStmt(line, name, CallExpr("문자열붙이기", [NameExpr(name), e.node]))])
    }
    if end >= start + 3 && isCollectionAddVerb(t[end - 2].body) && t[start].body.hasSuffix("에") {
        let arrName = stripSuffix(t[start].body, "에")
        let e = parseRange(t, start + 1, end - 2)
        if !e.ok { return .failure(start, e.err) }
        let colType = envType(env, arrName)
        if colType.hasSuffix("의 집합") || t[end - 2].body == "넣는다" {
            out.append(assignNameStmt(line, arrName, CallExpr("넣은것", [NameExpr(arrName), e.node])))
        } else {
            out.append(LineStmt(line, ASTNode("DynamicArrayAppend", [("name", S(arrName)), ("expr", e.node)])))
        }
        return .success(nextLine(t, end), out)
    }
    if end >= start + 5 && t[end - 2].body == "제거한다" && t[end - 3].body == "값을" && t[start].body.hasSuffix("에서") && t[end - 4].body.hasSuffix("번째") {
        let name = stripSuffix(t[start].body, "에서")
        let it = copyRange(t, start + 1, end - 3, "번째")
        if it.count == 0 { return .failure(start, "제거할 순번을 해석할 수 없습니다") }
        let i = parseVerbatimRange(it, 0, it.count)
        if !i.ok { return .failure(start, i.err) }
        let tgt = N("IndexTarget", [("base", N("NameTarget", [("name", S(name))])), ("index", i.node), ("natural", B(true))])
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("DynamicArrayRemove", [("target", tgt)]))])
    }
    if end >= start + 5 && t[end - 2].body == "제거한다" && isObjectParticleExact(t[end - 3].body) && t[end - 4].body == "]" {
        let tt = copyRange(t, start, end - 3, "")
        if tt.count == 0 { return .failure(start, "제거 대상을 해석할 수 없습니다") }
        let te = parseVerbatimRange(tt, 0, tt.count)
        if !te.ok { return .failure(start, te.err) }
        let tgt = toTarget(te.node)
        if tgt.isNull || tgt.kind != "IndexTarget" { return .failure(start, "제거 대상은 배열 인덱스여야 합니다") }
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("DynamicArrayRemove", [("target", tgt)]))])
    }
    if end >= start + 5 && t[end - 2].body == "삽입한다" && t[start].body.hasSuffix("에서") {
        var at = start + 1
        while at < end - 2 && t[at].body != "위치에" { at += 1 }
        if at < end - 2 && at > start + 1 && t[at - 1].body.hasSuffix("번째") {
            let name = stripSuffix(t[start].body, "에서")
            let it = copyRange(t, start + 1, at, "번째")
            if it.count == 0 { return .failure(start, "삽입할 순번을 해석할 수 없습니다") }
            let i = parseVerbatimRange(it, 0, it.count)
            if !i.ok { return .failure(start, i.err) }
            let v = parseRange(t, at + 1, end - 2)
            if !v.ok { return .failure(start, v.err) }
            let tgt = N("IndexTarget", [("base", N("NameTarget", [("name", S(name))])), ("index", i.node), ("natural", B(true))])
            return .success(nextLine(t, end), [LineStmt(line, ASTNode("DynamicArrayInsert", [("target", tgt), ("expr", v.node)]))])
        }
    }
    if end >= start + 5 && t[end - 2].body == "삽입한다" {
        var atIn = end
        var depth = 0
        var scan = start
        while scan < end - 2 {
            let b = t[scan].body
            if b == "[" || b == "(" {
                depth += 1
            } else if b == "]" || b == ")" {
                if depth > 0 { depth -= 1 }
            } else if depth == 0 && scan > start && atIn == end && b == "에" {
                if t[scan - 1].body == "]" { atIn = scan }
            }
            scan += 1
        }
        if atIn < end - 2 {
            let tt = copyRange(t, start, atIn, "")
            if tt.count == 0 { return .failure(start, "삽입 대상을 해석할 수 없습니다") }
            let te = parseVerbatimRange(tt, 0, tt.count)
            if !te.ok { return .failure(start, te.err) }
            let tgt = toTarget(te.node)
            if tgt.isNull || tgt.kind != "IndexTarget" { return .failure(start, "삽입 대상은 배열 인덱스여야 합니다") }
            let v = parseRange(t, atIn + 1, end - 2)
            if !v.ok { return .failure(start, v.err) }
            return .success(nextLine(t, end), [LineStmt(line, ASTNode("DynamicArrayInsert", [("target", tgt), ("expr", v.node)]))])
        }
    }
    if end >= start + 6 && t[end - 2].body == "확보한다" && t[end - 3].body == "메모리를" && t[end - 4].body == "담을" && t[end - 5].body.hasSuffix("개를") && endsSubject(t[start].body) {
        let name = stripSubject(t[start].body)
        let ct = copyRange(t, start + 1, end - 4, "개를")
        if ct.count == 0 { return .failure(start, "확보할 용량을 해석할 수 없습니다") }
        let c = parseVerbatimRange(ct, 0, ct.count)
        if !c.ok { return .failure(start, c.err) }
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("DynamicArrayReserve", [("name", S(name)), ("capacity", c.node)]))])
    }
    if end == start + 3 && t[end - 2].body == "비운다" && endsObject(t[start].body) {
        let name = stripObject(t[start].body)
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("DynamicArrayClear", [("name", S(name))]))])
    }
    if end >= start + 5 && t[start].body.hasSuffix("에서") {
        var ofAt = start + 1
        while ofAt < end && t[ofAt].body != "의" && !t[ofAt].body.hasSuffix("의") { ofAt += 1 }
        var keyEnd = ofAt
        let valStart = ofAt + 2
        if ofAt < end && t[ofAt].body != "의" { keyEnd = ofAt + 1 }
        if valStart < end && t[valStart - 1].body == "값은" {
            let dict = stripSuffix(t[start].body, "에서")
            let k = parseRange(t, start + 1, keyEnd)
            let v = parseRange(t, valStart, end)
            if !k.ok || !v.ok { return .failure(start, "사전 대입식을 해석할 수 없습니다") }
            return .success(nextLine(t, end), [assignNameStmt(line, dict, CallExpr("넣은것", [NameExpr(dict), k.node, v.node]))])
        }
    }
    if end >= start + 4 && t[end - 2].body == "지운다" && isDictLookupStart(t, start) && isObjectParticle(t[end - 3].body) {
        var p: BStr = "를"
        if t[end - 3].body.hasSuffix("을") { p = "을" }
        let it = copyRange(t, start + 1, end - 2, p)
        if it.count > 0 {
            let i = parseVerbatimRange(it, 0, it.count)
            if !i.ok { return .failure(start, i.err) }
            let name = stripSuffix(t[start].body, "에서")
            return .success(nextLine(t, end), [assignNameStmt(line, name, CallExpr("지운것", [NameExpr(name), i.node]))])
        }
    }
    if end == start + 3 && (t[end - 2].body == "실행한다" || t[end - 2].body == "시도한다") {
        let name = stripParticle(t[start].body)
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Execute", [("name", S(name)), ("args", .array([])), ("is_try", B(t[end - 2].body == "시도한다"))]))])
    }
    // 대입
    let asgAt = assignParticlePoint(t, start, end)
    if asgAt < end && t.body(end - 2) != "실행한다" && t.body(end - 2) != "시도한다" {
        var targetEnd = asgAt + 1
        if t[asgAt].body == "은" || t[asgAt].body == "는" { targetEnd = asgAt }
        let e = parseRange(t, asgAt + 1, end)
        if !e.ok { return .failure(start, e.err) }
        var target: ASTValue = .null
        if t[asgAt].body == "값은" {
            var fromAt = start
            while fromAt < asgAt && t[fromAt].body != "에서" && !t[fromAt].body.hasSuffix("에서") { fromAt += 1 }
            if fromAt + 1 < asgAt {
                var addr: [Token] = Array(t[start..<fromAt])
                if t[fromAt].body != "에서" {
                    var orig = t[fromAt]
                    orig.body = stripSuffix(orig.body, "에서")
                    addr.append(orig)
                }
                addr.append(Token(.end, "", line, 1))
                let ap = parseExpression(addr, 0, 1)
                if ap.ok {
                    let mt = stripParticle(tokenRangeText(t, fromAt + 1, asgAt))
                    target = N("OffsetMemoryTarget", [("address", ap.node), ("value_type", S(mt))])
                }
            }
        }
        if target.isNull && asgAt == start + 1 && t[start].body.hasSuffix("의") {
            let base = stripSuffix(t[start].body, "의")
            let field = stripParticle(t[asgAt].body)
            target = N("FieldTarget", [("base", N("NameTarget", [("name", S(base))])), ("field", S(field))])
        }
        if target.isNull {
            let te = parseRange(t, start, targetEnd)
            if !te.ok { return .failure(start, te.err) }
            target = toTarget(te.node)
        }
        if target.isNull { return .failure(start, "대입 대상을 해석할 수 없습니다") }
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Assign", [("target", target), ("expr", e.node)]))])
    }
    if end >= start + 4 && t[end - 2].body == "종료한다" && t[start].body == "코드" {
        let c = parseRange(t, start + 1, end - 2)
        if !c.ok { return .failure(start, c.err) }
        let args: ASTValue = .array([.array([S("코드"), castNatural64(c.node)])])
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Execute", [("name", S("종료")), ("args", args), ("is_try", B(false))]))])
    }
    if end >= start + 6 && (t[end - 2].body == "실행한다" || t[end - 2].body == "시도한다") && t[start + 1].body == "(" {
        let name = stripParticle(t[start].body)
        var close = start + 2
        var depth = 1
        while close < end && depth > 0 {
            if t[close].body == "(" {
                depth += 1
            } else if t[close].body == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            close += 1
        }
        if depth != 0 || close + 4 != end || (t[close + 1].body != "로" && t[close + 1].body != "으로") {
            return .failure(close, "실행/시도 인자 뒤에는 로 실행한다 또는 로 시도한다가 필요합니다")
        }
        if close == start + 2 { return .failure(close, "인자가 없는 실행/시도는 괄호 없이 써야 합니다") }
        var args: [ASTValue] = []
        var ap = start + 2
        while ap < close {
            if ap + 1 >= close || t[ap + 1].body != ":" { return .failure(ap, "실행 인자는 이름: 값 형식이어야 합니다") }
            let an = t[ap].body
            let cp = topLevelComma(t, ap + 2, close)
            var ae = parseVerbatimRange(t, ap + 2, cp)
            if !ae.ok { return .failure(ap, ae.err) }
            if cp == ap + 3 && t[ap + 2].kind == .string {
                let interp = interpolatedStringNode(t[ap + 2].body)
                if !interp.isNull { ae = .success(ae.pos, interp) }
            }
            args.append(.array([S(an), ae.node]))
            ap = cp + 1
        }
        return .success(nextLine(t, end), [LineStmt(line, ASTNode("Execute", [("name", S(name)), ("args", .array(args)), ("is_try", B(t[end - 2].body == "시도한다"))]))])
    }
    // 출력
    var printAt = start
    while printAt < end && t[printAt].body != "출력한다" { printAt += 1 }
    if printAt < end {
        var exprEnd = printAt
        var errMode = false
        var pieceMode = false
        if printAt > start && t[printAt - 1].body == "오류로" { errMode = true; exprEnd = printAt - 1 }
        if printAt > start && t[printAt - 1].body == "이어" { pieceMode = true; exprEnd = printAt - 1 }
        if printAt > start + 1 && t[printAt - 1].body == "없이" && t[printAt - 2].body == "줄바꿈" { pieceMode = true; exprEnd = printAt - 2 }
        let e = parseRange(t, start, exprEnd)
        if !e.ok { return .failure(start, e.err) }
        var pieces: [ASTValue] = [e.node]
        if t[start].kind == .string { pieces = stringPieceNodes(e.node) }
        if errMode || pieceMode || pieces.count > 1 {
            let fn: BStr = errMode ? "오류출력조각" : "출력조각"
            for p in pieces { out.append(exprStmt(line, CallExpr(fn, [p]))) }
            if !pieceMode {
                out.append(exprStmt(line, CallExpr(fn, [N("StringLiteral", [("value", S("\n"))])])))
            }
        } else {
            out.append(exprStmt(line, CallExpr("출력", [e.node])))
        }
        return .success(nextLine(t, end), out)
    }
    let e = parseRange(t, start, end)
    if !e.ok { return .failure(start, e.err) }
    return .success(nextLine(t, end), [exprStmt(line, e.node)])
}

/// 파싱멤버머리위치 (프론트엔드/초기화파서.hmje)
func memberHeadPoint(_ t: [Token], _ start: Int, _ end: Int) -> Int {
    let pos = start
    if pos < end && t[pos].body == "공개" { return pos + 1 }
    if pos + 1 < end && t[pos + 1].body == "내부" {
        let scope = t[pos].body
        if scope == "타입" || scope == "파일" || scope == "모듈" || scope == "프로젝트" { return pos + 2 }
    }
    return pos
}
