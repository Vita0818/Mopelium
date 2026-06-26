#if canImport(SwiftUI)
import SwiftUI

enum MopeliumStatus: String, CaseIterable, Identifiable {
    case queued
    case running
    case done
    case failed
    case local
    case enabled
    case disabled

    var id: String { rawValue }
}

enum MopeliumTheme {
    static let accent = Color(red: 0.365, green: 0.663, blue: 0.741)
    static let accentSoft = Color(red: 0.741, green: 0.894, blue: 0.929)
    static let accentDeep = Color(red: 0.153, green: 0.420, blue: 0.510)

    static let backgroundTop = Color(red: 0.976, green: 0.972, blue: 0.953)
    static let backgroundBottom = Color(red: 0.929, green: 0.953, blue: 0.957)
    static let backgroundTopDark = Color(red: 0.066, green: 0.071, blue: 0.073)
    static let backgroundBottomDark = Color(red: 0.086, green: 0.098, blue: 0.102)

    static let statusQueued = Color(red: 0.494, green: 0.553, blue: 0.604)
    static let statusRunning = Color(red: 0.317, green: 0.604, blue: 0.749)
    static let statusDone = Color(red: 0.251, green: 0.565, blue: 0.420)
    static let statusFailed = Color(red: 0.760, green: 0.314, blue: 0.302)

    static let textOnAccent = Color.white

    static func pageGradient(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                scheme == .dark ? backgroundTopDark : backgroundTop,
                scheme == .dark ? backgroundBottomDark : backgroundBottom,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.120, green: 0.128, blue: 0.126)
            : Color(red: 1.000, green: 0.996, blue: 0.980)
    }

    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.255, green: 0.314, blue: 0.318)
            : Color(red: 0.810, green: 0.843, blue: 0.835)
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.905, green: 0.914, blue: 0.898)
            : Color(red: 0.090, green: 0.102, blue: 0.098)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.680, green: 0.706, blue: 0.690)
            : Color(red: 0.365, green: 0.400, blue: 0.392)
    }

    static func tertiaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.475, green: 0.506, blue: 0.500)
            : Color(red: 0.573, green: 0.604, blue: 0.596)
    }

    static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black : Color(red: 0.416, green: 0.537, blue: 0.545)
    }

    static func statusColor(_ status: MopeliumStatus) -> Color {
        switch status {
        case .queued:
            return statusQueued
        case .running, .local:
            return statusRunning
        case .done, .enabled:
            return statusDone
        case .failed:
            return statusFailed
        case .disabled:
            return statusQueued
        }
    }

    static func statusFill(_ status: MopeliumStatus, _ scheme: ColorScheme) -> Color {
        statusColor(status).opacity(scheme == .dark ? 0.18 : 0.12)
    }

    static func statusStroke(_ status: MopeliumStatus, _ scheme: ColorScheme) -> Color {
        statusColor(status).opacity(scheme == .dark ? 0.38 : 0.30)
    }

    static func sidebarFill(selected: Bool, hovering: Bool, _ scheme: ColorScheme) -> AnyShapeStyle {
        if selected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        accentSoft.opacity(scheme == .dark ? 0.20 : 0.58),
                        accent.opacity(scheme == .dark ? 0.14 : 0.20),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(surface(scheme).opacity(hovering ? (scheme == .dark ? 0.24 : 0.52) : 0))
    }
}

enum MopeliumType {
    static func brand(_ size: CGFloat = 29, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func largeTitle(_ size: CGFloat = 30, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func title(_ size: CGFloat = 20, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func headline(_ size: CGFloat = 16, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    static func body(_ size: CGFloat = 14, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func caption(_ size: CGFloat = 12, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func button(_ size: CGFloat = 14, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
}
#endif
