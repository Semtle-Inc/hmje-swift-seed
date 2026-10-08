// HMIR생성/타입.hmje — 타입 해석·표시와 전역 등록부.
// 정본 등록부는 해시+길이로 찾는다. 여기서는 문자열 동치로 찾는다(32칸 안의 64비트 충돌은 없다).

extension HMIRGenerator {

    // 정본: HMIR표면동적배열초기화
    func registryReset() {
        surfaceDynArrays = []
        fnDisplayNames = []
        fnDisplayValues = []
    }

    // 정본: HMIR함수값표시등록
    func fnDisplayRegister(_ name: BStr, _ disp: BStr) {
        if fnDisplayNames.count >= 32 { return }
        fnDisplayNames.append(name)
        fnDisplayValues.append(disp)
    }

    // 정본: HMIR함수값표시찾기
    func fnDisplayFind(_ name: BStr) -> BStr {
        for i in 0..<fnDisplayNames.count where fnDisplayNames[i] == name { return fnDisplayValues[i] }
        return name
    }

    // 정본: HMIR함수값접두찾기
    func fnPrefixFind(_ disp: BStr) -> BStr {
        for i in 0..<fnDisplayValues.count where fnDisplayValues[i] == disp { return fnDisplayNames[i] }
        return disp
    }

    // 정본: HMIR채널끝점구조인가
    func isChannelEndpointStruct(_ n: BStr) -> Bool {
        if n.hasSuffix("선택값") { return false }
        if n.hasPrefix("HMJE채널송신_") || n.hasPrefix("HMJE채널수신_") { return true }
        return false
    }

    // 정본: HMIR채널끝점표시
    func channelEndpointDisplay(_ n: BStr) -> BStr {
        let reg = fnDisplayFind(n)
        if reg != n { return reg }
        var pre: BStr = "HMJE채널송신_"
        var act: BStr = " 보내는 채널"
        if n.hasPrefix("HMJE채널수신_") { pre = "HMJE채널수신_"; act = " 받는 채널" }
        let pl = pre.count, tl = n.count
        if tl <= pl + 11 { return n }
        let readable = hSub(n, pl, tl - pl - 11)
        var out: [UInt8] = []
        readable.withBytes { for b in $0 { if b == 95 { out.append(32) } else { out.append(b) } } }
        let ed = BStr(out)
        return hcat(ed, hObjParticle(ed), act)
    }

    // 정본: HMIR표면동적배열등록
    func surfaceDynArrayRegister(_ n: BStr) {
        for x in surfaceDynArrays where x == n { return }
        if surfaceDynArrays.count < 32 { surfaceDynArrays.append(n) }
    }

    // 정본: HMIR표면동적배열인가
    func isSurfaceDynArray(_ n: BStr) -> Bool {
        for x in surfaceDynArrays where x == n { return true }
        return false
    }

    // 정본: HMIR생성타입접두사
    func genTypePrefix(_ elem: BStr) -> BStr {
        let inner = typeResolve(elem)
        if isFnValueType(inner) { return fnPrefixFind(typeDisplay(inner)) }
        switch inner {
        case "u8": return "자연수8"
        case "u16": return "자연수16"
        case "u32": return "자연수32"
        case "u64": return "자연수64"
        case "i8": return "정수8"
        case "i16": return "정수16"
        case "i32": return "정수32"
        case "i64": return "정수64"
        case "f32": return "실수32"
        case "f64": return "실수64"
        case "char": return "문자"
        case "bool": return "참거짓"
        case "address": return "주소"
        case "text": return "문자열배열"
        default: break
        }
        if inner.hasPrefix("struct:") {
            let name = hSub(inner, 7, inner.count - 7)
            if name.hasSuffix("동적배열형") { return hcat(hSub(name, 0, name.count - 15), "배열") }
            return name
        }
        return elem
    }

