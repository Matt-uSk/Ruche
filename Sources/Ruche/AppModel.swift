import SwiftUI
import WebKit
import UserNotifications
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppModel: NSObject, ObservableObject {
    static let shared = AppModel()

    /// User-agent Safari standard : évite les blocages « navigateur non pris en charge » (Google, WhatsApp…).
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    @Published var services: [Service] = []
    @Published var selectedID: UUID?
    @Published var badges: [UUID: Int] = [:]
    @Published var icons: [UUID: NSImage] = [:]
    @Published var showAddSheet = false
    @Published var editing: Service?
    /// Brouillon de la feuille d'ajout / modification.
    @Published var draft = Service(name: "", url: "https://")
    /// Services qui ont une vue web chargée (les autres sont en veille).
    @Published private(set) var live: Set<UUID> = []
    /// Fin du mode « Ne pas déranger » (nil = désactivé, distantFuture = jusqu'à réactivation).
    @Published private(set) var dndUntil: Date?
    /// Largeur de départ pendant un redimensionnement de la barre latérale.
    var resizeStartSize: Double?
    let lock = LockManager()
    /// Mode silencieux : notifications affichées, mais sans son.
    @Published var silentMode = UserDefaults.standard.bool(forKey: "silentMode") {
        didSet { UserDefaults.standard.set(silentMode, forKey: "silentMode") }
    }
    /// Icône personnalisée choisie dans la feuille d'ajout / modification (appliquée à l'enregistrement).
    @Published var draftIcon: NSImage?
    var draftIconData: Data?
    @Published var draftIconReset = false
    /// Recherche dans la grille d'ajout de service.
    @Published var presetSearch = ""
    /// Recettes disponibles (intégrées + perso).
    @Published private(set) var recipes: [Recipe] = []
    /// Réveils périodiques en cours : fin prévue et compteur avant le réveil, par service.
    private var periodicUntil: [UUID: Date] = [:]
    private var badgeBeforeWake: [UUID: Int] = [:]
    private var lastPeriodicWake: [UUID: Date] = [:]
    /// Flux Gmail : identifiants des mails déjà vus, par service.
    var gmailSeen: [UUID: Set<String>] = [:]
    private var tickCount = 0
    /// Service en cours de déplacement dans la barre latérale (glisser-déposer).
    @Published var draggingID: UUID?
    private var dragStartIndex: Int?
    /// Largeur occupée par les boutons de fenêtre natifs, mesurée à l'affichage.
    @Published var trafficLightsWidth: Double = 78
    /// État des autorisations de notifications, affiché dans les Réglages.
    @Published var notificationStatus = "…"

    /// Vue unique qui contient toutes les vues web vivantes ; seule la sélectionnée est visible.
    let hostView = WebHostView(frame: .zero)
    var openMainWindow: (() -> Void)?

    private var controllers: [UUID: ServiceController] = [:]
    private var lastActive: [UUID: Date] = [:]
    private var timer: Timer?
    private var started = false

    private let supportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ruche", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("icons"),
                                                 withIntermediateDirectories: true)
        return dir
    }()
    private var servicesFile: URL { supportDir.appendingPathComponent("services.json") }
    private func iconURL(_ id: UUID) -> URL { supportDir.appendingPathComponent("icons/\(id.uuidString)") }

    // MARK: - Démarrage

    func start() {
        guard !started else { return }
        started = true
        UserDefaults.standard.register(defaults: ["hibernateMinutes": 10])
        hostView.wantsLayer = true
        hostView.layer?.cornerRadius = Layout.contentRadius
        hostView.layer?.masksToBounds = true
        recipes = RecipeLibrary.loadAll()
        load()
        let dnd = UserDefaults.standard.double(forKey: "dndUntil")
        if dnd > Date().timeIntervalSince1970 { dndUntil = Date(timeIntervalSince1970: dnd) }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        requestNotificationPermission()

        if let raw = UserDefaults.standard.string(forKey: "selectedID"),
           let id = UUID(uuidString: raw), service(id) != nil {
            selectedID = id
        } else {
            selectedID = services.first?.id
        }
        // Au lancement, on ne charge que le service affiché et ceux marqués « toujours actif ».
        for s in services where s.keepAwake || s.id == selectedID {
            ensureController(s.id)
        }
        updateVisibility()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        // Verrouillage : on masque les pages tant que l'app est verrouillée.
        lock.onLockChange = { [weak self] locked in
            self?.hostView.isHidden = locked
            self?.objectWillChange.send()
        }
        lock.start()

        // Premier relevé des Gmail en veille peu après le lancement.
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await self.checkGmailFeeds()
        }
    }

    // MARK: - Réorganisation par glisser-déposer

    /// Glisser vertical d'une icône : on la déplace d'autant de rangs que la souris a parcourus.
    func dragService(_ id: UUID, translation: CGFloat, rowHeight: CGFloat) {
        if draggingID == nil {
            draggingID = id
            dragStartIndex = services.firstIndex(where: { $0.id == id })
        }
        guard draggingID == id, let start = dragStartIndex,
              let current = services.firstIndex(where: { $0.id == id }) else { return }
        let steps = Int((translation / rowHeight).rounded())
        let target = min(services.count - 1, max(0, start + steps))
        guard target != current else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            services.move(fromOffsets: IndexSet(integer: current), toOffset: target > current ? target + 1 : target)
        }
    }

    func endDrag() {
        draggingID = nil
        dragStartIndex = nil
        save()
    }

    func service(_ id: UUID) -> Service? { services.first { $0.id == id } }
    func isAsleep(_ id: UUID) -> Bool { !live.contains(id) }

    // MARK: - Vues web

    @discardableResult
    private func ensureController(_ id: UUID) -> ServiceController? {
        if let c = controllers[id] { return c }
        guard let s = service(id) else { return nil }
        let c = ServiceController(service: s, model: self)
        c.webView.frame = hostView.bounds
        c.webView.autoresizingMask = [.width, .height]
        c.webView.isHidden = id != selectedID
        hostView.addSubview(c.webView)
        controllers[id] = c
        live.insert(id)
        lastActive[id] = Date()
        return c
    }

    private func updateVisibility() {
        for (id, c) in controllers { c.webView.isHidden = id != selectedID }
        if let id = selectedID, let wv = controllers[id]?.webView {
            wv.window?.makeFirstResponder(wv)
        }
    }

    func select(_ id: UUID) {
        periodicUntil[id] = nil
        badgeBeforeWake[id] = nil
        if let prev = selectedID { lastActive[prev] = Date() }
        selectedID = id
        lastActive[id] = Date()
        UserDefaults.standard.set(id.uuidString, forKey: "selectedID")
        ensureController(id)
        updateVisibility()
    }

    func selectIndex(_ index: Int) {
        guard services.indices.contains(index) else { return }
        select(services[index].id)
    }

    func hibernate(_ id: UUID) {
        guard let c = controllers.removeValue(forKey: id) else { return }
        c.tearDown()
        // Gmail : on mémorise tout de suite les mails présents, pour que chaque mail arrivé
        // pendant la veille déclenche une notification (sans doublon avec ceux déjà vus).
        gmailSeen[id] = nil
        if let s = service(id), s.isGmail {
            Task { await self.checkGmail(s, baselineOnly: true) }
        }
        live.remove(id)
    }

    func wake(_ id: UUID) {
        ensureController(id)
        updateVisibility()
    }

    func reload(_ id: UUID) {
        if let c = controllers[id] { c.webView.reload() } else { wake(id) }
    }

    func reloadSelected() { if let id = selectedID { reload(id) } }
    func goBack() { if let id = selectedID { controllers[id]?.webView.goBack() } }
    func goForward() { if let id = selectedID { controllers[id]?.webView.goForward() } }

    /// Met en veille les services inactifs depuis plus longtemps que le délai choisi.
    private func tick() {
        tickCount += 1
        periodicWakeTick()
        if tickCount % 2 == 0 { Task { await self.checkGmailFeeds() } }
        if let until = dndUntil, until <= Date() { setDoNotDisturb(until: nil) }
        let minutes = UserDefaults.standard.integer(forKey: "hibernateMinutes")
        guard minutes > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
        for s in services where s.id != selectedID && !s.keepAwake && controllers[s.id] != nil {
            if (lastActive[s.id] ?? .distantPast) < cutoff { hibernate(s.id) }
        }
    }

    // MARK: - Réveil périodique

    /// Réveille brièvement (environ 1 min) les services en veille qui le demandent, pour relever
    /// leurs non-lus, puis les remet en veille. Une hausse du compteur déclenche une notification.
    private func periodicWakeTick() {
        let now = Date()
        // Fin des réveils en cours
        for (id, until) in periodicUntil where until <= now {
            periodicUntil[id] = nil
            badgeBeforeWake[id] = nil
            if id != selectedID, service(id)?.keepAwake != true { hibernate(id) }
        }
        // Nouveaux réveils
        for s in services where s.wakeEveryMinutes > 0 && !s.keepAwake && s.id != selectedID && isAsleep(s.id) {
            let last = lastPeriodicWake[s.id] ?? .distantPast
            guard now.timeIntervalSince(last) >= Double(s.wakeEveryMinutes) * 60 else { continue }
            lastPeriodicWake[s.id] = now
            // Compteur de référence ; inconnu (jamais chargé depuis le lancement) = pas de notification ce coup-ci.
            if let known = badges[s.id] { badgeBeforeWake[s.id] = max(known, 0) }
            periodicUntil[s.id] = now.addingTimeInterval(60)
            ensureController(s.id)
            updateVisibility()
        }
    }

    // MARK: - Recettes

    func recipe(for service: Service) -> Recipe? {
        guard let host = URL(string: service.url)?.host else { return nil }
        return recipes.first { $0.matches(host: host) }
    }

    /// Recharge les recettes et relance les services chargés pour appliquer les changements.
    func reloadRecipes() {
        recipes = RecipeLibrary.loadAll()
        for id in Array(controllers.keys) {
            hibernate(id)
            ensureController(id)
        }
        updateVisibility()
    }

    func revealRecipesFolder() {
        try? FileManager.default.createDirectory(at: RecipeLibrary.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(RecipeLibrary.directory)
    }

    // MARK: - Gestion des services

    // MARK: - Onglet Services des Réglages

    @Published var settingsSelection: UUID?
    @Published var settingsAdding = false

    var draftIsValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && URL(string: draft.url)?.host != nil
    }

    var draftIsDirty: Bool {
        guard let id = settingsSelection, let stored = service(id) else { return false }
        return draft != stored || draftIcon != nil || draftIconReset
    }

    func selectInSettings(_ id: UUID?) {
        settingsAdding = false
        settingsSelection = id
        resetDraftIcon()
        if let id, let s = service(id) { draft = s }
    }

    func beginSettingsAdd() {
        presetSearch = ""
        settingsSelection = nil
        draft = Service(name: "", url: "https://")
        resetDraftIcon()
        settingsAdding = true
    }

    func cancelSettingsEdit() {
        selectInSettings(services.first?.id)
    }

    func commitSettingsEdit() {
        guard draftIsValid else { return }
        if settingsAdding {
            let newID = draft.id
            add(draft)
            selectInSettings(newID)
        } else {
            update(draft)
            if let id = settingsSelection { selectInSettings(id) }
        }
    }

    func moveServices(from offsets: IndexSet, to destination: Int) {
        services.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([servicesFile])
    }

    func beginAdd() {
        presetSearch = ""
        draft = Service(name: "", url: "https://")
        resetDraftIcon()
        showAddSheet = true
    }

    func beginEdit(_ s: Service) {
        draft = s
        resetDraftIcon()
        editing = s
    }

    private func resetDraftIcon() {
        draftIcon = nil
        draftIconData = nil
        draftIconReset = false
    }

    /// Choix d'une image pour l'icône du service en cours d'édition.
    func pickDraftIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        draftIcon = image
        draftIconData = png
        draftIconReset = false
    }

    func clearDraftIcon() {
        draftIcon = nil
        draftIconData = nil
        draftIconReset = true
    }

    /// Applique l'icône choisie (ou le retour à l'icône du site) au service enregistré.
    private func applyDraftIcon(to s: inout Service) {
        if let data = draftIconData, let image = draftIcon {
            try? data.write(to: iconURL(s.id))
            icons[s.id] = image
            s.customIcon = true
        } else if draftIconReset {
            try? FileManager.default.removeItem(at: iconURL(s.id))
            icons[s.id] = nil
            s.customIcon = false
            controllers[s.id]?.webView.reload() // pour récupérer l'icône du site
        }
        resetDraftIcon()
    }

    func add(_ s: Service) {
        var s = s
        applyDraftIcon(to: &s)
        services.append(s)
        save()
        select(s.id)
    }

    func update(_ s: Service) {
        var s = s
        guard let i = services.firstIndex(where: { $0.id == s.id }) else { return }
        applyDraftIcon(to: &s)
        let old = services[i]
        services[i] = s
        save()
        if old.url != s.url {
            hibernate(s.id)
            if !s.customIcon {
                icons[s.id] = nil
                try? FileManager.default.removeItem(at: iconURL(s.id))
            }
            if s.id == selectedID || s.keepAwake { ensureController(s.id) }
        } else {
            controllers[s.id]?.service = s
            controllers[s.id]?.webView.pageZoom = s.zoom
            if s.keepAwake { ensureController(s.id) }
        }
        updateVisibility()
    }

    // MARK: - Zoom

    static let zoomPresets: [Double] = [0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75]

    /// Indicateur temporaire affiché au centre lors d'un changement de zoom.
    @Published var zoomHUD: String?
    private var hudToken = 0

    private func flashZoom(_ z: Double) {
        hudToken += 1
        let token = hudToken
        zoomHUD = "\(Int((z * 100).rounded())) %"
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if token == self.hudToken { self.zoomHUD = nil }
        }
    }

    var selectedZoom: Double {
        selectedID.flatMap { service($0)?.zoom } ?? 1.0
    }

    func setZoom(_ value: Double, for id: UUID) {
        guard let i = services.firstIndex(where: { $0.id == id }) else { return }
        let z = min(2.0, max(0.5, (value * 100).rounded() / 100))
        services[i].zoom = z
        save()
        controllers[id]?.service = services[i]
        controllers[id]?.webView.pageZoom = z
        if id == selectedID { flashZoom(z) }
    }

    func zoomSelected(by delta: Double) {
        guard let id = selectedID else { return }
        setZoom(selectedZoom + delta, for: id)
    }

    func resetZoomSelected() {
        guard let id = selectedID else { return }
        setZoom(1.0, for: id)
    }

    func move(_ id: UUID, by delta: Int) {
        guard let i = services.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard services.indices.contains(j) else { return }
        services.swapAt(i, j)
        save()
    }

    /// Efface la session et les données locales d'un service (cookies, stockage), en gardant ses réglages.
    func confirmResetSession(_ s: Service) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Réinitialiser la session de « \(s.name) » ?"
        alert.informativeText = "Les cookies et données locales de ce service seront effacés : tu devras te reconnecter. Ses réglages sont conservés."
        alert.addButton(withTitle: "Réinitialiser")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let id = s.id
        hibernate(id)
        badges[id] = nil
        updateDockBadge()
        Task {
            // Vide le stockage en place (cookies, IndexedDB, caches…) : fonctionne même si WebKit
            // garde encore le stockage ouvert, contrairement à sa suppression.
            let store = WKWebsiteDataStore(forIdentifier: id)
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if self.selectedID == id || self.service(id)?.keepAwake == true {
                self.ensureController(id)
                self.updateVisibility()
            }
        }
    }

    func confirmDelete(_ s: Service) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Supprimer « \(s.name) » ?"
        alert.informativeText = "La session et toutes les données de ce service seront effacées (tu seras déconnecté)."
        alert.addButton(withTitle: "Supprimer")
        alert.addButton(withTitle: "Annuler")
        if alert.runModal() == .alertFirstButtonReturn { delete(s.id) }
    }

    private func delete(_ id: UUID) {
        hibernate(id)
        services.removeAll { $0.id == id }
        badges[id] = nil
        icons[id] = nil
        try? FileManager.default.removeItem(at: iconURL(id))
        save()
        updateDockBadge()
        if selectedID == id {
            selectedID = nil
            if let next = services.first?.id { select(next) }
        }
        if settingsSelection == id { selectInSettings(services.first?.id) }
        // Efface le stockage isolé une fois la vue web libérée.
        Task {
            let store = WKWebsiteDataStore(forIdentifier: id)
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            try? await WKWebsiteDataStore.remove(forIdentifier: id)
        }
    }

    // MARK: - Badges et icônes

    func setBadge(_ count: Int, for id: UUID) {
        if let before = badgeBeforeWake[id], count > before, let s = service(id) {
            badgeBeforeWake[id] = count
            let fresh = count - before
            notify(from: s, title: s.name,
                   body: fresh == 1 ? "1 nouveau message" : "\(fresh) nouveaux messages", jsID: "")
        }
        guard badges[id] != count else { return }
        badges[id] = count
        updateDockBadge()
    }

    private func updateDockBadge() {
        let total = badges.values.filter { $0 > 0 }.reduce(0, +)
        // Depuis macOS 14, la pastille du Dock passe par le centre de notifications.
        UNUserNotificationCenter.current().setBadgeCount(max(total, 0), withCompletionHandler: nil)
        if total > 0 {
            NSApp.dockTile.badgeLabel = "\(total)"
        } else if badges.values.contains(where: { $0 < 0 }) {
            NSApp.dockTile.badgeLabel = "•"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    func setIcon(_ image: NSImage, data: Data, for id: UUID) {
        guard service(id)?.customIcon != true else { return }
        icons[id] = image
        try? data.write(to: iconURL(id))
    }

    // MARK: - Fenêtre

    func showMainWindow() {
        NSApp.activate()
        if let window = hostView.window {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }

    // MARK: - Ne pas déranger

    var doNotDisturb: Bool { (dndUntil ?? .distantPast) > Date() }

    func setDoNotDisturb(until date: Date?) {
        dndUntil = date
        UserDefaults.standard.set(date?.timeIntervalSince1970 ?? 0, forKey: "dndUntil")
    }

    func toggleDoNotDisturb() {
        setDoNotDisturb(until: doNotDisturb ? nil : .distantFuture)
    }

    func enableDoNotDisturb(hours: Double) {
        setDoNotDisturb(until: Date().addingTimeInterval(hours * 3600))
    }

    func doNotDisturbUntilTomorrowMorning() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        setDoNotDisturb(until: morning)
    }

    var doNotDisturbDescription: String {
        guard doNotDisturb, let until = dndUntil else { return "Ne pas déranger : désactivé" }
        if until == .distantFuture { return "Ne pas déranger : activé" }
        return "Ne pas déranger jusqu'à " + until.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshNotificationStatus() }
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let auth: String
            switch settings.authorizationStatus {
            case .authorized, .provisional: auth = "autorisées"
            case .denied: auth = "refusées"
            case .notDetermined: auth = "jamais demandées"
            default: auth = "inconnu"
            }
            let badge: String
            switch settings.badgeSetting {
            case .enabled: badge = "activées"
            case .disabled: badge = "désactivées"
            default: badge = "non prises en charge"
            }
            let text = "Notifications : \(auth)\nPastilles du Dock : \(badge)"
            Task { @MainActor in
                self?.notificationStatus = text
                self?.updateDockBadge()
            }
        }
    }

    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? "ch.mattusk.ruche"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func notify(from service: Service, title: String, body: String, jsID: String) {
        guard !doNotDisturb, let current = self.service(service.id), current.notifications else { return }
        if NSApp.isActive, selectedID == service.id, hostView.window?.isVisible == true { return }

        let content = UNMutableNotificationContent()
        if lock.isLocked {
            // App verrouillée : pas d'aperçu du contenu.
            content.title = current.name
            content.body = "Nouvelle notification"
        } else {
            content.title = title.isEmpty ? current.name : title
            content.subtitle = current.name
            content.body = body
        }
        content.sound = (silentMode || !current.sound) ? nil : .default
        content.userInfo = ["service": current.id.uuidString, "js": jsID]
        if let attachment = iconAttachment(for: current.id) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// macOS affiche toujours l'icône de l'app à gauche ; on joint l'icône du service en vignette.
    private func iconAttachment(for id: UUID) -> UNNotificationAttachment? {
        guard let image = icons[id],
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ruche-icon-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "icon", url: url, options: nil)
        } catch {
            return nil
        }
    }

    fileprivate func handleNotificationClick(serviceID: String?, jsID: String?) {
        showMainWindow()
        guard let serviceID, let id = UUID(uuidString: serviceID), service(id) != nil else { return }
        select(id)
        if let jsID { controllers[id]?.clickNotification(jsID) }
    }

    // MARK: - Réglages rapides par service

    func toggleNotifications(_ id: UUID) {
        guard let i = services.firstIndex(where: { $0.id == id }) else { return }
        services[i].notifications.toggle()
        controllers[id]?.service = services[i]
        save()
    }

    func toggleSound(_ id: UUID) {
        guard let i = services.firstIndex(where: { $0.id == id }) else { return }
        services[i].sound.toggle()
        controllers[id]?.service = services[i]
        save()
    }

    var totalUnread: Int { badges.values.filter { $0 > 0 }.reduce(0, +) }

    // MARK: - Ouverture de session

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Impossible de modifier l'ouverture de session"
                alert.informativeText = error.localizedDescription + "\n\nAstuce : place Ruche dans le dossier Applications."
                alert.runModal()
            }
            objectWillChange.send()
        }
    }

    // MARK: - Export / import de la configuration

    private struct ExportFile: Codable {
        var format = "ruche-config"
        var version = 1
        var services: [Service]
        /// Icônes personnalisées (PNG en base64), par identifiant de service.
        var icons: [String: String]
    }

    func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Ruche-config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var customIcons: [String: String] = [:]
        for s in services where s.customIcon {
            if let data = try? Data(contentsOf: iconURL(s.id)) { customIcons[s.id.uuidString] = data.base64EncodedString() }
        }
        let file = ExportFile(services: services, icons: customIcons)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(file).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try JSONDecoder().decode(ExportFile.self, from: Data(contentsOf: url))
            for var s in file.services {
                let oldID = s.id
                s.id = UUID() // nouveau stockage isolé : il faudra se reconnecter
                if let b64 = file.icons[oldID.uuidString], let data = Data(base64Encoded: b64),
                   let image = NSImage(data: data) {
                    try? data.write(to: iconURL(s.id))
                    icons[s.id] = image
                } else {
                    s.customIcon = false
                }
                services.append(s)
            }
            save()
            if selectedID == nil, let first = services.first { select(first.id) }
            let alert = NSAlert()
            alert.messageText = "\(file.services.count) service(s) importé(s)"
            alert.informativeText = "Les sessions ne sont jamais exportées : connecte-toi à chaque service importé."
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Fichier de configuration illisible"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - Persistance

    private func load() {
        if let data = try? Data(contentsOf: servicesFile),
           let decoded = try? JSONDecoder().decode([Service].self, from: data) {
            services = decoded
        }
        for s in services {
            if let img = NSImage(contentsOf: iconURL(s.id)) { icons[s.id] = img }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(services) {
            try? data.write(to: servicesFile, options: .atomic)
        }
    }
}

extension AppModel: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Le son est déjà décidé dans le contenu (mode silencieux global ou par service).
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let serviceID = info["service"] as? String
        let jsID = info["js"] as? String
        await MainActor.run {
            self.handleNotificationClick(serviceID: serviceID, jsID: jsID)
        }
    }
}
