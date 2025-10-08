import SwiftUI

/// Lightweight stand-ins for the upcoming Liquid Glass APIs so we can adopt the new styling
/// model while remaining compatible with macOS releases prior to Tahoe.
struct Glass {
    var tintColor: Color?
    var isInteractive = false

    static var regular: Glass { Glass() }

    func tint(_ color: Color) -> Glass {
        var copy = self
        copy.tintColor = color
        return copy
    }

    func interactive() -> Glass {
        var copy = self
        copy.isInteractive = true
        return copy
    }
}

struct DefaultGlassEffectShape: InsettableShape {
    func path(in rect: CGRect) -> Path { Capsule().path(in: rect) }
    func inset(by amount: CGFloat) -> DefaultGlassEffectShape { self }
}

/// Compatibility helpers that mimic the system glass effect on older OS versions and defer to
/// the native APIs on Tahoe.
private struct GlassEffectModifier<S: InsettableShape>: ViewModifier {
    let configuration: Glass
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 15.0, *) {
            content
                .glassEffect(configuration.isInteractive ? .regular.interactive() : .regular, in: shape)
        } else {
            fallback(content: content)
        }
        #else
        fallback(content: content)
        #endif
    }

    @ViewBuilder
    private func fallback(content: Content) -> some View {
        content
            .background(
                AppTheme.surface.opacity(0.92),
                in: shape
            )
            .overlay(
                shape
                    .stroke(AppTheme.secondaryText.opacity(configuration.isInteractive ? 0.35 : 0.18))
            )
            .overlay {
                if let tint = configuration.tintColor {
                    shape.fill(tint.opacity(0.25))
                }
            }
    }
}

extension View {
    @ViewBuilder
    func compatGlassEffect(_ glass: Glass = .regular) -> some View {
        compatGlassEffect(glass, in: DefaultGlassEffectShape())
    }

    @ViewBuilder
    func compatGlassEffect<S: InsettableShape>(_ glass: Glass = .regular, in shape: S) -> some View {
        modifier(GlassEffectModifier(configuration: glass, shape: shape))
    }

    func compatGlassEffectID<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        self
    }

    func compatGlassEffectUnion<ID: Hashable & Sendable>(id: ID, namespace: Namespace.ID) -> some View {
        self
    }

    func compatBackgroundExtensionEffect(_ edges: Edge.Set = [.leading, .trailing]) -> some View {
        self
            .padding(.leading, edges.contains(.leading) ? -48 : 0)
            .padding(.trailing, edges.contains(.trailing) ? -48 : 0)
            .padding(.top, edges.contains(.top) ? -32 : 0)
            .padding(.bottom, edges.contains(.bottom) ? -32 : 0)
            .clipped()
    }

    func compatGlassBackgroundEffect(_ area: GlassBackgroundArea = .window) -> some View {
        let radius: CGFloat = {
            switch area {
            case .window:
                return 20
            case .sidebar, .inspector:
                return 28
            }
        }()

        return self.background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }
}

/// Convenience container used in a few places to stack glass areas.
struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder private var content: () -> Content

    init(spacing: CGFloat = 0, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(spacing: spacing) {
            content()
        }
    }
}

// MARK: - Button styling

struct GlassButtonStyle: PrimitiveButtonStyle {
    struct Body: View {
        let configuration: Configuration
        let glass: Glass

        @GestureState private var isPressed = false

        var body: some View {
            configuration.label
                .compatGlassEffect(glass, in: Capsule())
                .scaleEffect(isPressed && glass.isInteractive ? 0.96 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isPressed)
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressed) { _, state, _ in
                            state = true
                        }
                        .onEnded { _ in
                            configuration.trigger()
                        }
                )
        }
    }

    let glass: Glass

    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration, glass: glass)
    }
}

extension PrimitiveButtonStyle where Self == GlassButtonStyle {
    static var compatGlass: GlassButtonStyle { GlassButtonStyle(glass: .regular) }
    static func compatGlass(_ glass: Glass) -> GlassButtonStyle { GlassButtonStyle(glass: glass) }
}

enum GlassBackgroundArea {
    case window
    case sidebar
    case inspector
}
