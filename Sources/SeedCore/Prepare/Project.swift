// 정본: 프로젝트/파서.hmje, 프로젝트/계획.hmje, 프로젝트/원본선택.hmje, 프로젝트/포직스원본.hmje 중
// 표준모듈지도보강이 쓰는 부분(library/Project.hmjep 읽기 → 모듈 원본 목록).

struct ProjectDoc {
    var ok: Bool
    var declKinds: [BStr] = []
    var declNames: [BStr] = []
    var attrDecl: [Int] = []
    var attrNames: [BStr] = []
    var attrValues: [BStr] = []
    var attrPlatforms: [BStr] = []
    var error: BStr = ""
}

struct ProjectPlan {
    var ok: Bool
    var projectName: BStr = ""
    var artifactKind: BStr = ""
    var artifactName: BStr = ""
    var rootModules: [BStr] = []
    var moduleNames: [BStr] = []
    var moduleSourcePaths: [BStr] = []
    var moduleDepOwners: [Int] = []
    var moduleDepNames: [BStr] = []
    var libDepOwners: [Int] = []
    var libDepNames: [BStr] = []
    var depProjectNames: [BStr] = []
    var depProjectPaths: [BStr] = []
    var error: BStr = ""
}

enum Project {
    // 정본: 프로젝트선언머리
    static func declHead(_ line: BStr) -> [BStr] {
        let kinds: [BStr] = ["의존 프로젝트", "실행 파일", "외부 구현", "프로젝트", "라이브러리", "모듈", "앱", "시험"]
        for k in kinds {
            let prefix = k + " "
            if line.hasPrefix(prefix) && line.hasSuffix("의") {
                let name = line.sub(prefix.count, line.count - prefix.count - BStr("의").count)
                return [k, name]
            }
        }
        return []
    }

    // 정본: 프로젝트속성분리
    static func splitAttr(_ line: BStr) -> [BStr] {
        let names: [BStr] = ["시스템 프레임워크", "시스템 라이브러리", "의존 라이브러리", "내보내는 모듈", "컴파일 정의", "지원 플랫폼", "외부 구현", "의존 모듈", "원본 파일", "헤더 경로", "묶음 식별자", "아이콘 자원", "로컬 경로", "원본 경로", "자원 경로", "요구 버전", "표시 이름", "시험 모듈", "시험 대상", "시작 모듈", "깃 주소", "의존성", "권한 파일", "필요 기능", "버전", "파일 공유"]
        // 정본은 25개만 본다(마지막 "파일 공유"는 보지 않는다).
        for i in 0..<25 {
            let eun = names[i] + "은 ", neun = names[i] + "는 "
            if line.hasPrefix(eun) { return [names[i], line.sub(eun.count, line.count - eun.count)] }
            if line.hasPrefix(neun) { return [names[i], line.sub(neun.count, line.count - neun.count)] }
            if line == names[i] + "은" || line == names[i] + "는" { return [names[i], ""] }
        }
        if let p = line.find("은 ") {
            let l = BStr("은 ").count
            return [line.sub(0, p), line.sub(p + l, line.count - p - l)]
        }
        if let p = line.find("는 ") {
            let l = BStr("는 ").count
            return [line.sub(0, p), line.sub(p + l, line.count - p - l)]
        }
        if line.hasSuffix("은") { return [line.sub(0, line.count - BStr("은").count), ""] }
        if line.hasSuffix("는") { return [line.sub(0, line.count - BStr("는").count), ""] }
        return []
    }

    // 정본: 프로젝트값끝났나
    static func valueEnded(_ line: BStr) -> Bool { line.hasSuffix("이다.") || line.hasSuffix("이고,") }

    // 정본: 프로젝트값정리
    static func cleanValue(_ raw: BStr) -> BStr {
        var v = raw.trimmed()
        if v.hasSuffix("과,") || v.hasSuffix("와,") {
            v = v.sub(0, v.count - BStr("과,").count)
        } else if v.hasSuffix("이고,") {
            v = v.sub(0, v.count - BStr("이고,").count)
        } else if v.hasSuffix("이다.") {
            v = v.sub(0, v.count - BStr("이다.").count)
        }
        v = v.trimmed()
        if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 { v = v.sub(1, v.count - 2) }
        return v
    }

    static let platforms: [BStr] = ["macOS", "iOS", "Linux", "Android", "Windows", "semtleOS"]

    // 정본: 프로젝트플랫폼머리
    static func platformHead(_ line: BStr) -> BStr {
        for p in platforms where line == p + " 설정의" { return p }
        return ""
    }