    // 정본: HMIR타입해석
    func typeResolve(_ t: BStr) -> BStr {
        if t.hasPrefix("struct:") { return t }
        var chAct: BStr = ""
        if t.hasSuffix(" 보내는 채널") { chAct = " 보내는 채널" } else if t.hasSuffix(" 받는 채널") { chAct = " 받는 채널" }
        if chAct.count > 0 {
            let rem = t.count - chAct.count
            if rem >= 3 {
                let es = hSub(t, 0, rem - 3)
                let ei = typeResolve(es)
                let ed = typeDisplay(ei)
                let cd = hcat(ed, hObjParticle(ed), chAct)
                let cs = fnPrefixFind(cd)
                if cs != cd { return hcat("struct:", cs) }
            }
        }
        if t == "문자열의 배열" { return "struct:문자열배열동적배열형" }
        if t.hasSuffix("의 배열") {
            let elem = hSub(t, 0, t.count - 10)
            return hcat("struct:", genTypePrefix(elem), "동적배열형")
        }
        if t == "문자열?" { return "struct:문자열선택값" }
        if t == "자연수64?" || t == "큰자연수?" { return "struct:자연수64선택값" }
        if t == "정수64?" || t == "큰정수?" { return "struct:정수64선택값" }
        if t == "실수64?" { return "struct:실수64선택값" }
        if t.hasSuffix("?") {
            let oe = hSub(t, 0, t.count - 1)
            let oi = typeResolve(oe)
            if oi.hasPrefix("struct:") && oi.hasSuffix("동적배열형") {
                let ad = typeDisplay(oi)
                let tail: BStr = "의 배열"
                if ad.hasSuffix(tail) {
                    var ae = hSub(ad, 0, ad.count - tail.count)
                    if ae == "큰자연수" { ae = "자연수64" }
                    if ae == "큰정수" { ae = "정수64" }
                    return hcat("struct:", ae, "배열선택값")
                }
                let oas = hSub(oi, 7, oi.count - 7)
                return hcat("struct:", oas, "선택값")
            }
            let od = typeDisplay(oi)
            let orp = fnPrefixFind(od)
            if orp != od { return hcat("struct:", orp, "선택값") }
            return hcat("struct:", genTypePrefix(oe), "선택값")
        }
        if t.hasSuffix("동적배열형") { return hcat("struct:", t) }
        switch t {
        case "string", "문자열", "text": return "text"
        case "char", "문자": return "char"
        case "bool", "참거짓": return "bool"
        case "address", "주소": return "address"
        case "float", "float64", "실수", "실수64": return "f64"
        case "float32", "실수32": return "f32"
        case "작은자연수", "자연수8": return "u8"
        case "중간자연수", "자연수16": return "u16"
        case "자연수32": return "u32"
        case "자연수", "큰자연수", "자연수64": return "u64"
        case "작은정수", "정수8": return "i8"
        case "중간정수", "정수16": return "i16"
        case "정수32": return "i32"
        case "정수", "큰정수", "정수64": return "i64"
        default: return t
        }
    }

    // 정본: HMIR함수값타입인가
    func isFnValueType(_ t: BStr) -> Bool {
        if hHas(t, "|") {
            if t.hasPrefix("fn") || t.hasPrefix("asyncfn") { return true }
        }
        let recv = hHas(t, " 받아 ")
        let none = hHas(t, "받지 않고")
        if hHas(t, "반환") {
            if recv { return true }
            if none { return true }
        }
        return false
    }

    // 정본: HMIR비동기함수값타입인가
    func isAsyncFnValueType(_ t: BStr) -> Bool {
        if !isFnValueType(t) { return false }
        if t.hasPrefix("asyncfn") || hHas(t, "비동기로 반환") { return true }
        return false
    }

    // 정본: HMIR함수값반환타입
    func fnValueReturnType(_ t: BStr) -> BStr {
        if let bar = hFind(t, "|") {
            var st = 3
            if t.hasPrefix("asyncfn") { st = 8 }
            return typeResolve(hSub(t, st, bar - st))
        }
        if hHas(t, "반환하지 않음") { return "void" }
        var start = 0
        if let p = hFind(t, " 받아 ") {
            start = p + 8
        } else if let p = hFind(t, "받지 않고 ") {
            start = p + 14
        }
        let rest = hSub(t, start, t.count - start)
        if let p = hFind(rest, "를 비동기로 반환") { return typeResolve(hSub(rest, 0, p)) }
        if let p = hFind(rest, "을 비동기로 반환") { return typeResolve(hSub(rest, 0, p)) }
        if let p = hFind(rest, "를 반환") { return typeResolve(hSub(rest, 0, p)) }
        if let p = hFind(rest, "을 반환") { return typeResolve(hSub(rest, 0, p)) }
        return ""
    }

