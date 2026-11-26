import Foundation
import Security
import WebKit

/// Clé maîtresse WebCrypto de Ruche (16 octets), créée au premier lancement et gardée dans
/// ~/Library/Application Support/Ruche/webcrypto.key (lisible uniquement par l'utilisateur).
/// WebKit s'en sert pour chiffrer les clés cryptographiques que les sites stockent dans IndexedDB
/// (WhatsApp Web, par exemple). La fournir nous-mêmes évite la demande d'accès au trousseau.
enum WebCryptoKey {
    static let data: Data = {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ruche", isDirectory: true)
        let url = dir.appendingPathComponent("webcrypto.key")
        if let existing = try? Data(contentsOf: url), existing.count == 16 { return existing }

        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        }
        let key = Data(bytes)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: key, attributes: [.posixPermissions: 0o600])
        return key
    }()
}

/// Délégué minimal pour les fenêtres popup (connexion OAuth) : fournit seulement la clé WebCrypto.
final class WebCryptoKeyProvider: NSObject, WKNavigationDelegate {
    @objc(_webCryptoMasterKeyForWebView:completionHandler:)
    func webCryptoMasterKey(for webView: WKWebView, completionHandler: @escaping (NSData?) -> Void) {
        completionHandler(WebCryptoKey.data as NSData)
    }

    @objc(_webCryptoMasterKeyForWebView:)
    func webCryptoMasterKeyLegacy(for webView: WKWebView) -> NSData? {
        WebCryptoKey.data as NSData
    }
}
