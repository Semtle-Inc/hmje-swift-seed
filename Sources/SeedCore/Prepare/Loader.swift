// 정본: 프론트엔드/모듈적재.hmje, 프론트엔드/포직스적재.hmje, 프론트엔드/표준적재.hmje (darwin 갈래).

struct LoadResult {
    var ok: Bool
    var stmts: [J]
    var readPaths: [BStr]
    var nextLine: Int
    var error: BStr
}

final class ModuleLoader {
    let fs: PrepFS
    var names: [BStr]
    var paths: [BStr]

    init(fs: PrepFS, names: [BStr], paths: [BStr]) {
        self.fs = fs
        self.names = names
        self.paths = paths
    }

    // 정본: 모듈적재실패
    func failure(_ read: [BStr], _ next: Int, _ err: BStr) -> LoadResult {
        LoadResult(ok: false, stmts: [], readPaths: read, nextLine: next, error: err)
    }

    // 정본: 모듀이름경로
    static func moduleNamePath(_ name: BStr, _ names: [BStr], _ paths: [BStr]) -> BStr {
        var i = 0
        while i < names.count && i < paths.count {
            if names[i] == name { return paths[i] }
            i += 1
        }
        return ""
    }

    // 정본: 모듈뿌리안상대경로
    static func relUnderRoot(_ root: BStr, _ path: BStr) -> BStr {
        if root.count == 0 { return "밖" }
        if path == root { return "" }
        let prefix = root + "/"
        if !path.hasPrefix(prefix) { return "밖" }
        return path.sub(prefix.count, path.count - prefix.count)
    }

    // 정본: 모듈겹침후보있나
    func overlayCandidateExists(_ root: BStr, _ rel: BStr) -> Bool {
        if root.count == 0 { return false }
        return fs.read(normalizePath(root + "/" + rel)).count > 0
    }

    // 정본: 모듈UI뿌리
    static func uiRoot() -> BStr { envVar("HMJE_UI_ROOT") ?? "" }

    // 정본: 모듈oslibUI소유인가
    static func oslibUIOwned(_ rel: BStr) -> Bool {
        if rel.hasPrefix("oslib/ui/") || rel.hasPrefix("oslib/graphics/") || rel.hasPrefix("oslib/font/") { return true }
        return rel == "oslib/hmje_graphics.hmje" || rel == "oslib/image.hmje"
    }

    // 정본: 모듈oslib뿌리후보
    func oslibRootCandidate(_ suffix: BStr, _ libRoot: BStr, _ ui: BStr) -> BStr {
        var first = libRoot, second = ui
        if ModuleLoader.oslibUIOwned(suffix) { first = ui; second = libRoot }
        if overlayCandidateExists(first, suffix) { return normalizePath(first + "/" + suffix) }
        if overlayCandidateExists(second, suffix) { return normalizePath(second + "/" + suffix) }
        return ""
    }

    // 정본: 모듈뿌리겹침경로
    func rootOverlayPath(_ importer: BStr, _ target: BStr, _ libRoot: BStr, _ osRoot: BStr) -> BStr {
        var compilerRoot: BStr = ""
        if libRoot.count > 0 { compilerRoot = parentPath(libRoot) + "/compiler" }
        let parent = parentPath(importer)
        let ui = ModuleLoader.uiRoot()
        let holding: [BStr] = [osRoot, libRoot, ui, compilerRoot]
        let searching: [BStr] = [osRoot, libRoot, ui, osRoot, compilerRoot]
        for h in holding {
            let relParent = ModuleLoader.relUnderRoot(h, parent)
            if relParent != "밖" {
                let rel = normalizePath(relParent + "/" + target)
                if !rel.hasPrefix("..") && !rel.hasPrefix("/") {
                    var owner: BStr = ""
                    if rel.hasPrefix("kernel/api/") {
                        owner = libRoot
                    } else if rel.hasPrefix("stdlib/") || rel.hasPrefix("runtime/") || rel.hasPrefix("applib/") || rel.hasPrefix("oslib/") {
                        owner = libRoot
                    } else if rel.hasPrefix("kernel/") || rel.hasPrefix("runtimes/") || rel.hasPrefix("apps/") {
                        owner = osRoot
                    }
                    if ModuleLoader.oslibUIOwned(rel) { owner = ui }
                    if overlayCandidateExists(owner, rel) { return normalizePath(owner + "/" + rel) }
                    for s in searching where overlayCandidateExists(s, rel) { return normalizePath(s + "/" + rel) }
                }
            }
        }
        return ""
    }

