import Foundation

// 정본: 프로젝트조정기.hmje 앱시작의 계획 생성 구간(진입 파일·모듈 집계·모듈 지도·네이티브 계획).
// 컴파일러 호출(포직스프로세스실행)은 옮기지 않는다 — 씨앗은 계획만 만들고 finishpoint가 컴파일한다.
// 트로이목마 조정기가 파일 목록을 바꾸면 DDC 두 경로가 같은 잘못된 목록을 컴파일하므로,
// 이 계획은 stage0 산출물 없이 Project.hmjep와 파일 시스템에서 직접 만든다.

public struct CoordinatorPlan {
    public var entryPath: String
    public var mapPath: String
    public var nativePath: String
    /// 정본 컴파일인자들 중 프론트엔드로 넘어가는 옵션(인자들[8…]의 --define 외).
    public var extraOptions: [String]
}

public enum CoordinatorError: Error, CustomStringConvertible {
    case failed(String, Int32)
    public var description: String {
        switch self { case .failed(let m, _): return m }
    }
}

enum Coordinator {
    static let knownFeatures: [BStr] = ["네트워크", "오디오 입력", "위치", "카메라"]

    // 정본: 프로젝트조정자원뿌리들
    static func resourceRoots(_ d: ProjectDoc, _ module: BStr, _ platform: BStr) -> [BStr] {
        for i in 0..<d.declKinds.count where d.declKinds[i] == "모듈" && d.declNames[i] == module {
            return Project.declPlatformAttrs(d, i, "자원 경로", platform)
        }
        return []
    }

    // 정본: 프로젝트조정기능합치기
    static func mergeFeatures(_ input: [BStr], _ d: ProjectDoc, _ kind: BStr, _ name: BStr, _ platform: BStr) throws -> [BStr] {
        var result = input
        for i in 0..<d.declKinds.count {
            var match = false
            if d.declNames[i] == name {
                if d.declKinds[i] == kind { match = true }
                if kind != "모듈" && kind != "외부 구현" && d.declKinds[i] == "플랫폼 설정" { match = true }
            }
            if match {
                for f in Project.declPlatformAttrs(d, i, "필요 기능", platform) {
                    if !knownFeatures.contains(f) { throw CoordinatorError.failed("알 수 없는 필요 기능: " + f.string, 1) }
                    if !result.contains(f) { result.append(f) }
                }
            }
        }
        return result
    }

    // 정본: 프로젝트조정진입종류
    static func entryKind(_ sources: [BStr]) throws -> BStr {
        var mark: BStr = ""
        for s in sources {
            for line in readAll(s).split("\n") {
                if !line.hasPrefix(" ") && line.contains("함수 앱시작은") {
                    if mark.count > 0 { throw CoordinatorError.failed("앱시작 함수가 여러 개입니다", 1) }
                    if line.hasPrefix("비동기") {
                        mark = "비동기"
                    } else if line.contains("(") {
                        mark = "인자"
                    } else {
                        mark = "기본"
                    }
                }
            }
        }
        return mark
    }

    // 정본: 프로젝트조정표준자동인가
    static func stdAuto(_ target: BStr) -> Bool {
        if target.hasPrefix("limine-") { return false }
        if target.hasPrefix("aarch64-") && !target.hasPrefix("aarch64-stdapp-") { return false }
        return true
    }

    // 정본: 프로젝트조정자립타깃인가
    static let selfhostTargets: [BStr] = ["posix-host-exe", "posix-host-llvm-ir", "posix-host-hmir", "ios-sim-llvm-ir", "ios-llvm-ir", "ios-sim-app", "ios-app", "macos-app", "macos-launch-agent-pkg", "android-llvm-ir", "android-exe", "android-apk", "windows-llvm-ir", "windows-exe", "llvm-ir", "hmir", "limine-hmir", "app-hmir", "aarch64-limine-kernel-hmir", "limine-llvm-ir", "app-llvm-ir", "limine-elf64", "app-elf64", "aarch64-llvm-ir", "aarch64-elf64", "aarch64-limine-llvm-ir", "aarch64-limine-elf64", "aarch64-limine-kernel-llvm-ir", "aarch64-limine-kernel-elf64", "aarch64-app-llvm-ir", "aarch64-app-elf64", "aarch64-stdapp-llvm-ir", "aarch64-stdapp-elf64"]

