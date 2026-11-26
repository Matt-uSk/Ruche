import AppKit
import WebKit

/// Conteneur des vues web. Accepte aussi les glisser-déposer de fichiers, liens, texte et images
/// et les transmet à la vue web affichée : dans la hiérarchie SwiftUI, le dépôt n'atteignait
/// pas toujours WKWebView (ex. déposer une photo dans une conversation WhatsApp).
final class WebHostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png, .html, .rtf, .pdf])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    /// Vue web actuellement visible.
    private var target: WKWebView? {
        subviews.reversed().compactMap { $0 as? WKWebView }.first { !$0.isHidden }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        DropLog.write("draggingEntered reçu par le CONTENEUR")
        DropLog.dumpStack(of: self, reason: "conteneur")
        if UserDefaults.standard.bool(forKey: "dropDebug") {
            target?.evaluateJavaScript("window.__rucheDropLog && window.__rucheDropLog('AppKit : le glisser arrive sur le CONTENEUR (pas directement sur la page)')", completionHandler: nil)
        }
        return target?.draggingEntered(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        target?.draggingUpdated(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        target?.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        target?.prepareForDragOperation(sender) ?? false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        target?.performDragOperation(sender) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        target?.concludeDragOperation(sender)
    }
}
