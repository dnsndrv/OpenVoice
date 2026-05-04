import AppKit
import Combine
import SwiftUI

/// Плавающая стеклянная пилюля, прижатая к верху экрана с зазором
/// от меню-бара. Появляется только когда есть что показать (запись /
/// расшифровка / вставка / ошибка) — в idle полностью прячется.
@MainActor
final class RecordingHUDController {
    private let panel: NSPanel
    private let viewModel: HUDViewModel
    private var cancellables = Set<AnyCancellable>()

    private let panelWidth: CGFloat = 320
    private let panelHeight: CGFloat = 64

    init(coordinator: RecordingCoordinator, recorder: AudioRecorder) {
        let vm = HUDViewModel()
        self.viewModel = vm

        let view = HUDPillView(viewModel: vm)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Системная тень окна следует за альфа-маской контента — поэтому
        // тень получается ровно по форме нашей пилюли, без квадратных
        // артефактов, которые даёт SwiftUI .shadow на borderless панели.
        panel.hasShadow = true
        panel.contentView = hosting
        panel.ignoresMouseEvents = true
        self.panel = panel

        coordinator.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.apply(state: state) }
            .store(in: &cancellables)

        recorder.levelPublisher
            .receive(on: RunLoop.main)
            .sink { [weak vm] level in vm?.level = level }
            .store(in: &cancellables)
    }

    private func apply(state: RecordingCoordinator.State) {
        viewModel.state = state
        switch state {
        case .recording:
            viewModel.startedAt = Date()
            show()
        case .transcribing, .injecting, .error:
            show()
        case .idle:
            hide()
        }
    }

    private func show() {
        if !panel.isVisible {
            positionPanel()
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 1
            }
        }
    }

    private func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            if case .idle = self.viewModel.state { self.panel.orderOut(nil) }
        })
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let bottomGap: CGFloat = 24
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + bottomGap
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var state: RecordingCoordinator.State = .idle
    @Published var level: Float = 0
    @Published var startedAt: Date = Date()
}

// MARK: - View

private struct HUDPillView: View {
    @ObservedObject var viewModel: HUDViewModel
    @State private var now = Date()
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        // Контент полностью заполняет panel — это критично, чтобы системная
        // тень окна (panel.hasShadow=true) совпадала с альфа-формой пилюли,
        // а не оставляла прямоугольный ореол по углам panel'а.
        ZStack {
            GlassCapsule(cornerRadius: 18, shadow: false)
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .onReceive(timer) { now = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .recording:
            HStack(spacing: 10) {
                PulsingDot(color: .red)
                AudioVisualizer(level: viewModel.level, isActive: true)
                Spacer(minLength: 4)
                Text(elapsed)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        case .transcribing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Расшифровка")
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
        case .injecting:
            HStack(spacing: 10) {
                Image(systemName: "text.cursor").foregroundStyle(.tint)
                Text("Вставка")
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
        case .error(let msg):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        case .idle:
            EmptyView()
        }
    }

    private var elapsed: String {
        let s = max(0, Int(now.timeIntervalSince(viewModel.startedAt)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

private struct PulsingDot: View {
    let color: Color
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .opacity(pulse ? 1.0 : 0.45)
            .scaleEffect(pulse ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
