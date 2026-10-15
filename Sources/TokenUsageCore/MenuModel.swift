public enum MenuAction: Equatable, Sendable { case refreshNow, quit }

public enum MenuLine: Equatable, Sendable {
    case info(String)
    case header(String)
    case separator
    case action(String, MenuAction)

    public var text: String? {
        switch self {
        case .info(let s), .header(let s), .action(let s, _): return s
        case .separator: return nil
        }
    }
}

public struct MenuModel: Equatable, Sendable {
    public let title: String
    public let iconSymbolName: String
    public let iconIsTemplate: Bool
    public let lines: [MenuLine]

    public init(title: String, iconSymbolName: String, iconIsTemplate: Bool, lines: [MenuLine]) {
        self.title = title
        self.iconSymbolName = iconSymbolName
        self.iconIsTemplate = iconIsTemplate
        self.lines = lines
    }
}
