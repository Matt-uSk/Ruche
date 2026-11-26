import AppKit
import WebKit

/// Journal de diagnostic du glisser-déposer, désactivé par défaut. Pour l'activer :
/// `defaults write ch.mattusk.ruche dropDebug -bool true`, relancer Ruche, puis lire /tmp/ruche-drop.log.
enum DropLog {
    static let url = URL(fileURLWithPath: "/tmp/ruche-drop.log")
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "dropDebug") }

    static func write(_ text: String) {
        guard enabled else { return }
        let stamp = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(2)))
        let line = "\(stamp)  \(text)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Décrit une vue web : site, visibilité, fenêtre, taille, nombre de types de glisser enregistrés.
    static func describe(_ view: NSView) -> String {
        let host = (view as? WKWebView)?.url?.host ?? String(describing: type(of: view))
        return "\(host) [masquée=\(view.isHidden) fenêtre=\(view.window != nil) taille=\(Int(view.frame.width))x\(Int(view.frame.height)) types=\(view.registeredDraggedTypes.count)]"
    }

    static func describeWindow(_ window: NSWindow?) -> String {
        guard let window else { return "fenêtre=aucune" }
        let id = String(UInt(bitPattern: ObjectIdentifier(window).hashValue) % 100000)
        return "fenêtre#\(id) visible=\(window.isVisible) active=\(window.isKeyWindow) \(Int(window.frame.width))x\(Int(window.frame.height))"
    }

    /// État de la pile des pages (du dessous vers le dessus).
    static func dumpStack(of container: NSView?, reason: String) {
        guard enabled, let container else { return }
        write("PILE (\(reason)) conteneur \(describe(container)) | \(describeWindow(container.window))")
        for (i, v) in container.subviews.enumerated() {
            write("   \(i): \(describe(v))")
        }
    }
}
