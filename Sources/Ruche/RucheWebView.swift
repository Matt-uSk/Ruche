import AppKit
import UniformTypeIdentifiers
import WebKit

/// Vue web des services. Pour WhatsApp et Messenger, le dépôt de fichiers depuis le Finder
/// ne fonctionne pas dans WebKit (ces sites inspectent le contenu du glisser pendant le survol,
/// ce que WebKit masque par sécurité) : Ruche reçoit alors elle-même les fichiers et les remet
/// à la page sous forme d'un glisser-déposer JavaScript équivalent.
final class RucheWebView: WKWebView {
    /// Réglages internes de WebKit actifs dans Safari mais pas forcément dans une app :
    /// sans eux, `DataTransfer.items` est absent et WhatsApp / Messenger ignorent les fichiers déposés.
    /// Si ces réglages existent, on laisse WebKit gérer le dépôt normalement.
    private(set) static var nativeDropEnabled = false

    static func enableDataTransferFeatures(_ preferences: WKPreferences) {
        var enabled = false
        for key in ["dataTransferItemsEnabled", "customPasteboardDataEnabled"] {
            let capitalized = key.prefix(1).uppercased() + String(key.dropFirst())
            let setter = NSSelectorFromString("_set\(capitalized):")
            if preferences.responds(to: setter) {
                preferences.setValue(true, forKey: key)
                if key == "dataTransferItemsEnabled" { enabled = true }
            }
        }
        nativeDropEnabled = enabled
    }

    private static let syntheticDropHosts = ["whatsapp.com", "messenger.com", "facebook.com"]
    private static let maxSyntheticBytes = 100 * 1024 * 1024

    /// Le dépôt simulé n'est plus utilisé par défaut (il ne fonctionnait pas) ; réactivable pour test :
    /// `defaults write ch.mattusk.ruche syntheticDrop -bool true`.
    private func usesSyntheticDrop(_ sender: NSDraggingInfo) -> Bool {
        guard UserDefaults.standard.bool(forKey: "syntheticDrop"), let host = url?.host?.lowercased(),
              Self.syntheticDropHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
        return !fileURLs(sender).isEmpty
    }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    // MARK: Diagnostic (dropDebug)

    private var debugEnabled: Bool { UserDefaults.standard.bool(forKey: "dropDebug") }
    private var lastLoggedUpdate: UInt?

    fileprivate func debugLog(_ text: String) {
        guard debugEnabled,
              let data = try? JSONSerialization.data(withJSONObject: [text]),
              let json = String(data: data, encoding: .utf8) else { return }
        evaluateJavaScript("window.__rucheDropLog && window.__rucheDropLog(\(json)[0])", completionHandler: nil)
    }

    private func describe(_ sender: NSDraggingInfo) -> String {
        let types = (sender.draggingPasteboard.types ?? []).map(\.rawValue).joined(separator: ",")
        return "fichiers=\(fileURLs(sender).count) | masque source=\(sender.draggingSourceOperationMask.rawValue) | presse-papiers=[\(types.prefix(300))]"
    }

    // MARK: Cible de glisser-déposer