    // 정본: HMIR함수값첫매개타입
    func fnValueFirstParamType(_ t: BStr) -> BStr {
        if let bar = hFind(t, "|") {
            if t.count <= bar + 2 { return "" }
            return typeResolve(hSub(t, bar + 1, t.count - bar - 2))
        }
        guard let p = hFind(t, " 받아 ") else { return "" }
        var ps = hSub(t, 0, p)
        if ps.count >= 3 { ps = hSub(ps, 0, ps.count - 3) }
        return typeResolve(ps)
    }

    // 정본: HMIR최상위쉼표가르기
    func splitTopLevelCommas(_ body: BStr) -> [BStr] {
        var parts: [BStr] = []
        let n = body.count
        var depth = 0, ps = 0, i = 0
        while i < n {
            let b = hByte(body, i)
            if b == 40 || b == 60 || b == 91 { depth += 1 }
            if b == 41 || b == 62 || b == 93 { if depth > 0 { depth -= 1 } }
            if b == 44 && depth == 0 {
                let f = hTrim(hSub(body, ps, i - ps))
                if f.count > 0 { parts.append(f) }
                ps = i + 1
            }
            i += 1
        }
        let l = hTrim(hSub(body, ps, n - ps))
        if l.count > 0 { parts.append(l) }
        return parts
    }

    // 정본: HMIR값조사떼기
    func stripValueParticle(_ body: BStr) -> BStr {
        let t = hTrim(body)
        if t.hasSuffix("을") || t.hasSuffix("를") { return hTrim(hSub(t, 0, t.count - 3)) }
        return t
    }

    // 정본: HMIR매개표면가르기
    func splitParamSurface(_ surf: BStr) -> [BStr] {
        if hHas(surf, ",") { return splitTopLevelCommas(surf) }
        var parts: [BStr] = []
        let n = surf.count
        var depth = 0, ps = 0, i = 0
        while i < n {
            let b = hByte(surf, i)
            if b == 40 || b == 60 || b == 91 { depth += 1 }
            if b == 41 || b == 62 || b == 93 { if depth > 0 { depth -= 1 } }
            var conj = false
            if depth == 0 && i + 3 <= n {
                let g = hSub(surf, i, 3)
                if g == "와" || g == "과" {
                    var before = false
                    if i == 0 { before = true } else if hByte(surf, i - 1) == 32 { before = true }
                    var after = false
                    if i + 3 >= n { after = true } else if hByte(surf, i + 3) == 32 { after = true }
                    if before || after { conj = true }
                }
            }
            if conj {
                let f = hTrim(hSub(surf, ps, i - ps))
                if f.count > 0 { parts.append(f) }
                i += 3
                ps = i
            } else {
                i += 1
            }
        }
        let l = hTrim(hSub(surf, ps, n - ps))
        if l.count > 0 { parts.append(l) }
        return parts
    }

    // 정본: HMIR함수값매개타입들
    func fnValueParamTypes(_ t: BStr) -> [BStr] {
        var ps: [BStr] = []
        if let bar = hFind(t, "|") {
            if t.count <= bar + 2 { return ps }
            let inner = hSub(t, bar + 1, t.count - bar - 2)
            for x in splitTopLevelCommas(inner) { ps.append(typeResolve(x)) }
            return ps
        }
        guard let p = hFind(t, " 받아 ") else { return ps }
        let surf = stripValueParticle(hSub(t, 0, p))
        if surf.count == 0 || surf == "아무것도" { return ps }
        for x in splitParamSurface(surf) { ps.append(typeResolve(stripValueParticle(x))) }
        return ps
    }

