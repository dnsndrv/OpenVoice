import AppKit
import SwiftUI

/// Полупрозрачная подложка с системной vibrancy. На macOS 26+ автоматически
/// получает настоящий Liquid Glass; на 15.x работает поверх `NSVisualEffectView`.
///
/// `material`/`blending` передаются напрямую системе. Для окон
/// (под titlebar) используется `.behindWindow`, для всплывающих
/// панелей и HUD — `.withinWindow`.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = emphasized
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        v.isEmphasized = emphasized
    }
}

/// «Стеклянная» пилюля: материал + тонкая светлая обводка + мягкая тень.
/// Используется как фон HUD и других плавающих элементов. На macOS 26+
/// заменяется на `glassEffect()` если он доступен.
struct GlassCapsule: View {
    var cornerRadius: CGFloat = 22
    var material: Material = .regularMaterial
    var stroke: Bool = true
    var shadow: Bool = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(material)
            if stroke {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(shadow ? 0.28 : 0), radius: 18, x: 0, y: 6)
    }
}

extension View {
    /// Прозрачный фон формы/списка, чтобы под ним просвечивал glass.
    @ViewBuilder
    func clearScrollBackground() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