    // 정본: 모듈추가뿌리들
    static func extraRoots() -> [BStr] {
        guard let env = envVar("HMJE_IMPORT_ROOTS") else { return [] }
        return env.splitFast(":").filter { $0.count > 0 }.map(normalizePath)
    }

    // 정본: 모듈이름원본경로
    static func moduleNameSourcePath(_ name: BStr, _ libRoot: BStr, _ osRoot: BStr) -> BStr {
        let ui = uiRoot()
        var roots: [BStr] = [libRoot, ui, osRoot]
        roots.append(contentsOf: extraRoots())
        if let net = envVar("HMJE_NETWORK_ROOT") {
            roots.append(net)
        } else if ui.count > 0 {
            roots.append(parentPath(ui) + "/hmje-network")
        }
        for r in roots where r.count > 0 {
            let cand = realPathOrNormalize(r + "/Sources/" + name)
            if listHMJESources(cand).count > 0 { return cand }
        }
        return ""
    }

    // 정본: 모듈가져오기경로
    func importPath(_ importer: BStr, _ target: BStr, _ libRoot: BStr, _ osRoot: BStr, _ names: [BStr], _ paths: [BStr]) -> BStr {
        if target.hasPrefix("@module:") {
            let mod = target.sub(8, target.count - 8)
            if names.count > 0 { return ModuleLoader.moduleNamePath(mod, names, paths) }
            let src = ModuleLoader.moduleNameSourcePath(mod, libRoot, osRoot)
            if src.count == 0 { return "@missing:" + mod }
            if ModuleLoader.relUnderRoot(src, importer) != "밖" { return "@module-self" }
            return "@sources:" + src
        }
        if libRoot.count > 0 && target.hasSuffix("aarch64_io.hmje") {
            return normalizePath(libRoot + "/runtime/platform/aarch64/bare_console.hmje")
        }
        if target.hasPrefix("/") { return normalizePath(target) }
        if libRoot.count > 0 {
            if target.hasPrefix("runtime/") || target.hasPrefix("Sources/") || target.hasPrefix("kernel/") {
                return normalizePath(libRoot + "/" + target)
            }
        }
        let parent = parentPath(importer)
        if parent.count == 0 { return normalizePath(target) }
        let rel = normalizePath(parent + "/" + target)
        if libRoot.count > 0 && fs.read(rel).count == 0 {
            if let mark = target.find("stdlib/") {
                let l = BStr("stdlib/").count
                let suffix = target.sub(mark + l, target.count - mark - l)
                let std = normalizePath(libRoot + "/Sources/표준/" + suffix)
                if fs.read(std).count > 0 { return std }
                let base = normalizePath(libRoot + "/Sources/기반/" + suffix)
                if fs.read(base).count > 0 { return base }
            }
            if let mark = target.find("runtime/user/") {
                let suffix = target.sub(mark, target.count - mark)
                let rt = normalizePath(libRoot + "/" + suffix)
                if fs.read(rt).count > 0 { return rt }
            }
            if let mark = target.find("oslib/") {
                let suffix = target.sub(mark, target.count - mark)
                let os = oslibRootCandidate(suffix, libRoot, ModuleLoader.uiRoot())
                if os.count > 0 { return os }
            }
        }
        if fs.read(rel).count == 0 {
            for r in ModuleLoader.extraRoots() where overlayCandidateExists(r, target) {
                return normalizePath(r + "/" + target)
            }
        }
        if libRoot.count > 0 && target.find("/") == nil {
            if fs.read(rel).count == 0 {
                let std = normalizePath(libRoot + "/Sources/표준/" + target)
                if fs.read(std).count > 0 { return std }
                let base = normalizePath(libRoot + "/Sources/기반/" + target)
                if fs.read(base).count > 0 { return base }
                let rt = normalizePath(libRoot + "/runtime/user/" + target)
                if fs.read(rt).count > 0 { return rt }
            }
        }
        if fs.read(rel).count == 0 {
            let ov = rootOverlayPath(importer, target, libRoot, osRoot)
            if ov.count > 0 { return ov }
        }
        return rel
    }

    // 정본: 모듈소스줄수
    static func lineCount(_ src: BStr) -> Int {
        var n = 1
        src.withBytes { p in for b in p where b == 10 { n += 1 } }
        return n
    }

