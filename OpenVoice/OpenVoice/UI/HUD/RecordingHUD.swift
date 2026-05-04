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

    private let panelWidth: CGFloat = 520
    private let panelHeight: CGFloat = 96

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
        panel.hasShadow = false
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
        let frame = screen.frame
        let menubar = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let topGap: CGFloat = 14
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - menubar - topGap - size.height
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
        ZStack {
            GlassCapsule(cornerRadius: 24)
            content
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        .padding(8) // оставим место под shadow, чтобы не клиппилось panel'ом
        .onReceive(timer) { now = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .recording:
            HStack(spacing: 14) {
                PulsingDot(color: .red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Идёт запись")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    AudioVisualizer(level: viewModel.level, isActive: true,
                                    color: .primary)
                }
                Spacer(minLength: 8)
                Text(elapsed)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        case .transcribing:
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Расшифровка").font(.system(size: 13, weight: .semibold))
                    Text("Whisper обрабатывает аудио…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
        case .injecting:
            HStack(spacing: 14) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Вставляю текст").font(.system(size: 13, weight: .semibold))
                    Text("В активное приложение").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
        case .error(let msg):
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ошибка").font(.system(size: 13, weight: .semibold))
                    Text(msg).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
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
