// HMIR생성/문서.hmje + 증분.hmje(캐시 끔 경로) + 접근.hmje

extension HMIRGenerator {

    // 정본: HMIR표면동적배열수집
    func collectSurfaceDynArrays(_ v: J) {
        switch v {
        case .string(let t):
            if t.hasSuffix("의 배열") {
                let inner = typeResolve(t)
                if inner.hasPrefix("struct:") && inner.hasSuffix("동적배열형") {
                    surfaceDynArrayRegister(hSub(inner, 7, inner.count - 7))
                }
            }
        case .array(let a):
            for x in a { collectSurfaceDynArrays(x) }
        case .object(_, let vs):
            for x in vs { collectSurfaceDynArrays(x) }
        default: break
        }
    }

    // 정본: HMIR함수값표시수집
    func collectFnDisplays(_ sd: J) {
        let optSuf: BStr = "선택값"
        let ks = sd.objectKeys, vs = sd.objectValues
        for i in 0..<ks.count {
            let name = ks[i]
            if name.hasPrefix("함수값") && name.hasSuffix(optSuf) {
                let vf = astObjField(vs[i], "값")
                if !astIsNull(vf) {
                    let pre = hSub(name, 0, name.count - optSuf.count)
                    fnDisplayRegister(pre, typeDisplay(astStr(vf)))
                }
            } else if name.hasSuffix(optSuf) {
                let vf = astObjField(vs[i], "값")
                if !astIsNull(vf) {
                    let vt = typeResolve(astStr(vf))
                    if fixedArrayElemType(vt).count > 0 {
                        let pre = hSub(name, 0, name.count - optSuf.count)
                        fnDisplayRegister(pre, typeDisplay(vt))
                    }
                }
            }
        }
    }

    // 정본: HMIR채널표시수집
    func collectChannelDisplays(_ fns: J) {
        let sendPre: BStr = "HMJE채널보내기_"
        let ks = fns.objectKeys, vs = fns.objectValues
        for i in 0..<ks.count {
            let fname = ks[i]
            if fname.hasPrefix(sendPre) {
                if jHas(vs[i], 0) {
                    let params = astField(jAt(vs[i], 0), "params")
                    if jHas(params, 1) {
                        let ed = typeDisplay(astStrField(jAt(params, 1), "type_name"))
                        let pt = hObjParticle(ed)
                        let suf = hSub(fname, sendPre.count, fname.count - sendPre.count)
                        fnDisplayRegister(hcat("HMJE채널송신_", suf), hcat(ed, pt, " 보내는 채널"))
                        fnDisplayRegister(hcat("HMJE채널수신_", suf), hcat(ed, pt, " 받는 채널"))
                    }
                }
            }
        }
    }

    // 정본: HMIR오류모으기
    func errCollect(_ acc: BStr, _ item: BStr) -> BStr {
        if acc.count == 0 { return item }
        return hcat(acc, "\n", item)
    }

