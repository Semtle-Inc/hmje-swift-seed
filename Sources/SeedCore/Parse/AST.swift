// 파싱 AST. 자립 파서(프론트엔드/문장파서.hmje)는 노드를 `{"kind", "fields"}` 모양의
// JSON값으로 만들고 그 모양 그대로 되읽고 고친다(파싱노드필드교체·파싱대상변환 등).
// 씨앗도 같은 모양을 **타입 있는** 트리로 둔다: 노드 = 종류 + 순서 있는 필드, 필드 값은
// 아래 ASTValue의 닫힌 경우들이다. JSON 방출(hmje-parsed-ast-v1)은 이 트리의 직렬화다.

/// 파서가 만드는 노드 종류(방출 이름 = rawValue). 리터럴로 쓸 수 있고, 모르는 이름은 즉시 멈춘다.
public enum NodeKind: String, CaseIterable, ExpressibleByStringLiteral {
    case AddressOfExpr
    case ArrayBufferViewExpr
    case ArrayLiteral
    case Assign
    case AwaitExpr
    case BinaryExpr
    case BoolExprCondition
    case BoolLiteral
    case Break
    case CallExpr
    case CastExpr
    case ChannelAsyncReceiveExpr
    case ChannelAsyncSendExpr
    case ChannelReceiveExpr
    case ChannelTrySendExpr
    case CompareCondition
    case ConcurrentBlock
    case Continue
    case DeadlineBlock
    case DeferredDefaultExpr
    case Define
    case DynamicArrayAppend
    case DynamicArrayClear
    case DynamicArrayInsert
    case DynamicArrayPopExpr
    case DynamicArrayRemove
    case DynamicArrayReserve
    case EnumDef
    case Execute
    case ExprStmt
    case ExternalGlobal
    case FieldAccessExpr
    case FieldTarget
    case FileDataExpr
    case FixedArrayFillExpr
    case FloatLiteral
    case ForEach
    case Forget
    case FunctionAddressExpr
    case FunctionDef
    case FunctionValueDefine
    case GlobalDefine
    case If
    case Import
    case IndexAccessExpr
    case IndexTarget
    case IntLiteral
    case LogicalCondition
    case ManualRelease
    case MemoryReadExpr
    case MemoryTarget
    case ModuleImport
    case MoveDefine
    case NameExpr
    case NameTarget
    case NotCondition
    case OffsetMemoryReadExpr
    case OffsetMemoryTarget
    case OptionalBindCondition
    case OptionalHasValueCondition
    case OptionalNoneExpr
    case OptionalUnwrapExpr
    case OverlayBindExpr
    case Parameter
    case PinAddress
    case PreemptDisableBlock
    case ReferenceDefine
    case Return
    case StringLiteral
    case StructDef
    case StructFieldMetadata
    case StructInitExpr
    case Switch
    case TraitDef
    case TraitRequirement
    case TransferOwnership
    case TryBlock
    case TryExpr
    case UnaryExpr
    case UnsafeBlock
    case UnstructuredTaskStart
    case While
    case LoopModifierDef
    case BlockModifierDef
    case BorrowDefine
    case TakeDefine

    public init(stringLiteral v: String) {
        guard let k = NodeKind(rawValue: v) else { fatalError("알 수 없는 노드 종류: \(v)") }
        self = k
    }
}

public struct ASTNode {
    public var kind: NodeKind
    public var fields: [(String, ASTValue)]

    public init(_ kind: NodeKind, _ fields: [(String, ASTValue)]) {
        self.kind = kind
        self.fields = fields
    }

    /// 파싱JSON필드 / 파싱AST필드: 없으면 널.
    public subscript(_ key: String) -> ASTValue {
        for (k, v) in fields where k == key { return v }
        return .null
    }

    public func has(_ key: String) -> Bool { fields.contains { $0.0 == key } }

    /// 파싱AST문자필드: 문자열이 아니면 "".
    public func str(_ key: String) -> BStr {
        if case .str(let s) = self[key] { return s }
        return ""
    }

    /// 파싱노드필드교체: 이름이 있을 때만 값을 바꾼다(순서 보존).
    public func replacing(_ key: String, with value: ASTValue) -> ASTNode {
        var n = self
        for i in n.fields.indices where n.fields[i].0 == key { n.fields[i].1 = value }
        return n
    }
}

/// 한 줄 문장: 방출 모양은 `[{"integer": "<줄>"}, 노드]`.
public struct LineStmt {
    public var line: Int
    public var node: ASTNode
    public init(_ line: Int, _ node: ASTNode) {
        self.line = line
        self.node = node
    }
}

public indirect enum ASTValue {
    case null
    case bool(Bool)
    case str(BStr)
    /// `{"integer": "<십진>"}` — 정수 리터럴·줄 번호·정렬값.
    case int(BStr)
    /// `{"float": "<원문>"}`
    case float(BStr)
    /// `{"enum": 종류, "value": 값}` — 가시성 등.
    case enumTag(String, String)
    case array([ASTValue])
    /// 순서 있는 객체(구조체 필드 표, 구조체 생성 필드).
    case object([(BStr, ASTValue)])
    case node(ASTNode)
    /// 줄 문장 목록(본문).
    case stmts([LineStmt])

    public var isNull: Bool { if case .null = self { return true }; return false }

    public var nodeValue: ASTNode? { if case .node(let n) = self { return n }; return nil }

    /// 파싱AST종류: 노드가 아니면 "".
    public var kind: NodeKind? { nodeValue?.kind }

    public func str(_ key: String) -> BStr { nodeValue?.str(key) ?? "" }
    public subscript(_ key: String) -> ASTValue { nodeValue?[key] ?? .null }
}

