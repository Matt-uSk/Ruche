import SwiftUI

@main
struct RucheApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @AppStorage("showMenuBar") private var showMenuBar = false

    var body: some Scene {
        Window("Ruche", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { RucheCommands(model: model) }

        Settings {
            SettingsView().environmentObject(model)
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarContent().environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
        if UserDefaults.standard.bool(forKey: "startHidden") {
            // Laisse SwiftUI créer la fenêtre, puis masque l'app (un clic sur le Dock la réaffiche).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.hide(nil) }
        }
    }

    /// Fermer la fenêtre ne quitte pas l'app : les services « toujours actifs » continuent de notifier.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.showMainWindow() }
        return true
    }
}

struct RucheCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        // Menu Présentation
        CommandGroup(before: .toolbar) {
            Button("Zoom avant") { model.zoomSelected(by: 0.1) }
                .keyboardShortcut("+")
            Button("Zoom arrière") { model.zoomSelected(by: -0.1) }
                .keyboardShortcut("-")
            Button("Taille réelle") { model.resetZoomSelected() }
                .keyboardShortcut("0")
            Menu("Zoom du service (\(Int((model.selectedZoom * 100).rounded())) %)") {
                ForEach(AppModel.zoomPresets, id: \.self) { z in
                    Button("\(Int((z * 100).rounded())) %" + (abs(model.selectedZoom - z) < 0.01 ? "  ✓" : "")) {
                        if let id = model.selectedID { model.setZoom(z, for: id) }
                    }
                }
            }
            Divider()
        }

        CommandMenu("Services") {
            Button("Recharger") { model.reloadSelected() }
                .keyboardShortcut("r")
            Button("Précédent") { model.goBack() }
                .keyboardShortcut("[")
            Button("Suivant") { model.goForward() }
                .keyboardShortcut("]")
            Divider()
            Toggle("Mode silencieux", isOn: $model.silentMode)
            Button("Verrouiller maintenant") { model.lock.lockNow() }
                .keyboardShortcut("l", modifiers: [.command, .control])
            Divider()
            Button("Ajouter un service…") { model.beginAdd() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            ForEach(Array(model.services.prefix(9).enumerated()), id: \.element.id) { index, service in
                Button(service.name) { model.selectIndex(index) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}
