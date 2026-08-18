//
//  MopeliumDesign.swift
//  MopeliumMac
//
//  Mopelium's warm-neutral/champagne palette. Glass optics remain owned by
//  SwiftUI's native Liquid Glass APIs; these tokens only provide color.
//

#if canImport(SwiftUI)
import SwiftUI
import MopeliumSharedUI

// MARK: - Color tokens

enum MopeliumTheme {
    static let champagne = sRGB(0xECD8BB)
    static let champagneAccent = sRGB(0xBCA17F)

    static func deepText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? sRGB(0xF3EEE7) : sRGB(0x302A23)
    }

    static func softText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? sRGB(0xBFB4A6) : sRGB(0x736758)
    }

    static func tertiaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? sRGB(0x8E8171) : sRGB(0x948676)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? champagne : champagneAccent
    }

    static func pageGradient(_ scheme: ColorScheme) -> [Color] {
        scheme == .dark
            ? [sRGB(0x1A1815), sRGB(0x211E19), sRGB(0x1C1A17)]
            : [sRGB(0xFCFAF6), sRGB(0xF7EFE3), sRGB(0xFBF7F0)]
    }

    static func separator(_ scheme: ColorScheme) -> Color {
        let base = scheme == .dark ? sRGB(0xCBBBA5) : sRGB(0xDED0BE)
        return base.opacity(scheme == .dark ? 0.22 : 0.52)
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        let base = scheme == .dark ? sRGB(0xCBBBA5) : sRGB(0xDED0BE)
        return base.opacity(scheme == .dark ? 0.16 : 0.36)
    }

    static func selectedStroke(_ scheme: ColorScheme) -> Color {
        champagneAccent.opacity(scheme == .dark ? 0.46 : 0.38)
    }

    private static func sRGB(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1)
    }
}

/// The warm canvas sits behind system Material and native Liquid Glass.
struct MopeliumSystemCanvas: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle().fill(
            LinearGradient(
                colors: MopeliumTheme.pageGradient(scheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing))
    }
}

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
            cardStroke: MopeliumTheme.cardStroke(scheme),
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
                shape.stroke(MopeliumTheme.cardStroke(scheme), lineWidth: 1)
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
