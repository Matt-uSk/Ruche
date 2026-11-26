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
          const fire = (type) => {
            const el = document.elementFromPoint(x, y) || document.body;
            el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, composed: true,
                                                    dataTransfer: dt, clientX: x, clientY: y }));
          };
          fire("dragenter");
          fire("dragover");
          // La zone « Déposez les fichiers ici » apparaît après dragenter : on vise ce qui est sous le pointeur ensuite.
          await new Promise((r) => setTimeout(r, 150));
          fire("dragover");
          fire("drop");
        })(\(jsonText), \(Double(x)), \(Double(y)));
        """
        evaluateJavaScript(script, completionHandler: nil)
        return true
    }
}