    // 정본: 프로젝트조정필요모듈들
    static func neededModules(_ p: ProjectPlan) -> [BStr] {
        var result = p.rootModules
        var changed = true
        while changed {
            changed = false
            for i in 0..<p.moduleDepNames.count {
                let owner = p.moduleNames[p.moduleDepOwners[i]], dep = p.moduleDepNames[i]
                if result.contains(owner) && !result.contains(dep) {
                    result.append(dep)
                    changed = true
                }
            }
        }
        return result
    }

    // 정본: 프로젝트조정의존찾기 (못 찾으면 [])
    static func findDependency(_ root: BStr, _ d: ProjectDoc, _ library: BStr) -> [BStr] {
        if Project.plan(d, library).ok { return [root, library] }
        for i in 0..<d.declKinds.count where d.declKinds[i] == "의존 프로젝트" {
            let paths = Project.declAttrs(d, i, "로컬 경로")
            if paths.count == 1 {
                let candRoot = Project.joinPath(root, paths[0])
                let candDoc = Project.parse(readAll(candRoot + "/Project.hmjep"))
                if Project.plan(candDoc, library).ok { return [candRoot, library] }
            }
        }
        return []
    }

    // 정본: 프로젝트조정허용가져오기머리
    static func allowedImportsHeader(_ root: BStr, _ d: ProjectDoc, _ p: ProjectPlan, _ module: BStr) throws -> BStr {
        var allowed: [BStr] = []
        for i in 0..<p.moduleDepNames.count where p.moduleNames[p.moduleDepOwners[i]] == module {
            if !allowed.contains(p.moduleDepNames[i]) { allowed.append(p.moduleDepNames[i]) }
        }
        for i in 0..<p.libDepNames.count where p.moduleNames[p.libDepOwners[i]] == module {
            let loc = findDependency(root, d, p.libDepNames[i])
            if loc.count != 2 { throw CoordinatorError.failed("의존 라이브러리를 찾을 수 없습니다: " + p.libDepNames[i].string, 1) }
            let depDoc = Project.parse(readAll(loc[0] + "/Project.hmjep"))
            let depPlan = Project.plan(depDoc, loc[1])
            if !depPlan.ok || depPlan.artifactKind != "라이브러리" {
                throw CoordinatorError.failed("의존 산출물은 라이브러리여야 합니다: " + loc[1].string, 1)
            }
            for r in depPlan.rootModules where !allowed.contains(r) { allowed.append(r) }
        }
        var out: BStr = "# @hmje-allowed-imports\n"
        for a in allowed { out = out + "# @hmje-allowed-import " + a + "\n" }
        return out
    }

    // 정본: 프로젝트외부구현지표
    static func externalIndex(_ d: ProjectDoc, _ name: BStr) -> Int {
        for i in 0..<d.declKinds.count where d.declKinds[i] == "외부 구현" && d.declNames[i] == name { return i }
        return d.declKinds.count
    }

    // 정본: 프로젝트모듈외부구현들
    static func moduleExternals(_ d: ProjectDoc, _ module: BStr) -> [BStr] {
        for i in 0..<d.declKinds.count where d.declKinds[i] == "모듈" && d.declNames[i] == module {
            return Project.declAttrs(d, i, "외부 구현")
        }
        return []
    }

    // 정본: 프로젝트산출물외부구현들
    static func artifactExternals(_ d: ProjectDoc, _ artifact: BStr) -> [BStr] {
        for i in 0..<d.declKinds.count where d.declNames[i] == artifact {
            let k = d.declKinds[i]
            if k == "실행 파일" || k == "라이브러리" || k == "앱" || k == "시험" { return Project.declAttrs(d, i, "외부 구현") }
        }
        return []
    }

