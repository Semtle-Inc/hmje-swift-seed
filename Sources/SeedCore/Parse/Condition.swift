// 프론트엔드/문장파서.hmje의 조건 파서(파싱자연조건 계열). 널(.null)은 "조건으로 서지 않음".

/// 파싱조건노드
func conditionFromExpr(_ e: ASTValue) -> ASTValue {
    if e.kind == "BinaryExpr" {
        let op = e.str("op")
        if op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=" {
            return N("CompareCondition", [("left", e["left"]), ("op", S(op)), ("right", e["right"])])
        }
    }
    return N("BoolExprCondition", [("expr", e)])
}

@inline(__always) func NotCond(_ c: ASTValue) -> ASTValue { N("NotCondition", [("condition", c)]) }
@inline(__always) func BoolCond(_ e: ASTValue) -> ASTValue { N("BoolExprCondition", [("expr", e)]) }

/// 파싱동안조건: `A일 동안`의 `일`을 뗀다.
func parseWhileCondition(_ t: [Token], _ start: Int, _ end: Int) -> ASTValue {
    var pieces: [Token] = []
    var i = start
    while i < end {
        var tok = t[i]
        if i + 1 == end && tok.body.hasSuffix("일") { tok.body = stripSuffix(tok.body, "일") }
        if tok.body.count > 0 { pieces.append(tok) }
        i += 1
    }
    return parseNaturalCondition(pieces, 0, pieces.count)
}

/// 파싱부정연결왼쪽: 마지막 토큰의 가/이를 떼고 조건으로 읽는다.
func parseNegatedLeft(_ t: [Token], _ start: Int, _ end: Int) -> ASTValue {
    var pieces: [Token] = []
    var i = start
    while i < end {
        var tok = t[i]
        if i + 1 == end {
            if tok.body.hasSuffix("가") { tok.body = stripSuffix(tok.body, "가") }
            else if tok.body.hasSuffix("이") { tok.body = stripSuffix(tok.body, "이") }
        }
        if tok.body.count > 0 { pieces.append(tok) }
        i += 1
    }
    return parseNaturalCondition(pieces, 0, pieces.count)
}

/// 파싱토큰사이띄어짐인가
func spacedAfter(_ t: [Token], _ pos: Int) -> Bool {
    let a = t[safe: pos], b = t[safe: pos + 1]
    if b.line != a.line { return true }
    if b.col != a.col + a.body.count { return true }
    return false
}

/// 파싱주격같은지조건: `값이 10이 아니면`의 값 비교(부정은 호출자가 씌운다).
func parseDoubleSubjectEquality(_ t: [Token], _ start: Int, _ end: Int) -> ASTValue {
    if end < start + 2 { return .null }
    let rightEnd = t[end - 1].body
    if !endsSubject(rightEnd) { return .null }
    var rightP: BStr = "가"
    if rightEnd.hasSuffix("이") { rightP = "이" }
    var split = end
    var look = start
    while look + 1 < end && split == end {
        let lb = t[look].body
        if endsSubject(lb) && spacedAfter(t, look) {
            var emptyLeft = false
            if look == start && lb.count == 3 { emptyLeft = true }
            if !emptyLeft { split = look }
        }
        if split == end { look += 1 }
    }
    if split == end { return .null }
    var leftP: BStr = "가"
    if t[split].body.hasSuffix("이") { leftP = "이" }
    let leftToks = copyRange(t, start, split + 1, leftP)
    if leftToks.count == 0 { return .null }
    let rightToks = copyRange(t, split + 1, end, rightP)
    if rightToks.count == 0 { return .null }
    let l = parseVerbatimRange(leftToks, 0, leftToks.count)
    if !l.ok { return .null }
    let r = parseVerbatimRange(rightToks, 0, rightToks.count)
    if !r.ok { return .null }
    return BoolCond(CallExpr("같은지", [l.node, r.node]))
}