// MARK: - 짧은 생성자 (파싱AST노드)

@inline(__always) func N(_ kind: NodeKind, _ fields: [(String, ASTValue)]) -> ASTValue {
    .node(ASTNode(kind, fields))
}
@inline(__always) func S(_ s: BStr) -> ASTValue { .str(s) }
@inline(__always) func B(_ b: Bool) -> ASTValue { .bool(b) }
@inline(__always) func NameExpr(_ name: BStr, generated: Bool = false) -> ASTValue {
    N("NameExpr", [("name", S(name)), ("compiler_generated", B(generated))])
}
@inline(__always) func CallExpr(_ name: BStr, _ args: [ASTValue], generated: Bool = false) -> ASTValue {
    N("CallExpr", [("name", S(name)), ("args", .array(args)), ("compiler_generated", B(generated))])
}
@inline(__always) func IntLit(_ v: Int) -> ASTValue { N("IntLiteral", [("value", .int(BStr(decimal: v)))]) }
@inline(__always) func Visibility(_ v: String) -> ASTValue { .enumTag("Visibility", v) }

// MARK: - JSON 방출

public enum ASTJSON {
    public static func document(_ stmts: [LineStmt]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(1 << 16)
        put(&out, "{\"format\":\"hmje-parsed-ast-v1\",\"statements\":")
        emitStmts(&out, stmts)
        put(&out, "}\n")
        return String(decoding: out, as: UTF8.self)
    }

    static func put(_ o: inout [UInt8], _ s: StaticString) {
        s.withUTF8Buffer { o.append(contentsOf: $0) }
    }

    static func emitString(_ o: inout [UInt8], _ bytes: UnsafeBufferPointer<UInt8>) {
        o.append(34)
        for c in bytes {
            switch c {
            case 34: o.append(92); o.append(34)
            case 92: o.append(92); o.append(92)
            case 10: o.append(92); o.append(110)
            case 13: o.append(92); o.append(114)
            case 9: o.append(92); o.append(116)
            case 8: o.append(92); o.append(98)
            case 12: o.append(92); o.append(102)
            case 0..<32:
                let hex: [UInt8] = Array("0123456789abcdef".utf8)
                o.append(contentsOf: [92, 117, 48, 48, hex[Int(c >> 4)], hex[Int(c & 15)]])
            default: o.append(c)
            }
        }
        o.append(34)
    }

    static func emitString(_ o: inout [UInt8], _ s: BStr) { s.withBytes { emitString(&o, $0) } }
    static func emitString(_ o: inout [UInt8], _ s: String) {
        var s = s
        s.withUTF8 { emitString(&o, $0) }
    }

    static func emitStmts(_ o: inout [UInt8], _ stmts: [LineStmt]) {
        o.append(91)
        for (i, st) in stmts.enumerated() {
            if i > 0 { o.append(44) }
            put(&o, "[{\"integer\":\"")
            o.append(contentsOf: Array(String(st.line).utf8))
            put(&o, "\"},")
            emitNode(&o, st.node)
            o.append(93)
        }
        o.append(93)
    }

    static func emitNode(_ o: inout [UInt8], _ n: ASTNode) {
        put(&o, "{\"kind\":")
        emitString(&o, n.kind.rawValue)
        put(&o, ",\"fields\":{")
        for (i, (k, v)) in n.fields.enumerated() {
            if i > 0 { o.append(44) }
            emitString(&o, k)
            o.append(58)
            emit(&o, v)
        }
        put(&o, "}}")
    }

    static func emit(_ o: inout [UInt8], _ v: ASTValue) {
        switch v {
        case .null: put(&o, "null")
        case .bool(let b): if b { put(&o, "true") } else { put(&o, "false") }
        case .str(let s): emitString(&o, s)
        case .int(let s): put(&o, "{\"integer\":"); emitString(&o, s); o.append(125)
        case .float(let s): put(&o, "{\"float\":"); emitString(&o, s); o.append(125)
        case .enumTag(let k, let val):
            put(&o, "{\"enum\":"); emitString(&o, k); put(&o, ",\"value\":"); emitString(&o, val); o.append(125)
        case .array(let a):
            o.append(91)
            for (i, x) in a.enumerated() {
                if i > 0 { o.append(44) }
                emit(&o, x)
            }
            o.append(93)
        case .object(let kv):
            o.append(123)
            for (i, (k, x)) in kv.enumerated() {
                if i > 0 { o.append(44) }
                emitString(&o, k)
                o.append(58)
                emit(&o, x)
            }
            o.append(125)
        case .node(let n): emitNode(&o, n)
        case .stmts(let s): emitStmts(&o, s)
        }
    }
}
