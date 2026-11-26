import AppKit
import WebKit

/// Relais faible pour éviter le cycle de rétention WKUserContentController → handler.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: ServiceController?
    init(_ target: ServiceController) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.handle(message) }
    }
}

/// Une vue web vivante pour un service, avec son propre stockage isolé.
@MainActor
final class ServiceController: NSObject {
    var service: Service
    let webView: WKWebView
    weak var model: AppModel?

    private var popups: [PopupCatcher] = []
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    /// Hôtes de connexion autorisés à s'ouvrir dans l'app (OAuth, login).
    /// Hôtes entièrement dédiés à la connexion : toujours gardés dans l'app.
    static let authHosts: Set<String> = [
        "accounts.google.com", "accounts.youtube.com",
        "id.atlassian.com", "appleid.apple.com",
        "login.microsoftonline.com", "login.live.com", "account.proton.me",
    ]
    /// Sites généralistes qui servent aussi à se connecter ailleurs (« Se connecter avec Facebook ») :
    /// gardés dans l'app seulement pour leurs pages de connexion, pas pour un lien partagé.
    static let mixedAuthHosts: Set<String> = [
        "www.facebook.com", "facebook.com", "m.facebook.com", "discord.com",
    ]
    private static let authPathHints = ["login", "oauth", "dialog", "checkpoint", "signin", "auth", "consent", "two_step"]

    init(service: Service, model: AppModel) {
        self.service = service
        self.model = model

        let config = WKWebViewConfiguration()
        // Le cœur de l'isolation : un stockage (cookies, localStorage, IndexedDB…) par service.
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: service.id)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        RucheWebView.enableDataTransferFeatures(config.preferences)
        config.mediaTypesRequiringUserActionForPlayback = []
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Scripts.notificationShim,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: Scripts.badgeReporter,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: Scripts.recipeAPI,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: true))
        if let recipe = model.recipe(for: service), let script = recipe.script {
            ucc.addUserScript(WKUserScript(source: Scripts.wrapRecipe(script, id: recipe.id),
                                           injectionTime: .atDocumentEnd,
                                           forMainFrameOnly: true))
        }
        config.userContentController = ucc

        webView = RucheWebView(frame: .zero, configuration: config)
        super.init()

        ucc.add(WeakScriptHandler(self), name: "ruche")
        webView.customUserAgent = AppModel.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        webView.pageZoom = service.zoom

        if let url = URL(string: service.url) {
            webView.load(URLRequest(url: url))
        }
    }

    func tearDown() {
        webView.stopLoading()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        popups.forEach { $0.close() }
        popups.removeAll()
    }

    // MARK: - Notifications

    func handle(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if body["type"] as? String == "dropResult" {
            if body["ok"] as? Bool != true {
                let alert = NSAlert()
                alert.messageText = "\(service.name) n'a pas accepté le fichier"
                alert.informativeText = "Utilise plutôt le trombone de la conversation, ou copie le fichier dans le Finder (⌘C) puis colle-le (⌘V) dans le message."
                alert.runModal()
            }
            return
        }
        if body["type"] as? String == "badge" {
            let count = (body["count"] as? NSNumber)?.intValue ?? 0
            model?.setBadge(count, for: service.id)
            return
        }
        guard body["type"] as? String == "notification" else { return }
        let title = body["title"] as? String ?? service.name
        let text = body["body"] as? String ?? ""
        let jsID = (body["id"] as? String ?? "").filter { $0.isLetter || $0.isNumber }
        model?.notify(from: service, title: title, body: text, jsID: jsID)
    }

    func clickNotification(_ jsID: String) {
        let safe = jsID.filter { $0.isLetter || $0.isNumber }
        guard !safe.isEmpty else { return }
        webView.evaluateJavaScript("window.__rucheClick && window.__rucheClick('\(safe)')", completionHandler: nil)
    }

    // MARK: - Liens

    private func domainTail(_ host: String) -> String {
        host.split(separator: ".").suffix(2).joined(separator: ".")
    }

    private var baseDomain: String {
        domainTail(URL(string: service.url)?.host ?? "")
    }

    func isInternal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return domainTail(host) == baseDomain || Self.isAuthHost(url)
    }

    /// Déballe les redirections de suivi (google.com/url?q=…, l.messenger.com/l.php?u=…).
    func unwrapRedirect(_ url: URL) -> URL? {
        guard ["/url", "/l.php"].contains(url.path),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "q" || $0.name == "u" || $0.name == "url" })?.value,
              let target = URL(string: raw), target.scheme?.hasPrefix("http") == true
        else { return nil }
        return target
    }

    /// Ouvre un lien externe selon le réglage : navigateur par défaut (par défaut) ou fenêtre Ruche.
    func openExternally(_ url: URL) {
        let target = unwrapRedirect(url) ?? url
        if UserDefaults.standard.string(forKey: "externalLinks") == "ruche" {
            openInRucheWindow(target)
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    /// Fenêtre Ruche pour un lien externe, avec la session du service.
    func openInRucheWindow(_ url: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = webView.configuration.websiteDataStore
        let catcher = PopupCatcher(configuration: config, owner: self, keepInApp: true)
        popups.append(catcher)
        catcher.show()
        catcher.webView.load(URLRequest(url: url))
    }

    static func isAuthHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if authHosts.contains(host) { return true }
        if mixedAuthHosts.contains(host) {
            let path = url.path.lowercased()
            return authPathHints.contains { path.contains($0) }
        }
        return false
    }
}

// MARK: - WKNavigationDelegate

