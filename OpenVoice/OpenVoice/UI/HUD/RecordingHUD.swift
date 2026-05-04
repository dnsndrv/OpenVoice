import AppKit
import Combine
import SwiftUI

/// Плавающее окно (NSPanel) с индикатором записи. Появляется поверх всех
/// приложений на всех Spaces и не отбирает фокус у активного приложения.
@MainActor
final class RecordingHUDController {
    private let panel: NSPanel
    private let hosting: NSHostingView<HUDView>
    private let viewModel: HUDViewModel
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: RecordingCoordinator, recorder: AudioRecorder) {
        let vm = HUDViewModel()
        self.viewModel = vm

        let view = HUDView(viewModel: vm)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 80)
        self.hosting = hosting

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
        panel.hasShadow = true
        panel.contentView = hosting
        panel.ignoresMouseEvents = false
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
        case .transcribing, .injecting:
            show()
        case .error:
            show()
        case .idle:
            hide()
        }
    }

    private func show() {
        if !panel.isVisible {
            positionPanel()
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            if case .idle = self.viewModel.state { self.panel.orderOut(nil) }
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var state: RecordingCoordinator.State = .idle
    @Published var level: Float = 0
    @Published var startedAt: Date = Date()
}

struct HUDView: View {
    @ObservedObject var viewModel: HUDViewModel
    @State private var now = Date()
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            VisualEffectBlur()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .onReceive(timer) { now = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .recording:
            HStack(spacing: 12) {
                Circle().fill(.red).frame(width: 10, height: 10)
                LevelBar(level: viewModel.level)
                Text(elapsed)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
            }
        case .transcribing:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Расшифровка…").font(.body)
            }
        case .injecting:
            HStack(spacing: 12) {
                Image(systemName: "text.cursor")
                Text("Вставка…").font(.body)
            }
        case .error(let msg):
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(msg).font(.callout).lineLimit(2)
            }
        case .idle:
            EmptyView()
        }
    }

    private var elapsed: String {
        let s = Int(now.timeIntervalSince(viewModel.startedAt))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct LevelBar: View {
    let level: Float
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                let count = 20
                ForEach(0..<count, id: \.self) { i in
                    let threshold = Float(i + 1) / Float(count)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(level >= threshold ? barColor(for: threshold) : Color.gray.opacity(0.25))
                        .frame(width: (geo.size.width - CGFloat(count - 1) * 2) / CGFloat(count))
                }
            }
        }
        .frame(height: 18)
    }
    private func barColor(for t: Float) -> Color {
        if t > 0.85 { return .red }
        if t > 0.6 { return .yellow }
        return .green
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.state = .active
        v.blendingMode = .behindWindow
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