    // 정본: 프로젝트조정외부계획
    static func externalPlan(_ root: BStr, _ d: ProjectDoc, _ name: BStr, _ platform: BStr) throws -> BStr {
        let i = externalIndex(d, name)
        if i >= d.declKinds.count { throw CoordinatorError.failed("외부 구현을 찾을 수 없습니다: " + name.string, 1) }
        let srcRoots = Project.declPlatformAttrs(d, i, "원본 경로", platform)
        if srcRoots.count != 1 { throw CoordinatorError.failed("외부 구현 원본 경로가 필요합니다: " + name.string, 1) }
        let absRoot = Project.joinPath(root, srcRoots[0])
        var out: BStr = ""
        for s in Project.declPlatformAttrs(d, i, "원본 파일", platform) {
            let abs = Project.joinPath(absRoot, s)
            let kind: BStr = s.hasSuffix(".metal") ? "metal" : "source"
            out = out + kind + "\t" + abs + "\n"
        }
        for h in Project.declPlatformAttrs(d, i, "헤더 경로", platform) { out = out + "include\t" + absRoot + "/" + h + "\n" }
        for v in Project.declPlatformAttrs(d, i, "컴파일 정의", platform) { out = out + "define\t" + v + "\n" }
        for v in Project.declPlatformAttrs(d, i, "시스템 프레임워크", platform) { out = out + "framework\t" + v + "\n" }
        for v in Project.declPlatformAttrs(d, i, "시스템 라이브러리", platform) { out = out + "library\t" + v + "\n" }
        return out
    }

    /// 정본: 타입AST파일전체읽기 (없으면 "")
    static func readAll(_ path: BStr) -> BStr {
        guard path.count > 0, let d = FileManager.default.contents(atPath: path.string) else { return "" }
        return BStr([UInt8](d))
    }

    /// 정본: 프로젝트조정파일쓰기
    static func writeAll(_ path: BStr, _ body: BStr) throws {
        let ok = body.withBytes { FileManager.default.createFile(atPath: path.string, contents: Data($0)) }
        if !ok { throw CoordinatorError.failed("파일을 쓸 수 없습니다: " + path.string, 1) }
    }

    /// hmje_posix_path_slot_hash (FNV-1a 64)
    static func slotHash(_ s: BStr) -> UInt64 {
        s.withBytes { bytes in
            var h: UInt64 = 1469598103934665603
            for b in bytes { h ^= UInt64(b); h = h &* 1099511628211 }
            return h
        }
    }
}

/// 정본 프로젝트조정기 앱시작의 계획 구간.
/// - selfhost: 정본 인자들[1] (hmjec-selfhost 경로; 표준 뿌리 = 그 부모/../library)
/// - options: 정본 인자들[8…]
/// 산출물은 `outDir`에 쓴다: entry.hmje, modules.tsv, native.tsv, modules/<FNV>.hmje.
/// 정본은 작업 슬롯에 module-N.hmje를 쓰고 캐시 폴더로 내용 주소 사본을 게시한다 — 씨앗은
/// 게시될 내용 주소 경로에 바로 쓴다(지도가 가리키는 경로와 내용이 같다).
public func coordinateProjectPlan(selfhost: String, projectRoot: String, artifact: String, target: String,
                                  platform: String, options: [String], outDir: String) -> Result<CoordinatorPlan, CoordinatorError> {
    do { return .success(try coordinatePlanThrowing(selfhost, projectRoot, artifact, target, platform, options, outDir)) }
    catch let e as CoordinatorError { return .failure(e) }
    catch { return .failure(.failed("\(error)", 1)) }
}