    // 정본: 모듈가져오기목록
    static func importList(_ src: BStr) -> [BStr] {
        var out: [BStr] = []
        let eulLen = BStr("을 가져온다.").count
        let reulLen = BStr("를 가져온다.").count
        for line in src.splitFast("\n") {
            if line.hasPrefix("\"") && line.hasSuffix("\"를 가져온다.") {
                let rest = line.sub(1, line.count - 1)
                if let q = rest.find("\"") { out.append(rest.sub(0, q)) }
            } else if !line.hasPrefix(" ") {
                var sl = 0
                if line.hasSuffix("을 가져온다.") { sl = eulLen } else if line.hasSuffix("를 가져온다.") { sl = reulLen }
                if sl > 0 && line.count > sl { out.append("@module:" + line.sub(0, line.count - sl)) }
            }
        }
        return out
    }

    // 정본: 모듈적재내부
    func loadInner(_ path: BStr, _ read: [BStr], _ reading: [BStr], _ next: Int, _ libRoot: BStr, _ osRoot: BStr, _ names: [BStr], _ paths: [BStr]) -> LoadResult {
        if path.count == 0 { return failure(read, next, "이름으로 가져온 모듈이 module map에 없습니다") }
        if path.hasPrefix("@missing:") {
            return failure(read, next, "이름으로 가져온 모듈을 찾을 수 없습니다: " + path.sub(9, path.count - 9))
        }
        if path.hasPrefix("@sources:") {
            if read.contains(path) { return LoadResult(ok: true, stmts: [], readPaths: read, nextLine: next, error: "") }
            if reading.contains(path) { return failure(read, next, "순환 모듈 가져오기가 발견됐습니다: " + path) }
            let src = path.sub(9, path.count - 9)
            var result = LoadResult(ok: true, stmts: [], readPaths: read, nextLine: next, error: "")
            let modReading = reading + [path]
            for s in listHMJESources(src) {
                let r = loadInner(s, result.readPaths, modReading, result.nextLine, libRoot, osRoot, names, paths)
                if !r.ok { return r }
                result = LoadResult(ok: true, stmts: result.stmts + r.stmts, readPaths: r.readPaths, nextLine: r.nextLine, error: "")
            }
            return result
        }
        let norm = normalizePath(path)
        if read.contains(norm) { return LoadResult(ok: true, stmts: [], readPaths: read, nextLine: next, error: "") }
        if reading.contains(norm) { return failure(read, next, "순환 가져오기가 발견됐습니다: " + norm) }
        let src = fs.read(norm)
        if src.count == 0 { return failure(read, next, "파일을 찾거나 읽을 수 없습니다: " + norm) }
        let imports = ModuleLoader.importList(src)
        var merged: [J] = []
        var done = read
        var line = next
        let nowReading = reading + [norm]
        for imp in imports {
            let dep = importPath(norm, imp, libRoot, osRoot, names, paths)
            if dep != "@module-self" {
                let r = loadInner(dep, done, nowReading, line, libRoot, osRoot, names, paths)
                if !r.ok { return r }
                merged.append(contentsOf: r.stmts)
                done = r.readPaths
                line = r.nextLine
            }
        }
        let bodyStart = line
        line += ModuleLoader.lineCount(src)
        // 파서 환경: 의존 모듈 문장들. 씨앗 파서가 환경에서 읽는 것은 Define의 이름·타입뿐이다.
        var env: [LineStmt] = []
        for st in merged {
            let n = lineNode(st)
            if astKind(n) == "Define" {
                var fields: [(String, ASTValue)] = [("name", .str(astStrField(n, "name")))]
                if case .string(let t) = astField(n, "type_name") { fields.append(("type_name", .str(t))) }
                env.append(LineStmt(0, ASTNode("Define", fields)))
            }
        }
        let parsed = parseSource(bytes: src.bytes, startLine: bodyStart, env: env)
        if !parsed.ok {
            return failure(done, line, norm + " (모듈 시작 " + BStr(decimal: bodyStart) + "): " + BStr(parsed.error))
        }
        let origin = realPathOrNormalize(norm)
        for st in parsed.statements {
            if st.node.kind == "Import" || st.node.kind == "ModuleImport" { continue }
            let node = nodeReplace(jsonFromNode(st.node), "source_path", jstr(origin))
            merged.append(jarr([intTag(st.line), node]))
        }
        done = done + [norm]
        return LoadResult(ok: true, stmts: merged, readPaths: done, nextLine: line, error: "")
    }