    // 정본: HMIR문서생성
    func documentGenerate(statements stmts: J) -> HState {
        var st = stateStart()
        registryReset()
        collectSurfaceDynArrays(stmts)
        collectFnDisplays(structs)
        collectChannelDisplays(funcs)
        let stmtArr = stmts.arrayValue
        for pair in stmtArr {
            if jHas(pair, 1) {
                let node = jAt(pair, 1)
                if astKind(node) == "StructDef" {
                    st = symAdd(st, hcat("@구조체엔디안:", astStrField(node, "name")), astStrField(node, "endian"))
                }
            }
        }
        st = returnConsumePreCollectAll(st)
        st = addLine(st, "모듈 훈민정음")
        for pair in stmtArr {
            let node = jAt(pair, 1)
            if astKind(node) == "EnumDef" {
                st = enumRegister(st, node)
                st = enumDeclare(st, node)
                if !st.ok { return st }
            }
        }
        st = structDeclarations(st)
        for pair in stmtArr {
            let node = jAt(pair, 1)
            let kind = astKind(node)
            if kind == "GlobalDefine" || kind == "ExternalGlobal" {
                var t = typeResolve(astStrField(node, "type_name"))
                if kind == "GlobalDefine" && t.count == 0 { t = exprStaticType(astField(node, "expr"), st) }
                st = symAdd(st, astStrField(node, "name"), t)
            }
        }
        // HMIR증분환경설정: 캐시 끔 → 아무것도 하지 않는다.
        var errs: BStr = ""
        for pair in stmtArr {
            let node = objectSetAssign(jAt(pair, 1))
            let kind = astKind(node)
            let before = st
            if kind != "FunctionDef" {
                st = accessContext(st, node)
            }
            if kind == "FunctionDef" {
                st = plainFunction(st, node)
                if !st.ok { errs = errCollect(errs, st.err); st = before }
            }
            if kind == "ExternalGlobal" {
                let line = hcat("  외부전역 ", astStrField(node, "name"), ": ", typeDisplay(typeResolve(astStrField(node, "type_name"))))
                st = addLine(st, line)
            }
            if kind == "GlobalDefine" {
                var gt = typeResolve(astStrField(node, "type_name"))
                if gt.count == 0 { gt = exprStaticType(astField(node, "expr"), st) }
                let ge = lowerExpr(astField(node, "expr"), st, gt)
                st = ge.st
                let gok = st.ok
                if !gok {
                    errs = errCollect(errs, st.err)
                    st = before
                    if gt.count > 0 { st = symAdd(st, astStrField(node, "name"), gt) }
                }
                var line: BStr = "  "
                if astBoolField(node, "mutable") { line = hcat(line, "전역변수 ") } else { line = hcat(line, "전역상수 ") }
                line = hcat(line, astStrField(node, "name"), ": ", typeDisplay(gt), " = ", ge.val)
                let sec = astField(node, "section")
                let al = astField(node, "alignment")
                if !astIsNull(sec) { line = hcat(line, " [섹션 '", astStr(sec), "'") }
                if !astIsNull(al) {
                    if !astIsNull(sec) { line = hcat(line, ", 정렬 ") } else { line = hcat(line, " [정렬 ") }
                    line = hcat(line, astTagStr(al, "integer"))
                }
                if !astIsNull(sec) || !astIsNull(al) { line = hcat(line, "]") }
                if gok {
                    st = addLine(st, line)
                    st = symAdd(st, astStrField(node, "name"), gt)
                }
            }
            if kind == "Define" {
                st = functionStatements(st, .array([pair]), "void")
                if !st.ok { errs = errCollect(errs, st.err); st = before }
            }
            if kind == "UnsafeBlock" {
                let outer = st.sym
                st = addLine(st, "  위험구역")
                st = ctxChange(st, 2, outer)
                st = symAdd(st, "@위험구역", "bool")
                st = functionStatements(st, astField(node, "body"), "void")
                let uok = st.ok
                if !uok { errs = errCollect(errs, st.err); st = before }
                if uok { st = scopeBorrowCleanup(st, outer.len) }
                var pin = st.sym.len
                while pin > outer.len {
                    pin -= 1
                    let ps = st.sym.name(pin)
                    if ps.hasPrefix("@고정:") {
                        st = addLine(st, hcat("    주소고정끝 ", hSub(ps, 8, ps.count - 8)))
                    }
                }
                var keepN: [BStr] = [], keepT: [BStr] = []
                var fi = 0
                while fi < st.sym.len {
                    let fs = st.sym.name(fi)
                    var marker = false
                    if fi >= outer.len {
                        if fs.hasPrefix("@소유:") || fs.hasPrefix("@지역text:") { marker = true }
                        if fs.hasPrefix("@소유선택text:") || fs.hasPrefix("@소유struct:") { marker = true }
                        if fs == "@위험구역" { marker = true }
                    }
                    if !marker { keepN.append(fs); keepT.append(st.sym.type(fi)) }
                    fi += 1
                }
                st = ctxChange(st, 1, SymTab.fresh(keepN, keepT))
                st = addLine(st, "  위험구역끝")
            }
            switch kind {
            case "ReferenceDefine", "MoveDefine", "ExprStmt", "Assign", "DynamicArrayAppend", "DynamicArrayClear",
                 "DynamicArrayReserve", "DynamicArrayRemove", "DynamicArrayInsert", "If", "While", "ForEach",
                 "Execute", "Forget", "TransferOwnership", "PinAddress", "ManualRelease", "AsyncRootRun":
                st = functionStatements(st, .array([pair]), "void")
                if !st.ok { errs = errCollect(errs, st.err); st = before }
            default: break
            }
        }
        if errs.count > 0 { return fail(st, errs) }
        st = scopeBorrowCleanup(st, 0)
        st = addLine(st, "모듈끝")
        return st
    }