/// 파싱자연논리단계
func parseLogicLevel(_ t: [Token], _ start: Int, _ end: Int, _ conj: BStr, _ negConj: BStr) -> ASTValue {
    var pos = start
    var pieceStart = start
    var depth = 0
    var acc: ASTValue = .null
    while pos < end {
        let b = t[pos].body
        if b == "(" || b == "[" {
            depth += 1
        } else if b == ")" || b == "]" {
            if depth > 0 { depth -= 1 }
        } else if depth == 0 && (b == conj || b == negConj) {
            if pieceStart == pos { return .null }
            var piece: ASTValue
            if b == negConj {
                let base = parseNegatedLeft(t, pieceStart, pos)
                if base.isNull { return .null }
                piece = NotCond(base)
            } else {
                piece = parseNaturalCondition(t, pieceStart, pos)
            }
            if piece.isNull { return .null }
            if acc.isNull { acc = piece }
            else { acc = N("LogicalCondition", [("left", acc), ("op", S(conj)), ("right", piece)]) }
            pieceStart = pos + 1
        }
        pos += 1
    }
    if pieceStart == end || acc.isNull { return .null }
    let last = parseNaturalCondition(t, pieceStart, end)
    if last.isNull { return .null }
    return N("LogicalCondition", [("left", acc), ("op", S(conj)), ("right", last)])
}