    // 정본: 포직스모듈하나적재뿌리
    func loadOne(_ path: BStr, _ acc: [J], _ read: [BStr], _ next: Int, _ libRoot: BStr, _ osRoot: BStr) -> LoadResult {
        let r = loadInner(path, read, [], next, libRoot, osRoot, names, paths)
        if !r.ok { return r }
        return LoadResult(ok: true, stmts: acc + r.stmts, readPaths: r.readPaths, nextLine: r.nextLine, error: "")
    }

    // 정본: 포직스채널문법있는가
    static func hasChannelSyntax(_ v: J) -> Bool {
        switch v {
        case .object(_, let vs):
            if astKind(v).hasPrefix("Channel") { return true }
            for x in vs where hasChannelSyntax(x) { return true }
            return false
        case .array(let a):
            for x in a where hasChannelSyntax(x) { return true }
            return false
        default: return false
        }
    }

    // 정본: 포직스진입종류
    func entryKind(_ path: BStr) -> BStr {
        let src = fs.read(path)
        if src.count == 0 { return "오류" }
        let marker = BStr("# @hmje-entry ")
        for line in src.splitFast("\n") {
            if line.hasPrefix(marker) {
                let k = line.sub(marker.count, line.count - marker.count)
                if k == "기본" || k == "인자" || k == "비동기" { return k }
            }
            if !line.hasPrefix(" ") && line.find("함수 앱시작은") != nil {
                if line.hasPrefix("비동기") { return "비동기" }
                if line.find("(") != nil { return "인자" }
                return "기본"
            }
        }
        return "스크립트"
    }

    // 정본: 모듈출처진입연결
    static func markEntry(_ v: J) -> J {
        switch v {
        case .array(let a): return .array(a.map(markEntry))
        case .object(let ks, let vs):
            let k = astKind(v)
            if (k == "Execute" || k == "CallExpr") && astStrField(v, "name") == "앱시작" {
                return nodeReplace(v, "compiler_generated", jbool(true))
            }
            return .object(keys: ks, values: vs.map(markEntry))
        default: return v
        }
    }

    // 정본: 표준프렐류드경로
    func preludePath(_ libRoot: BStr) -> BStr {
        let p = ModuleLoader.moduleNamePath("표준", names, paths)
        if p.count > 0 { return p }
        return libRoot + "/Sources/표준/io.hmje"
    }

    // 정본: 포직스소스적재지도
    func loadPosix(_ source: BStr, _ library: BStr, _ platform: BStr) -> LoadResult {
        let absSource = realPathOrNormalize(source)
        let absLib = realPathOrNormalize(library)
        var r = LoadResult(ok: true, stmts: [], readPaths: [], nextLine: 1, error: "")
        r = loadOne(preludePath(absLib), r.stmts, r.readPaths, r.nextLine, absLib, "")
        if !r.ok { return r }
        r = loadOne(absLib + "/Sources/기반/input.hmje", r.stmts, r.readPaths, r.nextLine, absLib, "")
        if !r.ok { return r }
        r = loadOne(absLib + "/runtime/platform/posix/file_backend.hmje", r.stmts, r.readPaths, r.nextLine, absLib, "")
        if !r.ok { return r }
        var layout: BStr = "/runtime/platform/linux/file_layout.hmje"
        if platform == "darwin" || platform == "ios" { layout = "/runtime/platform/darwin/file_layout.hmje" }
        if platform == "android" { layout = "/runtime/platform/android/file_layout.hmje" }
        r = loadOne(absLib + layout, r.stmts, r.readPaths, r.nextLine, absLib, "")
        if !r.ok { return r }
        return loadAppBody(r, absSource, absLib, "")
    }

