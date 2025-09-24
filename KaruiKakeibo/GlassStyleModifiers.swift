import SwiftUI

public struct GlassRoundedBackgroundModifier: ViewModifier {
    public var cornerRadius: CGFloat = 16
    public var tint: Color = Color.blue.opacity(0.3)
    
    public init(cornerRadius: CGFloat = 16, tint: Color = Color.blue.opacity(0.3)) {
        self.cornerRadius = cornerRadius
        self.tint = tint
    }
    
    public func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .background(
                    EmptyView()
                        .glassEffect(.regular
                            .tint(tint)
                            .interactive(), in: .rect(cornerRadius: cornerRadius))
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)
        }
    }
}

public struct GlassCapsuleBackgroundModifier: ViewModifier {
    public var tint: Color = Color.blue.opacity(0.3)
    
    public init(tint: Color = Color.blue.opacity(0.3)) {
        self.tint = tint
    }
    
    public func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .background(
                    EmptyView()
                        .glassEffect(.regular
                            .tint(tint)
                            .interactive(), in: .capsule)
                )
        } else {
            content
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)
        }
    }
}

public extension View {
    func glassRoundedBackground(cornerRadius: CGFloat = 16, tint: Color = .blue.opacity(0.3)) -> some View {
        modifier(GlassRoundedBackgroundModifier(cornerRadius: cornerRadius, tint: tint))
    }
    
    func glassCapsuleBackground(tint: Color = .blue.opacity(0.3)) -> some View {
        modifier(GlassCapsuleBackgroundModifier(tint: tint))
    }
}
