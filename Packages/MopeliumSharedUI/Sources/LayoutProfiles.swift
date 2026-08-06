#if canImport(SwiftUI)
import SwiftUI

public struct MopeliumSplitColumnLayout: Equatable {
    public var sidebarMin: CGFloat
    public var sidebarIdeal: CGFloat
    public var contentMin: CGFloat
    public var contentIdeal: CGFloat
    public var detailMin: CGFloat
    public var detailIdeal: CGFloat

    public init(sidebarMin: CGFloat,
                sidebarIdeal: CGFloat,
                contentMin: CGFloat,
                contentIdeal: CGFloat,
                detailMin: CGFloat,
                detailIdeal: CGFloat) {
        self.sidebarMin = sidebarMin
        self.sidebarIdeal = sidebarIdeal
        self.contentMin = contentMin
        self.contentIdeal = contentIdeal
        self.detailMin = detailMin
        self.detailIdeal = detailIdeal
    }

    public static let chatInspector = MopeliumSplitColumnLayout(
        sidebarMin: 160,
        sidebarIdeal: 210,
        contentMin: 300,
        contentIdeal: 560,
        detailMin: 210,
        detailIdeal: 300)

    public static let workspace = MopeliumSplitColumnLayout(
        sidebarMin: 150,
        sidebarIdeal: 200,
        contentMin: 320,
        contentIdeal: 600,
        detailMin: 220,
        detailIdeal: 300)
}

public struct ThreeColumnShellLayout: Equatable {
    public enum Presentation: Equatable {
        case split
        case threadOnly
    }

    public var presentation: Presentation
    public var columns: MopeliumSplitColumnLayout

    public init(presentation: Presentation = .split,
                columns: MopeliumSplitColumnLayout = .chatInspector) {
        self.presentation = presentation
        self.columns = columns
    }

    public static let split = ThreeColumnShellLayout()
    public static let iOSChat = ThreeColumnShellLayout(presentation: .threadOnly)
}
#endif
