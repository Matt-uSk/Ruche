import AppKit
import WebKit

/// Vue web d'un service.
///
/// Toutes les pages des services sont empilées au même endroit, une seule étant affichée.
/// macOS ne remet un glisser-déposer qu'à la page du dessus de la pile : `WebHostView.bringToFront`
/// y place la page affichée à chaque changement de service. En complément, seule la page affichée
/// reste enregistrée comme cible, et une page masquée qui recevrait quand même un glisser le
/// transmet à la page affichée.
final class RucheWebView: WKWebView {
    private var savedDragTypes: [NSPasteboard.PasteboardType]?

    /// Enregistre (ou retire) cette page comme cible de glisser-déposer.
    func setDropTarget(_ enabled: Bool) {
        if savedDragTypes == nil {
            var types = registeredDraggedTypes
            for t: NSPasteboard.PasteboardType in [.fileURL, .URL, .string, .html, .rtf, .tiff, .png, .pdf]
            where !types.contains(t) {
                types.append(t)
            }
            savedDragTypes = types
        }
        unregisterDraggedTypes()
        if enabled, let types = savedDragTypes { registerForDraggedTypes(types) }
    }

    /// Page affichée à qui transmettre le glisser, si celle-ci est masquée.
    private var visibleSibling: RucheWebView? {
        guard isHidden else { return nil }
        return superview?.subviews.compactMap { $0 as? RucheWebView }.first { !$0.isHidden && $0 !== self }
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        DropLog.write("draggingEntered reçu par " + DropLog.describe(self))
        DropLog.dumpStack(of: superview, reason: "draggingEntered")
        if let other = visibleSibling { return other.draggingEntered(sender) }
        let op = super.draggingEntered(sender)
        DropLog.write("   WebKit répond \(op.rawValue) (0 = refusé)")
        return op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let other = visibleSibling { return other.draggingUpdated(sender) }
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let other = visibleSibling { other.draggingExited(sender); return }
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let other = visibleSibling { return other.prepareForDragOperation(sender) }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        DropLog.write("performDragOperation reçu par " + DropLog.describe(self))
        if let other = visibleSibling { return other.performDragOperation(sender) }
        return super.performDragOperation(sender)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if let other = visibleSibling { other.concludeDragOperation(sender); return }
        super.concludeDragOperation(sender)
    }
}