extension ServiceController: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        guard let url = navigationAction.request.url else { return .allow }

        if let scheme = url.scheme?.lowercased(),
           !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            NSWorkspace.shared.open(url) // mailto:, tel:, zoommtg:, etc.
            return .cancel
        }
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame == true,
           unwrapRedirect(url) != nil || !isInternal(url) {
            openExternally(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, model?.icons[service.id] == nil else { return }
        webView.evaluateJavaScript(Scripts.bestIcon) { [weak self] result, _ in
            guard let href = result as? String, let url = URL(string: href) else { return }
            Task { @MainActor in await self?.fetchIcon(url) }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // Clé maîtresse WebCrypto : par défaut, WebKit la range dans le trousseau, et macOS demande
    // l'autorisation à chaque nouvelle signature de l'app (signature ad hoc = à chaque mise à jour).
    // En fournissant la clé nous-mêmes (méthodes de délégué privées de WebKit, appelées si présentes),
    // le trousseau n'est plus sollicité.
    @objc(_webCryptoMasterKeyForWebView:completionHandler:)
    func webCryptoMasterKey(for webView: WKWebView, completionHandler: @escaping (NSData?) -> Void) {
        completionHandler(WebCryptoKey.data as NSData)
    }

    @objc(_webCryptoMasterKeyForWebView:)
    func webCryptoMasterKeyLegacy(for webView: WKWebView) -> NSData? {
        WebCryptoKey.data as NSData
    }

    private func fetchIcon(_ url: URL) async {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data), image.isValid else { return }
        model?.setIcon(image, data: data, for: service.id)
    }
}

// MARK: - WKUIDelegate

extension ServiceController: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme?.hasPrefix("http") == true,
           unwrapRedirect(url) != nil || !isInternal(url) {
            openExternally(url)
            return nil
        }
        // Popup interne (connexion OAuth) ou fenêtre vide pilotée par JS (WhatsApp ouvre ses liens
        // ainsi) : un « attrape-popup » invisible regarde où va la première navigation —
        // site externe → navigateur par défaut ; connexion / même service → petite fenêtre.
        let catcher = PopupCatcher(configuration: configuration, owner: self)
        popups.append(catcher)
        return catcher.webView
    }

    /// Faut-il ouvrir cette adresse dans l'app (connexion, même service) plutôt que dans le navigateur ?
    func shouldOpenInApp(_ url: URL) -> Bool {
        unwrapRedirect(url) == nil && isInternal(url)
    }

    func dropPopup(_ catcher: PopupCatcher) {
        popups.removeAll { $0 === catcher }
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.urls : nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = service.name
        alert.informativeText = message
        alert.runModal()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = service.name
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Annuler")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView,
                 decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo,
                 type: WKMediaCaptureType) async -> WKPermissionDecision {
        .prompt
    }
}

// MARK: - WKDownloadDelegate

extension ServiceController: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let fm = FileManager.default
        let dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = suggestedFilename.isEmpty ? "téléchargement" : suggestedFilename
        var dest = dir.appendingPathComponent(name)
        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        var i = 1
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            i += 1
        }
        downloadDestinations[ObjectIdentifier(download)] = dest
        return dest
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let dest = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // Fait rebondir la pile Téléchargements du Dock, comme Safari.
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"),
                                                     object: dest.path)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
    }
}


/// Fenêtre popup ouverte par une page. Reste invisible tant qu'on ne sait pas où elle va :
/// un lien externe part dans le navigateur par défaut, une page de connexion s'affiche.
@MainActor
final class PopupCatcher: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    weak var owner: ServiceController?
    private var window: NSWindow?
    /// Fenêtre ouverte volontairement pour un lien externe (réglage « fenêtre Ruche ») : on n'en sort pas.
    private let keepInApp: Bool
    /// Fenêtre de connexion (Google, Facebook…) : on la laisse naviguer librement.
    private var isAuthFlow = false
    /// Page du service : on n'affiche la fenêtre qu'une fois la page réellement chargée
    /// (elle peut n'être qu'une redirection vers un site externe).
    private var showWhenCommitted = false

    init(configuration: WKWebViewConfiguration, owner: ServiceController, keepInApp: Bool = false) {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: keepInApp ? 1000 : 520, height: keepInApp ? 760 : 720),
                            configuration: configuration)
        self.owner = owner
        self.keepInApp = keepInApp
        super.init()
        webView.customUserAgent = AppModel.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func show() {
        guard window == nil else { return }
        let window = NSWindow(contentRect: webView.frame,
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = owner?.service.name ?? "Ruche"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        webView.stopLoading()
        window?.close()
        window = nil
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard !keepInApp, let owner,
              navigationAction.targetFrame?.isMainFrame != false,
              let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return .allow }
        if ServiceController.isAuthHost(url) { isAuthFlow = true }
        // Page de connexion : petite fenêtre tout de suite.
        if isAuthFlow {
            show()
            return .allow
        }
        // Page du service lui-même : affichée seulement si elle se charge vraiment.
        if owner.shouldOpenInApp(url) {
            showWhenCommitted = true
            return .allow
        }
        // Site externe — y compris après une page de redirection du service (WhatsApp passe
        // d'abord par sa propre adresse) : on ferme la fenêtre et on ouvre le lien comme réglé.
        close()
        owner.dropPopup(self)
        owner.openExternally(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if showWhenCommitted { show() }
    }

    func webViewDidClose(_ webView: WKWebView) {
        close()
        owner?.dropPopup(self)
    }

    @objc(_webCryptoMasterKeyForWebView:completionHandler:)
    func webCryptoMasterKey(for webView: WKWebView, completionHandler: @escaping (NSData?) -> Void) {
        completionHandler(WebCryptoKey.data as NSData)
    }

    @objc(_webCryptoMasterKeyForWebView:)
    func webCryptoMasterKeyLegacy(for webView: WKWebView) -> NSData? {
        WebCryptoKey.data as NSData
    }
}