/// 파싱자연조건
func parseNaturalCondition(_ t: [Token], _ start: Int, _ end: Int) -> ASTValue {
    var realEnd = end
    while realEnd > start && isPunctEnd(t[realEnd - 1].body) { realEnd -= 1 }
    if realEnd > start && t[realEnd - 1].body == "이면" { realEnd -= 1 }
    // 괄호가 조건 전체를 감싼 꼴
    if realEnd >= start + 2 && t[start].body == "(" && t[realEnd - 1].body == ")" {
        var depth = 0
        var i = start
        var whole = true
        while i < realEnd - 1 {
            if t[i].body == "(" { depth += 1 }
            else if t[i].body == ")" { if depth > 0 { depth -= 1 } }
            if depth == 0 { whole = false }
            i += 1
        }
        if whole { return parseNaturalCondition(t, start + 1, realEnd - 1) }
    }
    if realEnd > start + 1 && t[realEnd - 1].body == "아닐" {
        return NotCond(parseNegatedLeft(t, start, realEnd - 1))
    }
    if realEnd > start {
        let endBody = t[realEnd - 1].body
        var suffix: BStr = ""
        if !isExistenceEnd(endBody) && endBody != "아니면" && endBody.hasSuffix("이면") && endBody.count > 6 {
            suffix = "이면"
        } else if !isExistenceEnd(endBody) && endBody != "아니면" && endBody != "이면" && endBody.hasSuffix("면") && endBody.count > 3 {
            suffix = "면"
        }
        if suffix.count > 0 {
            var toks: [Token] = []
            var i = start
            while i < realEnd {
                var tok = t[i]
                if i + 1 == realEnd { tok.body = stripSuffix(tok.body, suffix) }
                toks.append(tok)
                i += 1
            }
            return parseNaturalCondition(toks, 0, toks.count)
        }
    }
    let orAt = topLevelLogic(t, start, realEnd, "또는")
    let norAt = topLevelLogic(t, start, realEnd, "아니거나")
    if orAt < realEnd || norAt < realEnd {
        return parseLogicLevel(t, start, realEnd, "또는", "아니거나")
    }
    let andAt = topLevelLogic(t, start, realEnd, "그리고")
    let nandAt = topLevelLogic(t, start, realEnd, "아니고")
    if andAt < realEnd || nandAt < realEnd {
        return parseLogicLevel(t, start, realEnd, "그리고", "아니고")
    }
    if realEnd > start + 1 && t[start].body == "!" {
        return NotCond(parseNaturalCondition(t, start + 1, realEnd))
    }
    // `A가 B와 같으면`·`다르면`
    if realEnd >= start + 3 {
        let pred = t[realEnd - 1].body
        var cmpKind = 0
        if pred == "같으" || pred == "같" { cmpKind = 1 } else if pred == "다르" { cmpKind = 2 }
        let rb = t[realEnd - 2].body
        var rightP: BStr = ""
        if rb.hasSuffix("와") { rightP = "와" } else if rb.hasSuffix("과") { rightP = "과" }
        if cmpKind > 0 && rightP.count > 0 {
            var subjAt = start
            var subjP: BStr = ""
            while subjAt + 1 < realEnd - 2 && subjP.count == 0 {
                if t[subjAt].body.hasSuffix("이") { subjP = "이" }
                else if t[subjAt].body.hasSuffix("가") { subjP = "가" }
                else { subjAt += 1 }
            }
            if subjP.count > 0 {
                let lt = copyRange(t, start, subjAt + 1, subjP)
                let rt = copyRange(t, subjAt + 1, realEnd - 1, rightP)
                if lt.count > 0 && rt.count > 0 {
                    let l = parseVerbatimRange(lt, 0, lt.count)
                    let r = parseVerbatimRange(rt, 0, rt.count)
                    if l.ok && r.ok {
                        let c = BoolCond(CallExpr("같은지", [l.node, r.node]))
                        if cmpKind == 2 { return NotCond(c) }
                        return c
                    }
                }
            }
        }
    }
    // `A가 B보다 크거나 같`·`작거나 같`·`크`·`작`
    if realEnd >= start + 3 {
        var op: BStr = ""
        var thanAt = realEnd
        let pred = t[realEnd - 1].body
        if realEnd >= start + 4 && t[realEnd - 2].body == "크거나" {
            if pred == "같으" || pred == "같" { op = ">="; thanAt = realEnd - 3 }
        } else if realEnd >= start + 4 && t[realEnd - 2].body == "작거나" {
            if pred == "같으" || pred == "같" { op = "<="; thanAt = realEnd - 3 }
        } else if pred == "크" {
            op = ">"; thanAt = realEnd - 2
        } else if pred == "작" || pred == "작으" {
            op = "<"; thanAt = realEnd - 2
        }
        if op.count > 0 && thanAt > start && t[thanAt].body.hasSuffix("보다") {
            var leftP: BStr = ""
            if t[start].body.hasSuffix("가") { leftP = "가" } else if t[start].body.hasSuffix("이") { leftP = "이" }
            let lt = copyRange(t, start, start + 1, leftP)
            let rt = copyRange(t, start + 1, thanAt + 1, "보다")
            if lt.count > 0 && rt.count > 0 {
                let l = parseVerbatimRange(lt, 0, lt.count)
                let r = parseVerbatimRange(rt, 0, rt.count)
                if l.ok && r.ok {
                    return N("CompareCondition", [("left", l.node), ("op", S(op)), ("right", r.node)])
                }
            }
        }
    }
    // 기다린 결과가 비교보다 먼저 묶이는 꼴
    let cmpAt = topLevelCompare(t, start, realEnd)
    var awaitAt = cmpAt
    var scan = start
    while scan < cmpAt {
        if t[scan].body == "기다린" { awaitAt = scan }
        scan += 1
    }
    if cmpAt < realEnd && awaitAt < cmpAt {
        let l = parseRange(t, start, cmpAt)
        let r = parseExactRange(t, cmpAt + 1, realEnd)
        if l.ok && r.ok {
            return N("CompareCondition", [("left", l.node), ("op", S(t[cmpAt].body)), ("right", r.node)])
        }
    }
    if realEnd >= start + 3 && t[realEnd - 1].body == "아니면" && spacedAfter(t, realEnd - 2) {
        let eq = parseDoubleSubjectEquality(t, start, realEnd - 1)
        if !eq.isNull { return NotCond(eq) }
    }
    if realEnd >= start + 3 && t[realEnd - 2].body == "가" && t[realEnd - 1].body == "아니면" {
        let e = parseRange(t, start, realEnd - 2)
        if !e.ok { return .null }
        return NotCond(BoolCond(e.node))
    }
    if realEnd == start + 2 && t[start + 1].body == "아니면" {
        let orig = t[start].body
        if orig.hasSuffix("이") || orig.hasSuffix("가") {
            let name = stripSuffix(stripSuffix(orig, "가"), "이")
            return NotCond(BoolCond(NameExpr(name)))
        }
    }
    if realEnd > start + 2 && t[realEnd - 1].body == "아니면" && endsSubject(t[realEnd - 2].body) && spacedAfter(t, realEnd - 2) {
        let lc = parseNegatedLeft(t, start, realEnd - 1)
        if !lc.isNull { return NotCond(lc) }
    }
    // `X가 비었으면`
    if realEnd >= start + 2 && endsSubject(t[realEnd - 2].body) {
        let pred = t[realEnd - 1].body
        if pred == "비었으" || pred == "비었" {
            var p: BStr = "이"
            if t[realEnd - 2].body.hasSuffix("가") { p = "가" }
            let bt = copyRange(t, start, realEnd - 1, p)
            if bt.count > 0 {
                let b = parseVerbatimRange(bt, 0, bt.count)
                if b.ok { return BoolCond(CallExpr("문자열비었는가", [b.node])) }
            }
        }
    }
    // `모음에 값이 있으면`
    if realEnd >= start + 3 && isExistenceEnd(t[realEnd - 1].body) && endsSubject(t[realEnd - 2].body) {
        var at = start
        while at + 1 < realEnd - 1 && !t[at].body.hasSuffix("에") { at += 1 }
        if t[at].body.hasSuffix("에") && at + 1 < realEnd - 1 {
            var p: BStr = "이"
            if t[realEnd - 2].body.hasSuffix("가") { p = "가" }
            let ct = copyRange(t, start, at + 1, "에")
            let vt = copyRange(t, at + 1, realEnd - 1, p)
            if ct.count > 0 && vt.count > 0 {
                let c = parseVerbatimRange(ct, 0, ct.count)
                let v = parseVerbatimRange(vt, 0, vt.count)
                if c.ok && v.ok {
                    let cond = BoolCond(CallExpr("포함되는지", [c.node, v.node]))
                    if t[realEnd - 1].body == "없으면" { return NotCond(cond) }
                    return cond
                }
            }
        }
    }
    var existParticle = false
    if realEnd >= start + 2 {
        if t[realEnd - 2].body == "가" || t[realEnd - 2].body == "이" { existParticle = true }
    }
    if realEnd >= start + 3 && existParticle && isExistenceEnd(t[realEnd - 1].body) {
        let e = parseRange(t, start, realEnd - 2)
        if !e.ok { return .null }
        return N("OptionalHasValueCondition", [("expr", e.node), ("has_value", B(t[realEnd - 1].body == "있으면"))])
    }
    if realEnd > start + 2 && isExistenceEnd(t[realEnd - 1].body) {
        let e = parseRange(t, start, realEnd - 1)
        if e.ok {
            var node = e.node
            if node.kind == "FieldAccessExpr" {
                let f = node.str("field")
                if f.hasSuffix("이") || f.hasSuffix("가") {
                    let real = stripSuffix(stripSuffix(f, "가"), "이")
                    node = N("FieldAccessExpr", [("base", node["base"]), ("field", S(real))])
                }
                return N("OptionalHasValueCondition", [("expr", node), ("has_value", B(t[realEnd - 1].body == "있으면"))])
            }
        }
    }
    if realEnd == start + 2 && isExistenceEnd(t[start + 1].body) {
        let name = stripSuffix(stripSuffix(t[start].body, "가"), "이")
        return N("OptionalHasValueCondition", [("expr", NameExpr(name)), ("has_value", B(t[start + 1].body == "있으면"))])
    }
    if realEnd == start + 3 && t[start + 1].body == "값이" {
        let src = stripSuffix(t[start].body, "의")
        let bind = stripSuffix(t[start + 2].body, "이면")
        return N("OptionalBindCondition", [("expr", NameExpr(src)), ("name", S(bind))])
    }
    if realEnd >= start + 4 && t[realEnd - 2].body == "값이" && t[realEnd - 3].body.hasSuffix("의") && isDictLookupStart(t, start) {
        let keyToks = copyRange(t, start + 1, realEnd - 2, "의")
        if keyToks.count > 0 {
            let k = parseVerbatimRange(keyToks, 0, keyToks.count)
            if k.ok {
                let dict = NameExpr(stripSuffix(t[start].body, "에서"))
                let lookup = CallExpr("사전에서값", [dict, k.node])
                let v = stripSuffix(t[realEnd - 1].body, "이면")
                return N("OptionalBindCondition", [("expr", lookup), ("name", S(v))])
            }
        }
    }
    if realEnd > start + 3 && t[realEnd - 2].body == "값이" && t[realEnd - 3].body.hasSuffix("의") {
        let bt = copyRange(t, start, realEnd - 2, "의")
        if bt.count > 0 {
            let b = parseVerbatimRange(bt, 0, bt.count)
            if b.ok {
                let name = stripSuffix(t[realEnd - 1].body, "이면")
                return N("OptionalBindCondition", [("expr", b.node), ("name", S(name))])
            }
        }
    }
    if realEnd == start + 3 && isExistenceEnd(t[start + 2].body) && t[start].body.hasSuffix("에") {
        let col = NameExpr(stripSuffix(t[start].body, "에"))
        let val = NameExpr(stripSuffix(stripSuffix(t[start + 1].body, "가"), "이"))
        let cond = BoolCond(CallExpr("포함되는지", [col, val]))
        if t[start + 2].body == "없으면" { return NotCond(cond) }
        return cond
    }
    // `A에 B가 포함되어 있(으)`
    if realEnd >= start + 4 && t[realEnd - 2].body == "포함되어" && endsSubject(t[realEnd - 3].body) {
        let pred = t[realEnd - 1].body
        if pred == "있으면" || pred == "있으" || pred == "있" {
            var at = start
            while at + 1 < realEnd - 2 && !t[at].body.hasSuffix("에") { at += 1 }
            if t[at].body.hasSuffix("에") && at + 1 < realEnd - 2 {
                var p: BStr = "이"
                if t[realEnd - 3].body.hasSuffix("가") { p = "가" }
                let bt = copyRange(t, start, at + 1, "에")
                let vt = copyRange(t, at + 1, realEnd - 2, p)
                if bt.count > 0 && vt.count > 0 {
                    let b = parseVerbatimRange(bt, 0, bt.count)
                    let v = parseVerbatimRange(vt, 0, vt.count)
                    if b.ok && v.ok { return BoolCond(CallExpr("문자열포함하는가", [b.node, v.node])) }
                }
            }
        }
    }
    // `A가 B로 시작하`·`끝나`
    if realEnd >= start + 3 {
        let pred = t[realEnd - 1].body
        var call: BStr = ""
        if pred == "시작하" || pred == "시작" { call = "문자열시작하는가" }
        else if pred == "끝나" || pred == "끝" { call = "문자열끝나는가" }
        if call.count > 0 && t[realEnd - 2].body.hasSuffix("로") {
            var at = start
            while at + 1 < realEnd - 1 && !endsSubject(t[at].body) { at += 1 }
            if endsSubject(t[at].body) && at + 1 < realEnd - 1 {
                var sp: BStr = "이"
                if t[at].body.hasSuffix("가") { sp = "가" }
                var ip: BStr = "로"
                if t[realEnd - 2].body.hasSuffix("으로") { ip = "으로" }
                let bt = copyRange(t, start, at + 1, sp)
                let vt = copyRange(t, at + 1, realEnd - 1, ip)
                if bt.count > 0 && vt.count > 0 {
                    let b = parseVerbatimRange(bt, 0, bt.count)
                    let v = parseVerbatimRange(vt, 0, vt.count)
                    if b.ok && v.ok { return BoolCond(CallExpr(call, [b.node, v.node])) }
                }
            }
        }
    }
    // `A가 B를 포함하[지 않]`·`A가 비어있지 않`
    if realEnd >= start + 3 {
        let pred = t[realEnd - 1].body
        var negated = false
        var verbAt = realEnd
        var emptyCheck = false
        if pred == "포함하" || pred == "포함" {
            verbAt = realEnd - 1
        } else if pred == "않으" || pred == "않" {
            if t[realEnd - 2].body == "포함하지" {
                negated = true
                verbAt = realEnd - 2
            } else if t[realEnd - 2].body == "비어있지" {
                negated = true
                emptyCheck = true
                verbAt = realEnd - 2
            }
        }
        if emptyCheck && verbAt > start && endsSubject(t[verbAt - 1].body) {
            var p: BStr = "이"
            if t[verbAt - 1].body.hasSuffix("가") { p = "가" }
            let bt = copyRange(t, start, verbAt, p)
            if bt.count > 0 {
                let b = parseVerbatimRange(bt, 0, bt.count)
                if b.ok { return NotCond(BoolCond(CallExpr("문자열비었는가", [b.node]))) }
            }
        }
        if !emptyCheck && verbAt > start + 1 && endsObject(t[safe: verbAt - 1].body) {
            var at = start
            while at + 1 < verbAt - 1 && !endsSubject(t[at].body) { at += 1 }
            if endsSubject(t[at].body) {
                var sp: BStr = "이"
                if t[at].body.hasSuffix("가") { sp = "가" }
                var op: BStr = "를"
                if t[verbAt - 1].body.hasSuffix("을") { op = "을" }
                let ct = copyRange(t, start, at + 1, sp)
                let vt = copyRange(t, at + 1, verbAt, op)
                if ct.count > 0 && vt.count > 0 {
                    let c = parseVerbatimRange(ct, 0, ct.count)
                    let v = parseVerbatimRange(vt, 0, vt.count)
                    if c.ok && v.ok {
                        let cond = BoolCond(CallExpr("포함되는지", [c.node, v.node]))
                        if negated { return NotCond(cond) }
                        return cond
                    }
                }
            }
        }
    }
    if realEnd >= start + 3 && t[realEnd - 1].body == "결과" && t[realEnd - 2].body == "기다린" {
        let e = parseRange(t, start, realEnd)
        if e.ok { return conditionFromExpr(e.node) }
    }
    let ce = parseExactRange(t, start, realEnd)
    if !ce.ok {
        if cmpAt < realEnd && cmpAt > start {
            let l = parseRange(t, start, cmpAt)
            let r = parseExactRange(t, cmpAt + 1, realEnd)
            if l.ok && r.ok {
                return N("CompareCondition", [("left", l.node), ("op", S(t[cmpAt].body)), ("right", r.node)])
            }
        }
        return .null
    }
    return conditionFromExpr(ce.node)
}

/// 파싱문자열조각노드들: 보간이 만든 문자열붙인값을 출력 조각으로 되푼다.
func stringPieceNodes(_ n: ASTValue) -> [ASTValue] {
    if n.kind == "CallExpr" && n.str("name") == "문자열로만들기" {
        if case .array(let args) = n["args"], args.count == 1 { return [args[0]] }
    }
    if n.kind == "CallExpr" && n.str("name") == "문자열붙인값" {
        if case .array(let args) = n["args"], args.count == 2 {
            return stringPieceNodes(args[0]) + stringPieceNodes(args[1])
        }
    }
    return [n]
}
