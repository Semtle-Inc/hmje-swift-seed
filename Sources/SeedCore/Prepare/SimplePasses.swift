// 문서를 거의 바꾸지 않거나 단순히 다시 쓰는 준비 패스들.

enum SimplePasses {
    // 정본: 모듀이름문서낮추기 (충돌이 없으면 그대로). 충돌 갈래는 네 도구에 없다.
    static func moduleNameLower(_ stmts: [J], _ idx: AccessIndex) -> [J] {
        var conflicts: Set<BStr> = []
        for decl in idx.decls {
            let name = astStrField(decl, "name")
            let owner = idx.fileOwners[astStrField(decl, "source_path")] ?? ""
            if astKind(decl) != "FunctionDef" && owner != "" && !conflicts.contains(name) {
                var k = idx.nameHeads[name] ?? 0
                while k > 0 {
                    let cand = idx.decls[k - 1]
                    let co = idx.fileOwners[astStrField(cand, "source_path")] ?? ""
                    if astKind(cand) != "FunctionDef" && co != "" && co != owner { conflicts.insert(name); break }
                    k = idx.nexts[k - 1]
                }
            }
        }
        if conflicts.isEmpty { return stmts }
        fatalError("미이식: 모듀이름문서낮추기(모듈 간 이름 충돌 \(conflicts))")
    }

    // 정본: 파일이름문서낮추기 (file 가시성 선언이 없으면 그대로)
    static func fileNameLower(_ stmts: [J]) -> [J] {
        for s in stmts where ModuleAccess.visibility(lineNode(s)) == "file" {
            fatalError("미이식: 파일이름문서낮추기(file 가시성)")
        }
        return stmts
    }

    // 정본: 명목초기화문서낮추기 (명시 초기화가 있는 구조체가 없으면 그대로)
    static func nominalInitLower(_ stmts: [J]) -> [J] {
        for s in stmts {
            let n = lineNode(s)
            if astKind(n) == "StructDef" && astField(n, "initializers").arrayValue.count > 0 {
                fatalError("미이식: 명목초기화문서낮추기(초기화 선언)")
            }
        }
        return stmts
    }

    // 정본: 컴파일러파일데이터해결 (자원 지도 물리 경로 치환, 고정배열 길이 확정)
    static func fileDataResolve(_ v: J, _ map: ([BStr], [BStr]), _ roots: [BStr], _ fs: PrepFS) -> J {
        switch v {
        case .array(let a): return .array(a.map { fileDataResolve($0, map, roots, fs) })
        case .object(let ks, let vs):
            if astKind(v) == "FileDataExpr" {
                let logical = astStrField(v, "path")
                for i in 0..<map.0.count where map.0[i] == logical {
                    let phys = map.1[i]
                    if phys.count > 0 { return nodeReplace(v, "path", jstr(phys)) }
                    break
                }
                return v
            }
            let r = J.object(keys: ks, values: vs.map { fileDataResolve($0, map, roots, fs) })
            if astKind(r) == "GlobalDefine" && astKind(astField(r, "expr")) == "FileDataExpr" && astStrField(r, "type_name") == "자연수8의 고정배열" {
                fatalError("미이식: 컴파일러파일데이터길이")
            }
            return r
        default: return v
        }
    }

    // 정본: 컴파일러자원지도읽기
    static func readResourceMap(_ fs: PrepFS, _ path: BStr) -> ([BStr], [BStr]) {
        var logical: [BStr] = [], phys: [BStr] = []
        if path.count == 0 { return (logical, phys) }
        for line in fs.read(path).splitFast("\n") {
            let p = line.splitFast("\t")
            if p.count == 3 && p[0] == "resource" { phys.append(p[1]); logical.append(p[2]) }
        }
        return (logical, phys)
    }

    // 정본: UI불투명JSON낮추기
    static func opaqueUILower(_ v: J) -> J {
        switch v {
        case .array(let a): return .array(a.map(opaqueUILower))
        case .object(let ks, let vs):
            var r = J.object(keys: ks, values: vs.map(opaqueUILower))
            let k = astKind(r)
            if k == "FunctionDef" {
                if astField(r, "return_type") == .string("화면") { r = nodeReplace(r, "return_type", jstr("화면노드")) }
            } else if k == "Return" {
                if astField(r, "type_name") == .string("화면") { r = nodeReplace(r, "type_name", jstr("화면노드")) }
            }
            return r
        default: return v
        }
    }

