//
//  MopeliumDesign.swift
//  MopeliumMac
//
//  Mopelium delegates its palette to macOS. The window canvas, content material,
//  separators, accent, and Liquid Glass all remain dynamic system resources;
//  no sampled or fixed light/dark background values live here.
//

#if canImport(SwiftUI)
import SwiftUI
import MopeliumSharedUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Color tokens

enum MopeliumTheme {
    static func deepText(_: ColorScheme) -> Color { .primary }
    static func softText(_: ColorScheme) -> Color { .secondary }
    static func tertiaryText(_: ColorScheme) -> Color { .secondary.opacity(0.72) }
    static func accent(_: ColorScheme) -> Color { .accentColor }

    static func separator(_: ColorScheme) -> Color {
        #if canImport(AppKit)
        return Color(nsColor: .separatorColor)
        #else
        return .secondary.opacity(0.28)
        #endif
    }

    static func selectedStroke(_: ColorScheme) -> Color {
        .accentColor.opacity(0.72)
    }
}

/// The native window surface. On current systems SwiftUI resolves
/// `windowBackground` from the active appearance, wallpaper tint, contrast,
/// transparency, and window state rather than from a fixed RGB value.
struct MopeliumSystemCanvas: View {
    @ViewBuilder var body: some View {
        if #available(macOS 14.0, *) {
            Rectangle().fill(.windowBackground)
        } else {
            legacyWindowBackground
        }
    }

    @ViewBuilder private var legacyWindowBackground: some View {
        #if canImport(AppKit)
        MopeliumLegacyWindowBackground()
        #else
        Rectangle().fill(.background)
        #endif
    }
}

#if canImport(AppKit)
/// macOS 13 fallback for the same semantic window material.
private struct MopeliumLegacyWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif

// MARK: - Typography

/// Compatibility name for existing macOS call sites. The role definitions
/// live in SharedUI so dormant compatibility views use the same nominal sizes, weights and font
/// designs while applying its own Dynamic Type scaling.
typealias MopeliumType = MopeliumTypography

extension MopeliumThreadStyle {
    static func mopeliumMac(_ scheme: ColorScheme) -> MopeliumThreadStyle {
        MopeliumThreadStyle(
            primaryText: MopeliumTheme.deepText(scheme),
            secondaryText: MopeliumTheme.softText(scheme),
            tertiaryText: MopeliumTheme.tertiaryText(scheme),
            accent: MopeliumTheme.accent(scheme),
            stroke: MopeliumTheme.separator(scheme),
            cardStroke: MopeliumTheme.separator(scheme),
            error: .red)
    }
}

// MARK: - Native content surfaces

private struct MopeliumCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(.regularMaterial, in: shape)
            .overlay {
                shape.stroke(MopeliumTheme.separator(scheme), lineWidth: 1)
            }
    }
}

extension View {
    func mopeliumCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(MopeliumCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Shared header

/// Page header: a serif title plus a system-secondary subtitle.
struct MopeliumPageHeader: View {
    let title: String
    var subtitle: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(MopeliumType.largeTitle(30))
                .foregroundStyle(MopeliumTheme.deepText(scheme))
            if let subtitle {
                Text(subtitle)
                    .font(MopeliumType.caption(13, .medium))
                    .foregroundStyle(MopeliumTheme.softText(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
