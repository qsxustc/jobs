import SwiftUI

enum AppMotion {
    /// Pointer and press feedback should feel immediate on macOS.
    static let quick = Animation.spring(response: 0.16, dampingFraction: 0.86)
    /// Default transition for small layout and data changes.
    static let standard = Animation.spring(response: 0.28, dampingFraction: 0.88)
    /// Used when content moves between larger regions, such as kanban columns.
    static let emphasized = Animation.spring(response: 0.36, dampingFraction: 0.84)
}

struct ResponsivePlainButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : AppMotion.quick, value: configuration.isPressed)
    }
}

private struct InteractiveCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    let scale: CGFloat
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered && !reduceMotion ? scale : 1)
            .offset(y: isHovered && !reduceMotion ? -1 : 0)
            .shadow(
                color: .black.opacity(isHovered ? shadowOpacity : 0),
                radius: isHovered ? 9 : 0,
                y: isHovered ? 4 : 0
            )
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : AppMotion.quick, value: isHovered)
    }
}

extension View {
    /// A restrained hover response for clickable card-like surfaces.
    func interactiveCard(scale: CGFloat = 1.008, shadowOpacity: Double = 0.1) -> some View {
        modifier(InteractiveCardModifier(scale: scale, shadowOpacity: shadowOpacity))
    }
}

extension ApplicationStatus {
    var color: Color {
        switch self {
        case .evaluating: return .gray
        case .toApply: return .indigo
        case .applied: return .blue
        case .screening: return .cyan
        case .assessment: return .orange
        case .interviewing: return .purple
        case .waiting: return .yellow
        case .offer, .accepted: return .green
        case .rejected: return .red
        case .withdrawn, .closed: return .secondary
        }
    }
}

extension ApplicationAnalysisCategory {
    var color: Color {
        switch self {
        case .notSubmitted: return .indigo
        case .submitted: return .blue
        case .interview: return .purple
        case .offer: return .green
        case .ended: return .gray
        }
    }
}

extension Priority {
    var color: Color {
        switch self {
        case .low: return .secondary
        case .medium: return .blue
        case .high: return .orange
        }
    }
}

extension Color {
    static func jobColor(_ key: String) -> Color {
        switch key {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray": return .gray
        default: return .indigo
        }
    }
}

struct StatusPill: View {
    let status: ApplicationStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}

struct EffectiveStatusPill: View {
    @EnvironmentObject private var store: AppStore
    let application: JobApplication

    var body: some View {
        if let stage = store.customStage(id: application.customStageID) {
            let color = Color.jobColor(stage.colorKey)
            Text(stage.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
        } else {
            StatusPill(status: application.status)
        }
    }
}

struct TagPill: View {
    let tag: JobTag

    var body: some View {
        let color = Color.jobColor(tag.colorKey)
        Text(tag.name)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct PriorityPill: View {
    let priority: Priority

    var body: some View {
        Label(priority.rawValue, systemImage: "flag.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(priority.color)
    }
}

struct MetricCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : AppMotion.standard, value: value)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(message))
            .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct LargeTextEditor: View {
    @Binding var text: String
    let minimumHeight: CGFloat
    var placeholder: String?

    init(text: Binding<String>, minimumHeight: CGFloat, placeholder: String? = nil) {
        _text = text
        self.minimumHeight = minimumHeight
        self.placeholder = placeholder
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)

            if text.isEmpty, let placeholder {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minimumHeight)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .padding(.vertical, 3)
    }
}

struct CompanyAvatar: View {
    let name: String
    var size: CGFloat = 36

    private var initials: String {
        String(name.prefix(2))
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.30, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [.indigo, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.28)
            )
    }
}

struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
    }
}