    // 정본: 표면문서검증. 네 도구에는 표면 노드가 없다(라우트·DB·화면 낮추기는 비어 있다).
    static func surfaceValidate(_ doc: J) -> J {
        let stmts = objField(doc, "statements").arrayValue
        var out: [J] = []
        out.reserveCapacity(stmts.count)
        for s in stmts {
            let k = astKind(lineNode(s))
            if k.hasPrefix("Surface") || k == "BlockModifierDef" { fatalError("미이식: 표면문서검증(\(k))") }
            out.append(opaqueUILower(s))
        }
        return objReplace(doc, "statements", .array(out))
    }

    // 정본: 모듈출처문서붙이기
    static func attachOrigin(_ doc: J, _ idx: AccessIndex) -> J {
        let stmts = objField(doc, "statements").arrayValue
        var out: [J] = []
        out.reserveCapacity(stmts.count)
        for st in stmts {
            var node = lineNode(st)
            let file = astStrField(node, "source_path")
            let owner = idx.fileOwners[file] ?? ""
            if file != "" {
                node = nodeReplace(node, "access_owner", jstr(owner))
                node = nodeReplace(node, "access_imports", jstr(idx.fileImports[file] ?? ""))
                let name = astStrField(node, "name")
                if owner != "" && astKind(node) == "FunctionDef" && astField(node, "external_name").isNull {
                    var k = idx.nameHeads[name] ?? 0
                    var conflict = false
                    while k > 0 {
                        let cand = idx.decls[k - 1]
                        let co = idx.fileOwners[astStrField(cand, "source_path")] ?? ""
                        if astKind(cand) == "FunctionDef" && co != "" && co != owner { conflict = true }
                        k = idx.nexts[k - 1]
                    }
                    if conflict { fatalError("미이식: 모듈출처문서붙이기(emit_name 충돌 \(name))") }
                }
            }
            if astKind(node) == "FunctionDef" && astStrField(node, "name") == "__hmje_script_entry" {
                fatalError("미이식: 모듈출처문서붙이기(스크립트 진입)")
            }
            out.append(jarr([st.arrayValue[0], node]))
        }
        return objReplace(doc, "statements", .array(out))
    }

    // 정본: 준비열거변환문서낮추기
    static func enumCastLower(_ doc: J) -> J {
        guard let stmts = doc.field("statements") else { return doc }
        var names: [BStr] = []
        for s in stmts.arrayValue {
            let n = s.arrayValue.count > 1 ? s.arrayValue[1] : J.null
            if astKind(n) == "EnumDef" {
                let name = astStrField(n, "name")
                if name.count > 0 && !names.contains(name) { names.append(name) }
            }
        }
        if names.isEmpty { return doc }
        let set = Set(names)
        func walk(_ v: J) -> J {
            switch v {
            case .array(let a): return .array(a.map(walk))
            case .object(let ks, let vs):
                let r = J.object(keys: ks, values: vs.map(walk))
                if astKind(r) == "CallExpr" {
                    let name = astStrField(r, "name")
                    let args = astField(r, "args").arrayValue
                    if set.contains(name) && args.count == 1 {
                        return astNode("CastExpr", ["type_name", "expr", "compiler_generated"], [jstr(name), args[0], jbool(false)])
                    }
                }
                return r
            default: return v
            }
        }
        return objReplace(doc, "statements", walk(stmts))
    }

    // 정본: 구조체갱신문서낮추기
    static func structUpdateLower(_ doc: J) -> J {
        guard let stmts = doc.field("statements") else { return doc }
        var declNames: [BStr] = [], declFields: [J] = []
        for ls in stmts.arrayValue {
            if case .array(let a) = ls, a.count == 2, astKind(a[1]) == "StructDef" {
                declNames.append(astStrField(a[1], "name")); declFields.append(astField(a[1], "fields"))
            }
        }
        let decls = jobj(declNames, declFields)
        func walk(_ v: J) -> J {
            switch v {
            case .array(let a): return .array(a.map(walk))
            case .object(let ks, let vs):
                var r = J.object(keys: ks, values: vs.map(walk))
                if astKind(r) != "StructInitExpr" || astField(r, "base").isNull { return r }
                guard let df = decls.field(astStrField(r, "name")) else { return r }
                let written = astField(r, "fields")
                let base = astField(r, "base")
                var ck: [BStr] = [], cv: [J] = []
                for f in df.objectKeys {
                    ck.append(f)
                    if let w = written.field(f) { cv.append(w) } else {
                        cv.append(astNode("FieldAccessExpr", ["base", "field"], [base, jstr(f)]))
                    }
                }
                r = nodeReplace(r, "fields", jobj(ck, cv))
                return nodeReplace(r, "base", .null)
            default: return v
            }
        }
        return objReplace(doc, "statements", walk(stmts))
    }
}
