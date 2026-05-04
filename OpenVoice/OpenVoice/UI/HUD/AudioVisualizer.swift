import SwiftUI

/// Бары-эквалайзер с псевдо-волной: высота каждого бара модулируется
/// синусом со сдвигом фазы по индексу плюс реальный уровень микрофона.
/// Центральные бары визуально выше за счёт «поднятия серединой».
struct AudioVisualizer: View {
    let level: Float
    let isActive: Bool
    var color: Color = .primary

    private let barCount = 17
    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 2
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 22

    private var phases: [Double] {
        (0..<barCount).map { Double($0) * 0.45 }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(color.opacity(0.92))
                        .frame(width: barWidth, height: height(at: i, time: ctx.date.timeIntervalSinceReferenceDate))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func height(at index: Int, time: TimeInterval) -> CGFloat {
        guard isActive else { return minHeight }
        let amp = max(0, min(1, pow(Double(level), 0.7)))
        let wave = (sin(time * 7.5 + phases[index]) + 1) * 0.5
        let mid = Double(barCount - 1) / 2.0
        let centerness = 1.0 - abs(Double(index) - mid) / mid
        let boost = 0.55 + 0.45 * centerness
        let normalized = amp * wave * boost
        return max(minHeight, minHeight + CGFloat(normalized) * (maxHeight - minHeight))
    }
}

/// Статичные ровные бары — идл-состояние.
struct AudioVisualizerIdle: View {
    var color: Color = .primary
    private let barCount = 17
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { _ in
                Capsule().fill(color.opacity(0.4)).frame(width: 2.5, height: 3)
            }
        }
        .frame(height: 22)
    }
}