private func coordinatePlanThrowing(_ selfhost: String, _ projectRootArg: String, _ artifactS: String, _ targetS: String,
                                    _ platformS: String, _ options: [String], _ outDirS: String) throws -> CoordinatorPlan {
    typealias C = Coordinator
    let artifact = BStr(artifactS), target = BStr(targetS), platform = BStr(platformS)
    let projectRoot = Project.absPath(BStr(projectRootArg))
    let manifest = projectRoot + "/Project.hmjep"
    let doc = Project.parse(C.readAll(manifest))
    let rootPlan = Project.plan(doc, artifact)
    if !rootPlan.ok { throw CoordinatorError.failed(rootPlan.error.string, 1) }
    if !C.selfhostTargets.contains(target) { throw CoordinatorError.failed("이 프로젝트 타깃은 아직 자립하지 않았습니다", 2) }
    let slot = BStr(outDirS)
    if mkdirAll(slot.string) != 0 { throw CoordinatorError.failed("프로젝트 작업 디렉터리를 만들 수 없습니다", 1) }
    if getenv("HMJE_PROJECT_BUNDLE_PLAN_OUTPUT") != nil { fatalError("미이식: 프로젝트조정기 번들 계획(HMJE_PROJECT_BUNDLE_PLAN_OUTPUT)") }

    var mapBody: BStr = "", nativeBody: BStr = ""
    var registeredExternals: [BStr] = []
    var allRootSources: [BStr] = [], allSources: [BStr] = []
    var registeredModules: [BStr] = [], registeredModuleKeys: [BStr] = []
    var hasAudio = false, hasNetwork = false
    var features: [BStr] = []
    var queueRoots: [BStr] = [projectRoot], queueArtifacts: [BStr] = [artifact]
    let stdRoot = Project.joinPath(Project.coordParent(BStr(selfhost)), "../library")
    let stdAuto = C.stdAuto(target)
    if stdAuto { queueRoots.append(stdRoot); queueArtifacts.append("표준") }
    var donePlans: [BStr] = []
    var q = 0
    while q < queueRoots.count {
        let curRoot = queueRoots[q], curArtifact = queueArtifacts[q]
        let planKey = curRoot + "\t" + curArtifact
        if !donePlans.contains(planKey) {
            donePlans.append(planKey)
            let curDoc = Project.parse(C.readAll(curRoot + "/Project.hmjep"))
            let curPlan = Project.plan(curDoc, curArtifact)
            if !curPlan.ok { throw CoordinatorError.failed(curPlan.error.string, 1) }
            features = try C.mergeFeatures(features, curDoc, curPlan.artifactKind, curArtifact, platform)
            let needed = C.neededModules(curPlan)
            for m in 0..<curPlan.moduleNames.count {
                let module = curPlan.moduleNames[m]
                let moduleKey = curRoot + "\t" + module
                if needed.contains(module) && !registeredModuleKeys.contains(moduleKey) {
                    if registeredModules.contains(module) {
                        throw CoordinatorError.failed("프로젝트 graph에 서로 다른 모듈이 같은 이름을 씁니다: " + module.string, 1)
                    }
                    features = try C.mergeFeatures(features, curDoc, "모듈", module, platform)
                    registeredModuleKeys.append(moduleKey)
                    registeredModules.append(module)
                    // 정본은 원본뿌리(프로젝트조정결합경로)를 계산만 하고 쓰지 않는다.
                    _ = Project.joinPath(curRoot, curPlan.moduleSourcePaths[m])
                    let sources = Project.moduleSources(curRoot, curDoc, module, platform)
                    if sources.count == 0 { throw CoordinatorError.failed("모듈 원본이 없습니다: " + module.string, 1) }
                    var body = "# @hmje-project " + curRoot + "\n"
                    if stdAuto && curRoot == stdRoot && module == "표준" { body = body + "# @hmje-implicit-module\n" }
                    body = body + (try C.allowedImportsHeader(curRoot, curDoc, curPlan, module))
                    for s in sources {
                        if s.contains("\"") { throw CoordinatorError.failed("따옴표가 든 원본 경로는 지원하지 않습니다", 1) }
                        body = body + "\"" + s + "\"를 가져온다.\n"
                        if q == 0 && rootPlan.rootModules.contains(module) { allRootSources.append(s) }
                        allSources.append(s)
                        if s.hasSuffix("/audio_capture.hmje") { hasAudio = true }
                        if s.hasSuffix("/socket.hmje") { hasNetwork = true }
                    }
                    let cacheDir = slot + "/modules"
                    let cachePath = cacheDir + "/" + BStr(decimal: C.slotHash(body)) + ".hmje"
                    if mkdirAll(cacheDir.string) != 0 { throw CoordinatorError.failed("모듈 집계 캐시를 게시하지 못했습니다", 1) }
                    try C.writeAll(cachePath, body)
                    mapBody = mapBody + module + "\t" + cachePath + "\n"
                    for rr in C.resourceRoots(curDoc, module, platform) {
                        let resRoot = Project.joinPath(curRoot, rr)
                        for f in listProjectFiles(resRoot) {
                            let logical = f == resRoot ? Project.fileName(resRoot) : f.sub(resRoot.count + 1, f.count - resRoot.count - 1)
                            nativeBody = nativeBody + "resource\t" + f + "\t" + logical + "\n"
                        }
                    }
                    for ext in C.moduleExternals(curDoc, module) {
                        let extKey = curRoot + "\t" + ext
                        if !registeredExternals.contains(extKey) {
                            features = try C.mergeFeatures(features, curDoc, "외부 구현", ext, platform)
                            registeredExternals.append(extKey)
                            nativeBody = nativeBody + (try C.externalPlan(curRoot, curDoc, ext, platform))
                        }
                    }
                }
            }
            for ext in C.artifactExternals(curDoc, curArtifact) {
                let extKey = curRoot + "\t" + ext
                if !registeredExternals.contains(extKey) {
                    features = try C.mergeFeatures(features, curDoc, "외부 구현", ext, platform)
                    registeredExternals.append(extKey)
                    nativeBody = nativeBody + (try C.externalPlan(curRoot, curDoc, ext, platform))
                }
            }
            for i in 0..<curPlan.libDepNames.count {
                let owner = curPlan.moduleNames[curPlan.libDepOwners[i]]
                if needed.contains(owner) {
                    let loc = C.findDependency(curRoot, curDoc, curPlan.libDepNames[i])
                    if loc.count != 2 { throw CoordinatorError.failed("의존 라이브러리를 찾을 수 없습니다: " + curPlan.libDepNames[i].string, 1) }
                    if !donePlans.contains(loc[0] + "\t" + loc[1]) {
                        queueRoots.append(loc[0]); queueArtifacts.append(loc[1])
                    }
                }
            }
        }
        q += 1
    }
    // 네트워크·오디오 입력·위치·카메라 판정은 번들 메타(ios-/macos-/android-)와 번들 계획에서만 쓰인다.
    _ = (hasAudio, hasNetwork)
    let mapPath = slot + "/modules.tsv"
    try C.writeAll(mapPath, mapBody)
    if target.hasPrefix("ios-") || target.hasPrefix("macos-") || target.hasPrefix("android-") {
        fatalError("미이식: 프로젝트조정기 번들 메타(" + targetS + ")")
    }
    let nativePath = slot + "/native.tsv"
    try C.writeAll(nativePath, nativeBody)
    let kind = try C.entryKind(allRootSources)
    if kind.count == 0 { throw CoordinatorError.failed("선택 산출물에 앱시작 함수가 없습니다", 1) }
    var entry = "# @hmje-entry " + kind + "\n"
    if stdAuto { entry = entry + "표준을 가져온다.\n" }
    for r in rootPlan.rootModules { entry = entry + r + "을 가져온다.\n" }
    let entryPath = slot + "/entry.hmje"
    try C.writeAll(entryPath, entry)
    var extra: [String] = []
    var o = 0
    while o < options.count {
        if options[o] == "--define" {
            if o + 1 >= options.count { throw CoordinatorError.failed("--define에 값이 필요합니다", 2) }
            for d in BStr(options[o + 1]).split("\n") where d.count > 0 { nativeBody = nativeBody + "define\t" + d + "\n" }
            o += 1
        } else {
            extra.append(options[o])
        }
        o += 1
    }
    try C.writeAll(nativePath, nativeBody)
    if getenv("HMJE_PROJECT_MODULE_MAP_OUTPUT") != nil || getenv("HMJE_PROJECT_ENTRY_OUTPUT") != nil {
        fatalError("미이식: 프로젝트조정기 지도/진입 출력 요청")
    }
    return CoordinatorPlan(entryPath: entryPath.string, mapPath: mapPath.string, nativePath: nativePath.string, extraOptions: extra)
}

/// hmje_posix_directory_create_all
private func mkdirAll(_ path: String) -> Int32 {
    do { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true); return 0 }
    catch { return -1 }
}
