import AppKit
import SwiftUI

@main
struct OpenVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var menuBar: MenuBarController!
    private var hud: RecordingHUDController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        self.menuBar = MenuBarController(coordinator: coordinator)
        self.hud = RecordingHUDController(
            coordinator: coordinator.recording,
            recorder: coordinator.recorder
        )
        coordinator.start()

        if !TextInjector.hasAccessibilityPermission() {
            TextInjector.promptAccessibilityPermission()
        }
    }
}
