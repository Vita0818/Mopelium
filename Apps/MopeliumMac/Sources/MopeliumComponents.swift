#if canImport(SwiftUI)
import SwiftUI

struct MopeliumPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    private let trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(MopeliumType.largeTitle(30))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                Text(subtitle)
                    .font(MopeliumType.caption(13, .medium))
                    .foregroundStyle(MopeliumTheme.secondaryText(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
    }
}

extension MopeliumPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct MopeliumGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var contentPadding: CGFloat = 20
    private let content: Content
    @Environment(\.colorScheme) private var scheme

    init(cornerRadius: CGFloat = 22, contentPadding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(contentPadding)
            .background {
                shape.fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.38 : 0.62))
            }
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.stroke(MopeliumTheme.stroke(scheme).opacity(scheme == .dark ? 0.65 : 0.85), lineWidth: 1)
            }
            .shadow(
                color: MopeliumTheme.shadow(scheme).opacity(scheme == .dark ? 0.18 : 0.10),
                radius: 16,
                x: 0,
                y: 9
            )
    }
}

struct MopeliumStatusBadge: View {
    let status: MopeliumStatus
    let label: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(label)
            .font(MopeliumType.caption(11, .semibold))
            .foregroundStyle(MopeliumTheme.statusColor(status))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(MopeliumTheme.statusFill(status, scheme))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(MopeliumTheme.statusStroke(status, scheme), lineWidth: 1)
            }
    }
}

struct MopeliumComposer: View {
    @Binding var text: String
    var placeholder: String
    var isBusy: Bool = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    private var canSubmit: Bool {
        !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(MopeliumType.body(15))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit {
                        if canSubmit { onSubmit() }
                    }
                    .disabled(isBusy)

                Button(action: {}) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Provider options are loaded from Mopelium config")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                Capsule(style: .continuous)
                    .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.34 : 0.68))
            }
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(MopeliumTheme.stroke(scheme).opacity(0.82), lineWidth: 1)
            }

            Button(action: {
                if canSubmit { onSubmit() }
            }) {
                ZStack {
                    Circle()
                        .fill(
                            canSubmit
                                ? AnyShapeStyle(LinearGradient(colors: [MopeliumTheme.accentSoft, MopeliumTheme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(MopeliumTheme.surface(scheme).opacity(0.55))
                        )
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(canSubmit ? MopeliumTheme.textOnAccent : MopeliumTheme.tertiaryText(scheme))
                    }
                }
                .frame(width: 40, height: 40)
                .shadow(
                    color: MopeliumTheme.accent.opacity(canSubmit && scheme == .light ? 0.24 : 0),
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .help("Static send control")
        }
    }
}

struct MopeliumIconBadge: View {
    let systemName: String
    var status: MopeliumStatus = .local
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MopeliumTheme.statusFill(status, scheme))
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MopeliumTheme.statusColor(status))
        }
        .frame(width: 42, height: 42)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MopeliumTheme.statusStroke(status, scheme), lineWidth: 1)
        }
    }
}

struct MopeliumSidebarRow: View {
    let section: MopeliumSection
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: section.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? MopeliumTheme.accentDeep : MopeliumTheme.secondaryText(scheme))
                .frame(width: 20)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(section.title)
                    .font(MopeliumType.body(13, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? MopeliumTheme.primaryText(scheme) : MopeliumTheme.secondaryText(scheme))
                Text(section.gloss)
                    .font(MopeliumType.caption(12, .regular))
                    .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(MopeliumTheme.sidebarFill(selected: selected, hovering: hovering, scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(MopeliumTheme.accent.opacity(scheme == .dark ? 0.38 : 0.44), lineWidth: 1)
                .opacity(selected ? 1 : (hovering ? 0.38 : 0))
        }
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onHover { hovering = $0 }
    }
}

struct MopeliumSettingRow: View {
    let title: String
    let detail: String
    let value: String
    var isSensitive: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(MopeliumType.caption(12, .semibold))
                .foregroundStyle(MopeliumTheme.secondaryText(scheme))

            HStack(spacing: 10) {
                TextField(title, text: .constant(displayValue))
                    .textFieldStyle(.plain)
                    .disabled(true)
                    .font(MopeliumType.mono(13))
                    .foregroundStyle(MopeliumTheme.primaryText(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(1)
                Text(detail)
                    .font(MopeliumType.caption(11, .medium))
                    .foregroundStyle(MopeliumTheme.tertiaryText(scheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MopeliumTheme.surface(scheme).opacity(scheme == .dark ? 0.30 : 0.70))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MopeliumTheme.stroke(scheme).opacity(0.78), lineWidth: 1)
            }
        }
    }

    private var displayValue: String {
        isSensitive ? "Not stored" : value
    }
}

struct MopeliumEmptyState: View {
    let title: String
    let message: String
    let systemName: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            MopeliumIconBadge(systemName: systemName, status: .local)
                .frame(width: 52, height: 52)
            Text(title)
                .font(MopeliumType.title(21))
                .foregroundStyle(MopeliumTheme.primaryText(scheme))
            Text(message)
                .font(MopeliumType.body(14))
                .foregroundStyle(MopeliumTheme.secondaryText(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