    /// Toutes les pages des services sont empilées au même endroit, une seule étant affichée.
    /// AppKit peut remettre un glisser à une page masquée située au-dessus dans la pile :
    /// la page affichée ne voyait alors rien. Deux protections :
    ///  1. seule la page affichée reste enregistrée comme cible (setDropTarget) ;
    ///  2. si une page masquée reçoit quand même un glisser, elle le transmet à la page affichée.
    private var savedDragTypes: [NSPasteboard.PasteboardType]?

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
        if let other = visibleSibling {
            other.debugLog("AppKit : glisser remis à une page MASQUÉE (\(url?.host ?? "?")) → transmis à la page affichée")
            return other.draggingEntered(sender)
        }
        lastLoggedUpdate = nil
        if usesSyntheticDrop(sender) {
            debugLog("AppKit draggingEntered → simulé | " + describe(sender))
            return .copy
        }
        let op = super.draggingEntered(sender)
        DropLog.write("   WebKit répond \(op.rawValue) (0 = refusé) | fichiers=\(fileURLs(sender).count)")
        debugLog("AppKit draggingEntered → WebKit répond \(op.rawValue) | " + describe(sender))
        return op
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let other = visibleSibling { return other.draggingUpdated(sender) }
        if usesSyntheticDrop(sender) { return .copy }
        let op = super.draggingUpdated(sender)
        if lastLoggedUpdate != op.rawValue {
            lastLoggedUpdate = op.rawValue
            debugLog("AppKit draggingUpdated → WebKit répond \(op.rawValue) (0 = refusé, 1 = copie)")
        }
        return op
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let other = visibleSibling { other.draggingExited(sender); return }
        debugLog("AppKit draggingExited")
        if let sender, usesSyntheticDrop(sender) { return }
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let other = visibleSibling { return other.prepareForDragOperation(sender) }
        if usesSyntheticDrop(sender) { return true }
        let ok = super.prepareForDragOperation(sender)
        debugLog("AppKit prepareForDragOperation → \(ok)")
        return ok
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        DropLog.write("performDragOperation reçu par " + DropLog.describe(self))
        if let other = visibleSibling { return other.performDragOperation(sender) }
        guard usesSyntheticDrop(sender) else {
            let ok = super.performDragOperation(sender)
            debugLog("AppKit performDragOperation → \(ok)")
            return ok
        }
        debugLog("AppKit performDragOperation → simulé")
        let point = convert(sender.draggingLocation, from: nil)
        let y = isFlipped ? point.y : bounds.height - point.y
        let zoom = max(pageZoom, 0.1)
        return syntheticDrop(fileURLs(sender), x: point.x / zoom, y: y / zoom)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if let other = visibleSibling { other.concludeDragOperation(sender); return }
        if let sender, usesSyntheticDrop(sender) { return }
        super.concludeDragOperation(sender)
    }

    /// Lit les fichiers et rejoue dragenter / dragover / drop dans la page avec un vrai DataTransfer.
    private func syntheticDrop(_ urls: [URL], x: CGFloat, y: CGFloat) -> Bool {
        var total = 0
        var files: [[String: String]] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            total += data.count
            guard total <= Self.maxSyntheticBytes else { break }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            files.append(["name": url.lastPathComponent, "type": type, "b64": data.base64EncodedString()])
        }
        guard !files.isEmpty,
              let json = try? JSONSerialization.data(withJSONObject: files),
              let jsonText = String(data: json, encoding: .utf8) else { return false }

        let script = """
        (async function (files, x, y) {
          const dt = new DataTransfer();
          for (const f of files) {
            const bin = atob(f.b64);
            const bytes = new Uint8Array(bin.length);
            for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
            dt.items.add(new File([bytes], f.name, { type: f.type }));
          }
          // WebKit ignore parfois « dataTransfer » dans le constructeur : on l'attache aussi à la main.
          const make = (type, init, prop, value) => {
            let ev;
            try { ev = new DragEvent(type, init); } catch (e) { ev = new Event(type, init); }
            if (!ev[prop]) { try { Object.defineProperty(ev, prop, { value: value }); } catch (e) {} }
            return ev;
          };
          const fire = (type) => {
            const el = document.elementFromPoint(x, y) || document.body;
            const ev = make(type, { bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y,
                                    dataTransfer: dt }, "dataTransfer", dt);
            el.dispatchEvent(ev);
            return ev.defaultPrevented;
          };
          fire("dragenter");
          fire("dragover");
          await new Promise((r) => setTimeout(r, 150));
          fire("dragover");
          let ok = fire("drop");
          if (!ok) {
            // Plan B : un collage (⌘V) des fichiers dans la zone de saisie, que WhatsApp et Messenger acceptent.
            const editors = Array.from(document.querySelectorAll('[contenteditable="true"]'));
            const target = (document.activeElement && document.activeElement.isContentEditable)
              ? document.activeElement : editors[editors.length - 1];
            if (target) {
              target.focus();
              let paste;
              try { paste = new ClipboardEvent("paste", { bubbles: true, cancelable: true, clipboardData: dt }); }
              catch (e) { paste = new Event("paste", { bubbles: true, cancelable: true }); }
              if (!paste.clipboardData) { try { Object.defineProperty(paste, "clipboardData", { value: dt }); } catch (e) {} }
              target.dispatchEvent(paste);
              ok = paste.defaultPrevented;
            }
          }
          try { window.webkit.messageHandlers.ruche.postMessage({ type: "dropResult", ok: ok }); } catch (e) {}
        })(\(jsonText), \(Double(x)), \(Double(y)));
        """
        evaluateJavaScript(script, completionHandler: nil)
        return true
    }
}
