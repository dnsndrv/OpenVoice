import AppKit
import Combine
import SwiftUI

/// Notch-стиль HUD: тёмная пилюля свисает из-под выреза дисплея
/// (или из-под верхнего края меню-бара на дисплеях без notch),
/// расширяется вбок при записи / расшифровке и сворачивается до
/// невидимости в idle. Не отбирает фокус, не активирует приложение.
@MainActor
final class RecordingHUDController {
    private let panel: NSPanel
    private let viewModel: HUDViewModel
    private var cancellables = Set<AnyCancellable>()

    /// Габариты NSPanel — берём «с запасом», чтобы любая конфигурация
    /// раскрытой пилюли в него вписалась. Сама форма рисуется через
    /// `NotchShape` внутри SwiftUI и реально видна только тогда, когда
    /// HUD активен.
    private let panelWidth: CGFloat = 540
    private let panelHeight: CGFloat = 64

    init(coordinator: RecordingCoordinator, recorder: AudioRecorder) {
        let vm = HUDViewModel()
        self.viewModel = vm

        let view = NotchHUDView(viewModel: vm)
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
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        // Дадим свернуться спрингу до невидимости, потом убираем panel вовсе.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            if case .idle = self.viewModel.state { self.panel.orderOut(nil) }
        }
    }

    /// Прижимаем panel к верху экрана: верх контента совпадает с верхней
    /// границей дисплея, чтобы пилюля «свисала» из-под notch.
    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
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

private struct NotchHUDView: View {
    @ObservedObject var viewModel: HUDViewModel
    @State private var now = Date()
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private enum DisplayState: Equatable { case collapsed, active }

    private var displayState: DisplayState {
        switch viewModel.state {
        case .idle: return .collapsed
        case .recording, .transcribing, .injecting, .error: return .active
        }
    }

    /// Геометрия физического notch текущего экрана. На устройствах без
    /// notch возвращаем компактную ширину, эквивалентную небольшой пилюле.
    private var notchSize: CGSize {
        guard let screen = NSScreen.main else {
            return CGSize(width: 180, height: 32)
        }
        if let l = screen.auxiliaryTopLeftArea?.width,
           let r = screen.auxiliaryTopRightArea?.width {
            let w = screen.frame.width - l - r
            let h = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            return CGSize(width: w, height: h)
        }
        return CGSize(width: 180, height: NSStatusBar.system.thickness)
    }

    private let sideExpansion: CGFloat = 110
    private let heightBonus: CGFloat = 8

    private var pillSize: CGSize {
        switch displayState {
        case .collapsed:
            return notchSize
        case .active:
            return CGSize(
                width: notchSize.width + sideExpansion * 2,
                height: notchSize.height + heightBonus
            )
        }
    }

    private var animation: Animation {
        displayState == .collapsed
            ? .spring(response: 0.45, dampingFraction: 1.0)
            : .spring(response: 0.42, dampingFraction: 0.80)
    }

    var body: some View {
        VStack(spacing: 0) {
            pill
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { now = $0 }
        .animation(animation, value: displayState)
    }

    private var pill: some View {
        HStack(spacing: 12) {
            content
                .opacity(displayState == .collapsed ? 0 : 1)
                .animation(displayState == .collapsed
                    ? .easeOut(duration: 0.12)
                    : .easeIn(duration: 0.18).delay(0.1),
                    value: displayState)
        }
        .padding(.horizontal, 18)
        .frame(width: pillSize.width, height: pillSize.height)
        .background(Color.black)
        .clipShape(NotchShape(topCornerRadius: 8, bottomCornerRadius: 18))
        .shadow(color: .black.opacity(displayState == .collapsed ? 0 : 0.35),
                radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .recording:
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .opacity(0.85)
                AudioVisualizer(level: viewModel.level, isActive: true)
                Text(elapsed)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        case .transcribing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Расшифровка")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
        case .injecting:
            HStack(spacing: 10) {
                Image(systemName: "text.cursor")
                    .foregroundStyle(.white)
                Text("Вставка")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            }
        case .error(let msg):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
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