    // 정본: HMIR일반함수 (증분 끔)
    func plainFunction(_ s: HState, _ node: J) -> HState {
        if !astIsNull(astField(node, "external_name")) {
            return plainFunctionDirect(s, node)
        }
        let start = HState(lines: .empty(), tmp: 0, tmpPrefix: "%f", label: 0, indent: 1, sym: s.sym,
                           ownVals: [], ownTypes: [], endCtx: .null, ok: true, err: "")
        let gen = plainFunctionDirect(start, node)
        if !gen.ok { return fail(s, gen.err) }
        var r = s
        for i in 0..<gen.lines.len { r = addLine(r, gen.lines[i]) }
        return r
    }

    // MARK: 접근.hmje

    // 정본: HMIR접근문맥설정
    func accessContext(_ s: HState, _ node: J) -> HState {
        var r = symAdd(s, "@접근파일", astStrField(node, "source_path"))
        r = symAdd(r, "@접근주인", astStrField(node, "access_owner"))
        r = symAdd(r, "@접근가져옴", astStrField(node, "access_imports"))
        return r
    }

    // 정본: HMIR접근정의허용
    func accessAllowed(_ def: J, _ s: HState) -> Bool {
        astModuleDefAllowed(def, symType(s, "@접근파일"), symType(s, "@접근주인"), symType(s, "@접근가져옴"))
    }

    // 정본: HMIR접근서명정의
    func accessSignatureDef(_ name: BStr, _ types: [BStr], _ retType: BStr, _ s: HState) -> J {
        let cands = funcOverloads(name)
        var rejected: J = .null
        for cand in cands.arrayValue {
            let params = astField(cand, "params").arrayValue
            var match = params.count == types.count
            var i = 0
            while i < types.count && match {
                match = typeDisplay(astStrField(params[i], "type_name")) == typeDisplay(types[i])
                i += 1
            }
            var cr = typeResolve(astStrField(cand, "return_type"))
            if cr == "" { cr = "void" }
            if retType != "" && typeDisplay(cr) != typeDisplay(retType) { match = false }
            if match {
                if accessAllowed(cand, s) { return cand }
                rejected = cand
            }
        }
        return rejected
    }

    // 정본: HMIR접근코드이름
    func accessCodeName(_ def: J) -> BStr {
        let n = astStrField(def, "emit_name")
        if n != "" { return n }
        return astStrField(def, "name")
    }

    // 정본: HMIR접근동명모호한가
    func accessAmbiguous(_ def: J, _ s: HState) -> Bool {
        let cands = funcOverloads(astStrField(def, "name"))
        let params = astField(def, "params").arrayValue
        for cand in cands.arrayValue {
            if accessCodeName(cand) != accessCodeName(def) && accessAllowed(cand, s) {
                let cps = astField(cand, "params").arrayValue
                var same = params.count == cps.count
                var i = 0
                while i < params.count && same {
                    same = typeResolve(astStrField(params[i], "type_name")) == typeResolve(astStrField(cps[i], "type_name"))
                    i += 1
                }
                if same { return true }
            }
        }
        return false
    }
}
