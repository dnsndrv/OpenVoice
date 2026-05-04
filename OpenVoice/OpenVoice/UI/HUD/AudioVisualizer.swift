import SwiftUI

/// Плавная аудио-волна: бары размещаются по всей доступной ширине,
/// высота каждого бара модулируется псевдо-шумом + реальным уровнем
/// микрофона. Центральные бары визуально выше: создаёт «дыхание»
/// волны от середины к краям, как в системных рекордерах macOS.
struct AudioVisualizer: View {
    let level: Float
    let isActive: Bool
    var color: Color = .primary
    /// Желательная плотность баров: примерно 1 бар на N точек ширины.
    var density: CGFloat = 7
    var minHeight: CGFloat = 3
    var maxHeight: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let count = max(12, Int(geo.size.width / density))
            let totalCount = CGFloat(count)
            let barWidth: CGFloat = 2.5
            let spacing = max(1, (geo.size.width - barWidth * totalCount) / max(1, totalCount - 1))

            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule(style: .continuous)
                            .fill(color.opacity(0.92))
                            .frame(
                                width: barWidth,
                                height: barHeight(
                                    at: i,
                                    of: count,
                                    time: ctx.date.timeIntervalSinceReferenceDate
                                )
                            )
                    }
                }
                .frame(height: maxHeight, alignment: .center)
            }
        }
        .frame(height: maxHeight)
    }

    private func barHeight(at index: Int, of count: Int, time: TimeInterval) -> CGFloat {
        guard isActive else { return minHeight }
        let amp = max(0, min(1, pow(Double(level), 0.7)))
        // Псевдо-волна: смещение фазы по индексу + два разных периода
        // дают более органичное «дыхание» вместо монотонной синусоиды.
        let phase = Double(index) * 0.42
        let wave = (sin(time * 6.5 + phase) + sin(time * 2.7 + phase * 0.5)) * 0.25 + 0.5
        let mid = Double(count - 1) / 2.0
        let centerness = 1.0 - abs(Double(index) - mid) / mid
        let boost = 0.5 + 0.5 * centerness
        let normalized = amp * wave * boost
        return max(minHeight, minHeight + CGFloat(normalized) * (maxHeight - minHeight))
    }
}

/// Статичные ровные бары — idle-состояние.
struct AudioVisualizerIdle: View {
    var color: Color = .primary
    var body: some View {
        GeometryReader { geo in
            let count = max(12, Int(geo.size.width / 7))
            let totalCount = CGFloat(count)
            let barWidth: CGFloat = 2.5
            let spacing = max(1, (geo.size.width - barWidth * totalCount) / max(1, totalCount - 1))
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { _ in
                    Capsule().fill(color.opacity(0.4)).frame(width: barWidth, height: 3)
                }
            }
            .frame(height: 24)
        }
        .frame(height: 24)
    }
}
