import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let coordinator: AppCoordinator
    private var cancellables = Set<AnyCancellable>()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VibeVoice")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 380)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.recording)
                .environmentObject(coordinator.history)
                .environmentObject(coordinator.models)
        )

        coordinator.recording.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.updateIcon(for: state) }
            .store(in: &cancellables)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateIcon(for state: RecordingCoordinator.State) {
        guard let button = statusItem.button else { return }
        let symbolName: String
        switch state {
        case .idle: symbolName = "mic.fill"
        case .recording: symbolName = "mic.circle.fill"
        case .transcribing, .injecting: symbolName = "waveform.circle.fill"
        case .error: symbolName = "mic.slash.fill"
        }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VibeVoice")
    }
}
