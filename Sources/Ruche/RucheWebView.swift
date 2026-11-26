import AppKit
import UniformTypeIdentifiers
import WebKit

/// Vue web des services. Pour WhatsApp et Messenger, le dépôt de fichiers depuis le Finder
/// ne fonctionne pas dans WebKit (ces sites inspectent le contenu du glisser pendant le survol,
/// ce que WebKit masque par sécurité) : Ruche reçoit alors elle-même les fichiers et les remet
/// à la page sous forme d'un glisser-déposer JavaScript équivalent.
final class RucheWebView: WKWebView {
    private static let syntheticDropHosts = ["whatsapp.com", "messenger.com", "facebook.com"]
    private static let maxSyntheticBytes = 100 * 1024 * 1024

    private func usesSyntheticDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let host = url?.host?.lowercased(),
              Self.syntheticDropHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
        return !fileURLs(sender).isEmpty
    }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        usesSyntheticDrop(sender) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        usesSyntheticDrop(sender) ? .copy : super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let sender, usesSyntheticDrop(sender) { return }
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        usesSyntheticDrop(sender) ? true : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard usesSyntheticDrop(sender) else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        let y = isFlipped ? point.y : bounds.height - point.y
        let zoom = max(pageZoom, 0.1)
        return syntheticDrop(fileURLs(sender), x: point.x / zoom, y: y / zoom)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
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
