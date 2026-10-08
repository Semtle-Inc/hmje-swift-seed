// 정본: 프론트엔드/모듈접근.hmje 중 준비 단계가 쓰는 부분(색인 만들기·접근 허용).
// 접근 **검사**(모듈접근검사)는 올바른 입력에서 문서를 바꾸지 않으므로 옮기지 않는다.

struct AccessIndex {
    var fileOwners: [BStr: BStr] = [:]
    var fileImports: [BStr: BStr] = [:]
    var nameHeads: [BStr: Int] = [:]
    var decls: [J] = []
    var nexts: [Int] = []
}

enum ModuleAccess {
    // 정본: 모듈접근가시성
    static func visibility(_ node: J) -> BStr {
        let v = astField(node, "visibility")
        if case .string(let s) = v { return s }
        return objField(v, "value").stringValue
    }

    // 정본: 모듈접근색인만들기
    static func makeIndex(_ loader: ModuleLoader, _ stmts: [J], _ names: [BStr], _ paths: [BStr], _ mapPath: BStr) -> AccessIndex {
        let fs = loader.fs
        var idx = AccessIndex()
        var moduleAllows: [BStr: BStr] = [:]
        var implicitOwners: BStr = "\n"
        var libRoot: BStr = ""
        let defaultProject = realPathOrNormalize(mapPath)
        var i = 0
        while i < names.count && i < paths.count {
            let path = realPathOrNormalize(paths[i])
            let body = fs.read(path)
            let project = StandardLoad.accessProject(body, defaultProject)
            let owner = project + "\t" + names[i]
            idx.fileOwners[path] = owner
            if body.find("# @hmje-implicit-module\n") != nil {
                implicitOwners = implicitOwners + owner + "\n"
                if names[i] == "표준" { libRoot = project }
            }
            if body.find("# @hmje-allowed-imports\n") != nil {
                var allow: BStr = "\n"
                let prefix = BStr("# @hmje-allowed-import ")
                for line in body.splitFast("\n") where line.hasPrefix(prefix) {
                    allow = allow + line.sub(prefix.count, line.count - prefix.count) + "\n"
                }
                moduleAllows[owner] = allow
            }
            var sources = listHMJESources(path)
            if body.hasPrefix("# @hmje-project ") { sources = ModuleLoader.importList(body) }
            for s in sources {
                let src = realPathOrNormalize(s)
                let prev = idx.fileOwners[src] ?? ""
                if prev.count > 0 && prev != owner { prepFail("파일이 여러 모듈에 속합니다: " + src.string) }
                idx.fileOwners[src] = owner
            }
            i += 1
        }
        var originStmts = stmts
        for st in stmts {
            let node = lineNode(st)
            if astKind(node) == "FunctionDef" && astStrField(node, "name") == "__hmje_script_entry" {
                originStmts.append(contentsOf: astField(node, "body").arrayValue)
            }
        }
        for st in originStmts {
            let file = astStrField(lineNode(st), "source_path")
            if file != "" && (idx.fileImports[file] ?? "") == "" {
                let useOwner = idx.fileOwners[file] ?? ""
                let allow = moduleAllows[useOwner] ?? ""
                var direct = implicitOwners
                for imp in ModuleLoader.importList(fs.read(file)) {
                    if imp.hasPrefix("@module:") {
                        let name = imp.sub(8, imp.count - 8)
                        let key = "\n" + name + "\n"
                        if allow != "" && allow.find(key) == nil {
                            prepFail("모듈 접근 거부: 선언되지 않은 의존 모듈 " + name.string + "; 사용 " + file.string)
                        }
                        let target = ModuleLoader.moduleNamePath(name, names, paths)
                        let targetOwner = idx.fileOwners[realPathOrNormalize(target)] ?? ""
                        if targetOwner != "" { direct = direct + targetOwner + "\n" }
                    } else {
                        let target = realPathOrNormalize(loader.importPath(file, imp, libRoot, "", names, paths))
                        let targetOwner = idx.fileOwners[target] ?? ""
                        if allow != "" && targetOwner != "" && targetOwner != useOwner {
                            prepFail("모듈 접근 거부: 프로젝트 파일 가져오기는 현재 모듈 경계를 벗어날 수 없습니다; 사용 " + file.string)
                        }
                        direct = direct + "@file:" + target + "\n"
                    }
                }
                idx.fileImports[file] = direct
            }
        }
        for st in stmts {
            let node = lineNode(st)
            let kind = astKind(node)
            if kind == "FunctionDef" || kind == "GlobalDefine" || kind == "ExternalGlobal" || kind == "StructDef" || kind == "EnumDef" || kind == "TraitDef" {
                let name = astStrField(node, "name")
                idx.nexts.append(idx.nameHeads[name] ?? 0)
                idx.decls.append(node)
                idx.nameHeads[name] = idx.decls.count
            }
        }
        return idx
    }

    // 정본: 모듈접근허용
    static func allowed(_ decl: J, _ useFile: BStr, _ idx: AccessIndex) -> Bool {
        let declFile = astStrField(decl, "source_path")
        let vis = visibility(decl)
        if vis == "type" { return false }
        if declFile == useFile { return true }
        if vis == "file" { return false }
        let declOwner = idx.fileOwners[declFile] ?? ""
        if declOwner.count == 0 { return true }
        let useOwner = idx.fileOwners[useFile] ?? ""
        if declOwner == useOwner { return true }
        let direct = idx.fileImports[useFile] ?? ""
        let importKey = "\n" + declOwner + "\n"
        let fileKey = "\n@file:" + declFile + "\n"
        if direct.find(importKey) == nil && direct.find(fileKey) == nil { return false }
        if vis == "public" { return true }
        if vis == "project" && useOwner.count > 0 {
            let d = declOwner.splitFast("\t"), u = useOwner.splitFast("\t")
            return d[0] == u[0]
        }
        return false
    }
}