    // 정본: 프로젝트산출물플랫폼머리
    static func artifactPlatformHead(_ line: BStr) -> [BStr] {
        let kinds: [BStr] = ["실행 파일", "라이브러리", "앱", "시험"]
        for k in kinds {
            for p in platforms {
                let tail = " " + k + "의 " + p + " 설정의"
                if line.hasSuffix(tail) && line.count > tail.count {
                    return [line.sub(0, line.count - tail.count), p]
                }
            }
        }
        return []
    }

    // 정본: 프로젝트문서파싱
    static func parse(_ content: BStr) -> ProjectDoc {
        var d = ProjectDoc(ok: true)
        var cur = 0
        var has = false
        var pending: BStr = ""
        var curPlatform: BStr = ""
        for raw in content.splitFast("\n") {
            let line = raw.trimmed()
            if line.count > 0 && !line.hasPrefix("#") {
                var heads: [BStr] = []
                var apHeads: [BStr] = []
                if !raw.hasPrefix(" ") && !raw.hasPrefix("\t") {
                    heads = declHead(line)
                    if heads.count == 0 { apHeads = artifactPlatformHead(line) }
                }
                if heads.count == 2 {
                    d.declKinds.append(heads[0]); d.declNames.append(heads[1])
                    cur = d.declKinds.count - 1; has = true; pending = ""; curPlatform = ""
                } else if apHeads.count == 2 {
                    d.declKinds.append("플랫폼 설정"); d.declNames.append(apHeads[0])
                    cur = d.declKinds.count - 1; has = true; pending = ""; curPlatform = apHeads[1]
                } else if has {
                    let ph = platformHead(line)
                    let piece = splitAttr(line)
                    if ph.count > 0 {
                        curPlatform = ph; pending = ""
                    } else if piece.count == 2 {
                        pending = piece[0]
                        if piece[1].count > 0 {
                            d.attrDecl.append(cur); d.attrNames.append(pending)
                            d.attrValues.append(cleanValue(piece[1])); d.attrPlatforms.append(curPlatform)
                            if valueEnded(piece[1]) { pending = "" }
                        }
                    } else if pending.count > 0 {
                        d.attrDecl.append(cur); d.attrNames.append(pending)
                        d.attrValues.append(cleanValue(line)); d.attrPlatforms.append(curPlatform)
                        if valueEnded(line) { pending = "" }
                    }
                } else {
                    return ProjectDoc(ok: false, error: "선언 밖 속성: " + line)
                }
            }
        }
        if d.declKinds.count == 0 { return ProjectDoc(ok: false, error: "프로젝트 선언이 없습니다") }
        return d
    }

    // 정본: 프로젝트선언속성들
    static func declAttrs(_ d: ProjectDoc, _ decl: Int, _ name: BStr) -> [BStr] {
        var out: [BStr] = []
        for i in 0..<d.attrNames.count where d.attrDecl[i] == decl && d.attrNames[i] == name { out.append(d.attrValues[i]) }
        return out
    }

    // 정본: 프로젝트선언플랫폼속성들
    static func declPlatformAttrs(_ d: ProjectDoc, _ decl: Int, _ name: BStr, _ platform: BStr) -> [BStr] {
        var out: [BStr] = []
        for i in 0..<d.attrNames.count where d.attrDecl[i] == decl && d.attrNames[i] == name {
            if d.attrPlatforms[i].count == 0 || d.attrPlatforms[i] == platform { out.append(d.attrValues[i]) }
        }
        return out
    }

    static func isArtifactKind(_ k: BStr) -> Bool { k == "앱" || k == "실행 파일" || k == "라이브러리" }