    // 정본: HMIR타입표시
    func typeDisplay(_ t: BStr) -> BStr {
        let inner = typeResolve(t)
        if inner.hasPrefix("overlay:") { return hcat(hSub(inner, 8, inner.count - 8), "에 놓인 뷰") }
        if inner.hasPrefix("enum:") { return hSub(inner, 5, inner.count - 5) }
        if isFnValueType(inner) {
            let fr = fnValueReturnType(inner)
            let fp = fnValueFirstParamType(inner)
            var fd: BStr = ""
            if fp.count == 0 {
                fd = "아무것도 받지 않고 "
            } else {
                let fpd = typeDisplay(fp)
                fd = hcat(fpd, hObjParticle(fpd), " 받아 ")
            }
            var isAsync = false
            if hHas(inner, "asyncfn") { isAsync = true }
            if hHas(inner, "비동기로 반환") { isAsync = true }
            if fr == "void" {
                if isAsync { fd = hcat(fd, "비동기로 ") }
                return hcat(fd, "반환하지 않음")
            }
            let frd = typeDisplay(fr)
            fd = hcat(fd, frd, hObjParticle(frd))
            if isAsync { return hcat(fd, " 비동기로 반환") }
            return hcat(fd, " 반환")
        }
        if inner.hasPrefix("함수값") { return fnDisplayFind(inner) }
        if isChannelEndpointStruct(inner) { return channelEndpointDisplay(inner) }
        let optSuffix: BStr = "선택값"
        if inner.hasPrefix("struct:") {
            let sn = hSub(inner, 7, inner.count - 7)
            if isChannelEndpointStruct(sn) { return channelEndpointDisplay(sn) }
            if sn.hasSuffix(optSuffix) {
                let op = hSub(sn, 0, sn.count - optSuffix.count)
                let od = fnDisplayFind(op)
                if od != op { return hcat(od, "?") }
                return hcat(typeDisplay(op), "?")
            }
            if sn == "문자열배열동적배열형" { return "문자열의 배열" }
            let dyn: BStr = "동적배열형"
            if sn.hasSuffix(dyn) {
                let ed = hSub(sn, 0, sn.count - dyn.count)
                if ed.hasPrefix("함수값") { return hcat(fnDisplayFind(ed), "의 배열") }
                if ed.hasSuffix("배열") {
                    if isSurfaceDynArray(sn) {
                        let ip = hSub(ed, 0, ed.count - 6)
                        return hcat(typeDisplay(hcat("struct:", ip, dyn)), "의 배열")
                    }
                    return sn
                }
                return hcat(typeDisplay(ed), "의 배열")
            }
            return sn
        }
        if inner.hasSuffix(optSuffix) {
            let op = hSub(inner, 0, inner.count - optSuffix.count)
            let od = fnDisplayFind(op)
            if od != op { return hcat(od, "?") }
            return hcat(typeDisplay(op), "?")
        }
        if inner.hasPrefix("array<") && inner.hasSuffix(">") {
            return hcat(typeDisplay(fixedArrayElemType(inner)), " ", hDecU(fixedArrayLen(inner)), "개의 고정배열")
        }
        if hHas(inner, "개의 고정배열") {
            if let sp = hFind(inner, " ") {
                let es = hSub(inner, 0, sp)
                let rest = hSub(inner, sp, inner.count - sp)
                return hcat(typeDisplay(es), rest)
            }
        }
        switch inner {
        case "text": return "문자열"
        case "char": return "문자"
        case "bool": return "참거짓"
        case "address": return "주소"
        case "f32": return "실수32"
        case "f64": return "실수64"
        case "u8": return "자연수8"
        case "u16": return "자연수16"
        case "u32": return "자연수32"
        case "u64": return "큰자연수"
        case "i8": return "정수8"
        case "i16": return "정수16"
        case "i32": return "정수32"
        case "i64": return "큰정수"
        default: return inner
        }
    }

    // 정본: HMIR고정배열원소타입
    func fixedArrayElemType(_ t: BStr) -> BStr {
        if let sp = hFind(t, " "), hHas(t, "개의 고정배열") { return hSub(t, 0, sp) }
        if t.hasPrefix("array<") && t.hasSuffix(">") {
            let inner = hSub(t, 6, t.count - 7)
            if let c = hFind(inner, ",") { return hSub(inner, 0, c) }
        }
        return ""
    }

    // 정본: HMIR고정배열길이
    func fixedArrayLen(_ t: BStr) -> UInt64 {
        if let sp = hFind(t, " "), let mk = hFind(t, "개의 고정배열") {
            let st = sp + 1
            if let v = hParseU64(hSub(t, st, mk - st)) { return v }
        }
        if t.hasPrefix("array<") && t.hasSuffix(">") {
            let inner = hSub(t, 6, t.count - 7)
            if let c = hFind(inner, ",") {
                if let v = hParseU64(hSub(inner, c + 1, inner.count - c - 1)) { return v }
            }
        }
        return 0
    }

    // 정본: HMIR동적배열함수머리
    func dynArrayFnHead(_ t: BStr) -> BStr {
        var sn = typeResolve(t)
        if sn.hasPrefix("struct:") { sn = hSub(sn, 7, sn.count - 7) }
        let suf: BStr = "동적배열형"
        if sn.hasSuffix(suf) { return hSub(sn, 0, sn.count - suf.count) }
        return ""
    }
}
