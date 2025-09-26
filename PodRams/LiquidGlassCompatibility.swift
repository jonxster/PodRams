import SwiftUI

#if !swift(>=6.2)
/// Lightweight stand-ins for the upcoming Liquid Glass APIs so we can adopt the guidelines today.
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

/// Lightweight representation of the system’s glass background styles.
enum GlassBackgroundArea {
    case window
    case sidebar
    case inspector
}

private struct GlassEffectModifier<S: InsettableShape>: ViewModifier {
    let configuration: Glass
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content
            .background(AppTheme.surface, in: shape)
            .overlay(shape.stroke(AppTheme.secondaryText.opacity(configuration.isInteractive ? 0.25 : 0.12)))
        if let tint = configuration.tintColor {
            base.tint(tint)
        } else {
            base
        }
    }
}

extension View {
    func glassEffect(_ glass: Glass = .regular) -> some View {
        glassEffect(glass, in: DefaultGlassEffectShape())
    }

    func glassEffect<S: InsettableShape>(_ glass: Glass = .regular, in shape: S) -> some View {
        modifier(GlassEffectModifier(configuration: glass, shape: shape))
    }
}

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
                .glassEffect(glass, in: Capsule())
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
    static var glass: GlassButtonStyle { GlassButtonStyle(glass: .regular) }
    static func glass(_ glass: Glass) -> GlassButtonStyle { GlassButtonStyle(glass: glass) }
}

// MARK: - Glass identifiers & unions

extension View {
    func glassEffectID<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        self
    }

    func glassEffectNamespace(_ namespace: Namespace.ID) -> some View { self }

    func glassEffectUnion<ID: Hashable>(id: ID, namespace: Namespace.ID) -> some View {
        self
    }
}

// MARK: - Background extension effect

private struct BackgroundExtensionEffectModifier: ViewModifier {
    let edges: Edge.Set

    func body(content: Content) -> some View {
        content
            .padding(.leading, edges.contains(.leading) ? -48 : 0)
            .padding(.trailing, edges.contains(.trailing) ? -48 : 0)
            .padding(.top, edges.contains(.top) ? -32 : 0)
            .padding(.bottom, edges.contains(.bottom) ? -32 : 0)
            .clipped()
    }
}

extension View {
    func backgroundExtensionEffect(_ edges: Edge.Set = [.leading, .trailing]) -> some View {
        modifier(BackgroundExtensionEffectModifier(edges: edges))
    }

    func glassBackgroundEffect(_ area: GlassBackgroundArea = .window) -> some View {
        let radius: CGFloat
        switch area {
        case .window: radius = 20
        case .sidebar, .inspector: radius = 28
        }
        return background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

#endif