    // 정본: 포직스앱본문적재
    func loadAppBody(_ prev: LoadResult, _ absSource: BStr, _ absLib: BStr, _ osRoot: BStr) -> LoadResult {
        var r = prev
        let kind = entryKind(absSource)
        if kind == "오류" { return failure(r.readPaths, r.nextLine, "앱 진입점을 파싱할 수 없습니다") }
        if kind == "기본" || kind == "인자" {
            let entryPath: BStr = kind == "인자" ? "/runtime/user/app_start_args.hmje" : "/runtime/user/app_start.hmje"
            let before = r.stmts.count
            r = loadOne(absLib + entryPath, r.stmts, r.readPaths, r.nextLine, absLib, osRoot)
            if !r.ok { return r }
            let entryReal = realPathOrNormalize(absLib + entryPath)
            var i = before
            while i < r.stmts.count {
                if astStrField(lineNode(r.stmts[i]), "source_path") == entryReal {
                    r.stmts[i] = ModuleLoader.markEntry(r.stmts[i])
                }
                i += 1
            }
        }
        var fin = loadOne(absSource, r.stmts, r.readPaths, r.nextLine, absLib, osRoot)
        if !fin.ok { return fin }
        if ModuleLoader.hasChannelSyntax(.array(fin.stmts)) {
            fin = loadOne(absLib + "/Sources/기반/channel_runtime.hmje", fin.stmts, fin.readPaths, fin.nextLine, absLib, osRoot)
            if !fin.ok { return fin }
            fin = loadOne(absLib + "/Sources/기반/arc_transfer_runtime.hmje", fin.stmts, fin.readPaths, fin.nextLine, absLib, osRoot)
            if !fin.ok { return fin }
        }
        if kind == "스크립트" { fatalError("미이식: 포직스앱본문적재(스크립트 진입)") }
        if kind != "비동기" { return fin }
        fatalError("미이식: 포직스앱본문적재(비동기 진입)")
    }
}

// MARK: - 표준적재.hmje

enum StandardLoad {
    // 정본: 표준자동제공인가
    static func autoProvided(_ platform: BStr, _ source: BStr, _ osRoot: BStr) -> Bool {
        if platform == "limine-x86_64" || platform == "bare-aarch64" || platform == "limine-aarch64" || platform == "limine-min-aarch64" || platform == "app-min-aarch64" { return false }
        if platform == "bare-x86_64" && osRoot.count > 0 { fatalError("미이식: 자유x86맨프렐류드싣나") }
        return true
    }

    // 정본: 표준선택플랫폼
    static func selectPlatform(_ p: BStr) -> BStr {
        switch p {
        case "darwin": return "macOS"
        case "linux": return "Linux"
        case "windows": return "Windows"
        case "ios": return "iOS"
        case "android": return "Android"
        default: return "semtleOS"
        }
    }

    // 정본: 모듈접근프로젝트
    static func accessProject(_ src: BStr, _ fallback: BStr) -> BStr {
        let prefix = BStr("# @hmje-project ")
        if src.hasPrefix(prefix), let e = src.find("\n") { return src.sub(prefix.count, e - prefix.count) }
        return fallback
    }

    // 정본: 표준모듈집계 + 자동모듈집계게시(가상 파일로)
    static func aggregate(_ fs: PrepFS, _ root: BStr, _ doc: ProjectDoc, _ name: BStr, _ platform: BStr, _ implicit: Bool) -> BStr {
        let sources = Project.moduleSources(root, doc, name, selectPlatform(platform))
        if sources.count == 0 { prepFail("표준 라이브러리 모듈 원본이 없습니다: " + name.string) }
        var body = "# @hmje-project " + root + "\n"
        if implicit { body = body + "# @hmje-implicit-module\n" }
        for s in sources {
            if s.find("\"") != nil { prepFail("따옴표가 든 표준 원본 경로는 지원하지 않습니다") }
            body = body + "\"" + s + "\"를 가져온다.\n"
        }
        let path = "/@hmje-seed-implicit-modules" + root + "/" + name + ".hmje"
        fs.virtual[path] = body
        return path
    }

    // 정본: 표준모듈지도보강
    static func augmentMap(_ fs: PrepFS, _ libRoot: BStr, _ platform: BStr, _ names0: [BStr], _ paths0: [BStr]) -> ([BStr], [BStr]) {
        let root = realPathOrNormalize(libRoot)
        let doc = Project.parse(fs.read(root + "/Project.hmjep"))
        let plan = Project.plan(doc, "표준")
        if !plan.ok || !plan.rootModules.contains("표준") {
            prepFail("library/Project.hmjep에 표준 라이브러리와 표준 모듈 선언이 필요합니다")
        }
        var names = names0, paths = paths0
        var reg: [BStr] = ["표준"]
        if plan.moduleNames.contains("기반") { reg.append("기반") }
        for name in reg {
            let path = aggregate(fs, root, doc, name, platform, name == "표준")
            var found = false
            for i in 0..<names.count where names[i] == name {
                let owner = accessProject(fs.read(paths[i]), "")
                if owner != root { prepFail("표준 라이브러리와 다른 프로젝트가 같은 모듈 이름을 씁니다: " + name.string) }
                paths[i] = path
                found = true
            }
            if !found { names.append(name); paths.append(path) }
        }
        return (names, paths)
    }
}