    // 정본: 프로젝트계획만들기
    static func plan(_ d: ProjectDoc, _ requested: BStr) -> ProjectPlan {
        func fail(_ e: BStr) -> ProjectPlan { ProjectPlan(ok: false, error: e) }
        if !d.ok { return fail(d.error) }
        var p = ProjectPlan(ok: true)
        for i in 0..<d.declKinds.count {
            let kind = d.declKinds[i], name = d.declNames[i]
            if kind == "프로젝트" {
                if p.projectName.count > 0 { return fail("프로젝트 선언이 중복되었습니다") }
                p.projectName = name
            } else if kind == "모듈" {
                if p.moduleNames.contains(name) { return fail("중복된 모듈: " + name) }
                p.moduleNames.append(name)
                let srcs = declAttrs(d, i, "원본 경로")
                p.moduleSourcePaths.append(srcs.count > 0 ? srcs[0] : "Sources/" + name)
                for dep in declAttrs(d, i, "의존 모듈") { p.moduleDepOwners.append(p.moduleNames.count - 1); p.moduleDepNames.append(dep) }
                for dep in declAttrs(d, i, "의존 라이브러리") { p.libDepOwners.append(p.moduleNames.count - 1); p.libDepNames.append(dep) }
            } else if kind == "의존 프로젝트" {
                if p.depProjectNames.contains(name) { return fail("중복된 의존 프로젝트: " + name) }
                let paths = declAttrs(d, i, "로컬 경로")
                if paths.count != 1 { return fail("로컬 경로가 필요합니다: " + name) }
                p.depProjectNames.append(name); p.depProjectPaths.append(paths[0])
            }
        }
        if p.projectName.count == 0 { return fail("프로젝트 선언이 없습니다") }
        for dep in p.moduleDepNames where !p.moduleNames.contains(dep) { return fail("없는 의존 모듈: " + dep) }
        for i in 0..<d.declKinds.count {
            let kind = d.declKinds[i], name = d.declNames[i]
            if isArtifactKind(kind) && name == requested {
                if p.artifactKind.count > 0 { return fail("중복된 산출물: " + name) }
                p.artifactKind = kind; p.artifactName = name
                if kind == "라이브러리" {
                    p.rootModules = declAttrs(d, i, "내보내는 모듈")
                    if p.rootModules.count == 0 { return fail("라이브러리에 내보내는 모듈이 없습니다: " + name) }
                } else {
                    p.rootModules = declAttrs(d, i, "시작 모듈")
                    if p.rootModules.count != 1 { return fail("시작 모듈이 필요합니다: " + name) }
                }
            }
        }
        if p.artifactKind.count == 0 { return fail("산출물을 찾을 수 없습니다: " + requested) }
        for r in p.rootModules where !p.moduleNames.contains(r) { return fail("없는 루트 모듈: " + r) }
        return p
    }

    // 정본: 포직스프로젝트절대경로 (실패하면 "")
    static func absPath(_ path: BStr) -> BStr { realPathRaw(path) ?? "" }

    // 정본: 프로젝트조정결합경로
    static func joinPath(_ root: BStr, _ path: BStr) -> BStr {
        if path.hasPrefix("/") { return absPath(path) }
        return absPath(root + "/" + path)
    }

    // 정본: 프로젝트조정부모경로
    static func coordParent(_ path: BStr) -> BStr {
        var last = path.count
        for i in 0..<path.count where path[i] == 47 { last = i }
        if last == path.count { return "." }
        if last == 0 { return "/" }
        return path.sub(0, last)
    }

    // 정본: 프로젝트조정파일이름
    static func fileName(_ path: BStr) -> BStr {
        let parent = coordParent(path)
        var start = parent.count
        if parent != "/" { start += 1 }
        return path.sub(start, path.count - start)
    }

    // 정본: 프로젝트조정모듈원본들
    static func moduleSources(_ projectRoot: BStr, _ d: ProjectDoc, _ module: BStr, _ platform: BStr) -> [BStr] {
        var roots: [BStr] = [], selected: [BStr] = [], excluded: [BStr] = []
        for i in 0..<d.declKinds.count where d.declKinds[i] == "모듈" && d.declNames[i] == module {
            roots = declPlatformAttrs(d, i, "원본 경로", platform)
            selected = declPlatformAttrs(d, i, "원본 파일", platform)
            excluded = declPlatformAttrs(d, i, "제외 원본 파일", platform)
        }
        if roots.count == 0 { roots.append("Sources/" + module) }
        var result: [BStr] = []
        var found: [BStr] = []
        for r in roots {
            let root = joinPath(projectRoot, r)
            let listed = listHMJESources(root)
            var sources: [BStr] = []
            for e in listed {
                let rel = e == root ? fileName(root) : e.sub(root.count + 1, e.count - root.count - 1)
                if !excluded.contains(rel) { sources.append(e) }
            }
            if selected.count == 0 {
                for s in sources where !result.contains(s) { result.append(s) }
            } else {
                for sel in selected {
                    if sel.hasPrefix("/") { prepFail("모듈 원본 파일은 선언된 원본 경로에 대한 상대 경로여야 합니다") }
                    var cand = joinPath(root, sel)
                    if sources.count == 1 && sources[0] == root && sel == fileName(root) { cand = root }
                    if sources.contains(cand) {
                        if !result.contains(cand) { result.append(cand) }
                        found.append(sel)
                    }
                }
            }
        }
        for sel in selected where !found.contains(sel) { prepFail("선택된 원본 파일이 선언된 원본 경로에 없습니다: " + sel.string) }
        return result
    }
}
