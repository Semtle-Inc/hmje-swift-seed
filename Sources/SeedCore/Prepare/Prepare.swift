// 정본: 컴파일러.hmje 앱시작의 인자 처리부터 두 번째 모듈출처문서붙이기까지.
// 결과는 단계덤프기가 쓰는 준비 문서(`<out>.prepared.json`)와 바이트 동일하다.

public struct PrepareOptions {
    /// 단계별 중간 결과를 받는다(개발용). 이름은 p00(적재)…p16(최종).
    public var onStage: ((String, JSONValue) -> Void)?
    public init(onStage: ((String, JSONValue) -> Void)? = nil) { self.onStage = onStage }
}

/// 정본 컴파일러모듈지도읽기
func readModuleMap(_ fs: PrepFS, _ path: BStr) -> ([BStr], [BStr]) {
    var names: [BStr] = [], paths: [BStr] = []
    if path.count == 0 { return (names, paths) }
    for raw in fs.read(path).splitFast("\n") {
        let line = raw.trimmed()
        if let tab = line.find("\t") {
            if tab > 0 && tab + 1 < line.count {
                names.append(line.sub(0, tab))
                paths.append(line.sub(tab + 1, line.count - (tab + 1)))
            }
        }
    }
    return (names, paths)
}

/// `args`: 실제 프론트엔드와 같은 인자(실행본 이름 제외):
/// `<entry.hmje> <library-root> <platform> <기본동적배열.hmje> <out.hmir> [옵션...]`.
public func prepareDocument(args rawArgs: [String], options: PrepareOptions = PrepareOptions()) -> JSONValue {
    let args = ["hmje-seed"] + rawArgs.map { BStr($0) }
    if args.count < 6 { prepFail("쓰임: prepare <source.hmje> <library-root> <platform> <기본동적배열.hmje> <출력.hmir> [옵션]") }
    let platform = args[3]
    if !(platform == "darwin" || platform == "linux") { fatalError("미이식: 앱시작(플랫폼 \(platform))") }
    var mapPath: BStr = "", nativePlan: BStr = "", osRoot: BStr = ""
    var i = 6
    while i < args.count {
        let a = args[i]
        if a == "--계측" || a == "--캐시끄기" || a == "--함수캐시검사" || a == "--파싱캐시검사" {
            // 계측·캐시는 결과 문서에 영향을 주지 않는다.
        } else if a == "--dump-deps" {
            fatalError("미이식: 앱시작(--dump-deps)")
        } else if a == "--module-map" {
            if i + 1 >= args.count { prepFail("--module-map에 값이 필요합니다") }
            mapPath = args[i + 1]; i += 1
        } else if a == "--native-plan" {
            if i + 1 >= args.count { prepFail("--native-plan에 값이 필요합니다") }
            nativePlan = args[i + 1]; i += 1
        } else if a == "--os-root" {
            if i + 1 >= args.count { prepFail("--os-root에 값이 필요합니다") }
            osRoot = args[i + 1]; i += 1
        } else if a == "--전개보기" || a == "--trace-prepared-symbol" {
            fatalError("미이식: 앱시작(\(a))")
        }
        i += 1
    }
    let fs = PrepFS()
    var (names, paths) = readModuleMap(fs, mapPath)
    if StandardLoad.autoProvided(platform, args[1], osRoot) {
        (names, paths) = StandardLoad.augmentMap(fs, args[2], platform, names, paths)
    }
    if mapPath == "" { fatalError("미이식: 단일소스모듈지도보강") }
    let loader = ModuleLoader(fs: fs, names: names, paths: paths)
    let load = loader.loadPosix(args[1], args[2], platform)
    if !load.ok { prepFail(load.error.string) }
    var stmts = load.stmts
    options.onStage?("p00", .array(stmts))
    let dynSource = fs.read(args[4])
    if dynSource.count == 0 { prepFail("기본 동적배열 소스를 읽을 수 없습니다") }

    let stage = options.onStage
    var idx = ModuleAccess.makeIndex(loader, stmts, names, paths, mapPath)
    stmts = SimplePasses.moduleNameLower(stmts, idx)
    stage?("p01", .array(stmts))
    stmts = SimplePasses.fileNameLower(stmts)
    stage?("p02", .array(stmts))
    stmts = SimplePasses.nominalInitLower(stmts)
    stage?("p03", .array(stmts))
    let resMap = SimplePasses.readResourceMap(fs, nativePlan)
    let absLib = realPathOrNormalize(args[2])
    let toolRoot = parentPath(absLib)
    var resRoots: [BStr] = [absLib, toolRoot + "/compiler", toolRoot + "/platforms"]
    if osRoot.count > 0 { resRoots = [realPathOrNormalize(osRoot)] + resRoots }
    let ui = ModuleLoader.uiRoot()
    if ui.count > 0 { resRoots.append(ui); resRoots.append(ui + "/assets") }
    let resolved = SimplePasses.fileDataResolve(.array(stmts), resMap, resRoots, fs)
    stage?("p04", resolved)
    var doc = jobj(["format", "statements"], [jstr("hmje-parsed-ast-v1"), resolved])
    doc = SimplePasses.surfaceValidate(doc)
    stage?("p05", doc)
    doc = Container.lowerArrayLiterals(doc)
    stage?("p06", doc)
    if Guards.hasKind(objField(doc, "statements"), ["FilterDefine", "MapDefine", "SortDefine"]) { fatalError("미이식: 준비배열파이프라인문서낮추기") }
    stage?("p07", doc)
    idx = ModuleAccess.makeIndex(loader, stmts, names, paths, mapPath)
    doc = SimplePasses.attachOrigin(doc, idx)
    stage?("p08", doc)
    doc = Generic.basicCleanup(doc)
    stage?("p09", doc)
    if Guards.hasKindPrefix(objField(doc, "statements"), "Channel") { fatalError("미이식: 준비채널문서낮추기") }
    stage?("p10", doc)
    doc = Container.injectOptionals(doc)
    stage?("p11", doc)
    doc = Container.injectDynamicArrays(doc, dynSource)
    stage?("p12", doc)
    doc = SimplePasses.structUpdateLower(doc)
    stage?("p13", doc)
    if Guards.hasKind(objField(doc, "statements"), ["FunctionValueDefine"]) { fatalError("미이식: 준비클로저문서낮추기") }
    doc = objReplace(doc, "format", jstr("hmje-prepared-ast-v1"))
    stage?("p14", doc)
    doc = SimplePasses.enumCastLower(doc)
    stage?("p15", doc)
    doc = SimplePasses.attachOrigin(doc, idx)
    stage?("p16", doc)
    return doc
}

enum Guards {
    static func hasKind(_ v: J, _ kinds: Set<BStr>) -> Bool {
        switch v {
        case .array(let a): return a.contains { hasKind($0, kinds) }
        case .object(_, let vs):
            if kinds.contains(astKind(v)) { return true }
            return vs.contains { hasKind($0, kinds) }
        default: return false
        }
    }
    static func hasKindPrefix(_ v: J, _ prefix: BStr) -> Bool {
        switch v {
        case .array(let a): return a.contains { hasKindPrefix($0, prefix) }
        case .object(_, let vs):
            if astKind(v).hasPrefix(prefix) { return true }
            return vs.contains { hasKindPrefix($0, prefix) }
        default: return false
        }
    }
}
