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

/// «Стеклянная» пилюля в духе Apple Liquid Glass: ультратонкий материал
/// + верхний highlight, имитирующий преломление света на стекле, +
/// градиентная edge-обводка, придающая объём граням. На macOS 26+
/// автоматически заменяется на нативный `.glassEffect()` (когда выйдет
/// SDK — поправим единственное место).
struct GlassCapsule: View {
    var cornerRadius: CGFloat = 22
    var stroke: Bool = true
    var shadow: Bool = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            // 1. Базовый ультратонкий материал — основа стекла.
            shape.fill(.ultraThinMaterial)

            // 2. Верхний светлый highlight: имитирует свет, преломляющийся
            //    через стеклянный край сверху.
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            .blendMode(.plusLighter)

            // 3. Нижнее лёгкое затемнение — даёт «толщину» стеклу.
            shape.fill(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.05)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            )

            // 4. Двухтоновая обводка: яркий блик сверху-слева, мягкая
            //    тёмная грань снизу-справа.
            if stroke {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(shadow ? 0.25 : 0), radius: 16, x: 0, y: 6)
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
