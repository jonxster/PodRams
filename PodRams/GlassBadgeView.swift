import SwiftUI

struct GlassBadgeView: View {
    let symbolName: String
    let title: String
    let subtitle: String?
    let tint: Color
    let namespace: Namespace.ID?
    let glassID: String?

    init(symbolName: String,
         title: String,
         subtitle: String? = nil,
         tint: Color = .accentColor,
         namespace: Namespace.ID? = nil,
         glassID: String? = nil) {
        self.symbolName = symbolName
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.namespace = namespace
        self.glassID = glassID
    }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(tint).interactive(), in: Circle())

            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(tint.opacity(0.6)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .glassEffect(.regular.tint(tint.opacity(0.35)), in: Capsule())
        .applyGlassIDIfNeeded(namespace: namespace, glassID: glassID)
    }
}

private extension View {
    @ViewBuilder
    func applyGlassIDIfNeeded(namespace: Namespace.ID?, glassID: String?) -> some View {
        if let namespace, let glassID {
            self.glassEffectID(glassID, in: namespace)
        } else {
            self
        }
    }
}
