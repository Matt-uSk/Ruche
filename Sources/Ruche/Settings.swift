import SwiftUI

// MARK: - Modèles de services (grille d'icônes)

struct RecipeGroup: Identifiable {
    let id: String
    let recipes: [Recipe]
}

struct PresetGrid: View {
    @EnvironmentObject var model: AppModel
    var columns = 4

    /// Recettes filtrées par la recherche, regroupées par catégorie (ordre des catégories connues, puis les autres).
    private var groups: [RecipeGroup] {
        let query = model.presetSearch.trimmingCharacters(in: .whitespaces)
        let filtered = model.recipes.filter { r in
            query.isEmpty
                || r.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || r.url.range(of: query, options: [.caseInsensitive]) != nil
                || RecipeLibrary.label(forCategory: r.category)
                    .range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        var order = RecipeLibrary.categories.map(\.id)
        for r in filtered where !order.contains(r.category) { order.append(r.category) }
        return order.compactMap { cat in
            let items = filtered.filter { $0.category == cat }
            return items.isEmpty ? nil : RecipeGroup(id: cat, recipes: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Rechercher un service", text: $model.presetSearch)
                    .textFieldStyle(.plain)
                if !model.presetSearch.isEmpty {
                    Button { model.presetSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let groups = self.groups
                    if groups.isEmpty {
                        Text("Aucun service ne correspond. Tu peux en ajouter un à la main avec le formulaire ci-dessous.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(RecipeLibrary.label(forCategory: group.id))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns),
                                      spacing: 8) {
                                ForEach(group.recipes) { preset in tile(preset) }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    private func tile(_ preset: Recipe) -> some View {
        Button {
            model.draft.name = preset.name
            model.draft.url = preset.url
            model.draft.keepAwake = preset.keepAwake
        } label: {
            VStack(spacing: 6) {
                AsyncImage(url: preset.iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    } else {
                        Placeholder(name: preset.name)
                    }
                }
                .frame(width: 32, height: 32)
                // Certaines icônes ont un fond blanc carré : coins arrondis pour toutes.
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(preset.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(model.draft.url == preset.url ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(model.draft.url == preset.url ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Formulaire d'un service (feuille d'ajout et onglet Services)

/// Champs d'un service, liés au brouillon `model.draft`.
struct ServiceForm: View {
    @EnvironmentObject var model: AppModel
    private var draft: Service { model.draft }

    var body: some View {
        Form {
            TextField("Nom", text: $model.draft.name)
            TextField("URL", text: $model.draft.url)
            LabeledContent("Icône") {
                HStack(spacing: 10) {
                    Group {
                        if let image = model.draftIcon {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        } else if !model.draftIconReset, let image = model.icons[draft.id] {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Placeholder(name: draft.name.isEmpty ? "?" : draft.name)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button("Choisir une image…") { model.pickDraftIcon() }
                    if model.draftIcon != nil || (draft.customIcon && !model.draftIconReset) {
                        Button("Icône du site") { model.clearDraftIcon() }
                    }
                }
            }
            Picker("Pastille", selection: $model.draft.tint) {
                ForEach(TintColor.allCases) { Text($0.label).tag($0) }
            }
            Picker("Zoom", selection: $model.draft.zoom) {
                ForEach(AppModel.zoomPresets, id: \.self) { z in
                    Text("\(Int((z * 100).rounded())) %").tag(z)
                }
            }
            Toggle("Toujours actif (jamais mis en veille)", isOn: $model.draft.keepAwake)
            Picker("Réveil périodique en veille", selection: $model.draft.wakeEveryMinutes) {
                Text("Jamais").tag(0)
                Text("Toutes les 10 min").tag(10)
                Text("Toutes les 15 min").tag(15)
                Text("Toutes les 30 min").tag(30)
                Text("Toutes les heures").tag(60)
            }
            .disabled(draft.keepAwake)
            if let recipe = model.recipe(for: draft) {
                LabeledContent("Recette") {
                    Text(recipe.name + (recipe.script == nil ? " (détection générique)" : "")
                         + (recipe.isBuiltIn ? "" : " · perso"))
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Notifications", isOn: $model.draft.notifications)
            Toggle("Son des notifications", isOn: $model.draft.sound)
                .disabled(!draft.notifications)
        }
    }
}

// MARK: - Feuille d'ajout / modification (depuis la barre latérale)

struct ServiceEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Service d'origine en modification (nil = ajout). Le brouillon vit dans model.draft :
    /// les Command Line Tools n'ont pas le plugin de macro SwiftUI requis par @State.
    let original: Service?

    init(original: Service?) { self.original = original }

    private var isNew: Bool { original == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Ajouter un service" : "Modifier « \(original?.name ?? "") »")
                .font(.headline)
            if isNew { PresetGrid() }
            ServiceForm()
            Text("Chaque service a son propre stockage isolé : tu peux ajouter plusieurs fois le même service avec des comptes différents. Notifications désactivées = le compteur reste visible, sans notification.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Ajouter" : "Enregistrer") {
                    if isNew { model.add(model.draft) } else { model.update(model.draft) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.draftIsValid)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

// MARK: - Réglages (onglets)

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Général", systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label("Apparence", systemImage: "paintbrush") }
            ServicesSettings()
                .tabItem { Label("Services", systemImage: "square.stack") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            SecuritySettings()
                .tabItem { Label("Sécurité", systemImage: "touchid") }
            AdvancedSettings()
                .tabItem { Label("Avancé", systemImage: "wrench.and.screwdriver") }
        }
        .environmentObject(model)
    }
}

/// Mise en page commune des onglets simples.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(width: 560)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("startHidden") private var startHidden = false
    @AppStorage("showMenuBar") private var showMenuBar = false
    @AppStorage("hibernateMinutes") private var minutes = 10
    @AppStorage("externalLinks") private var externalLinks = "browser"

    var body: some View {
        SettingsPage {
            Section("Démarrage") {
                Toggle("Ouvrir Ruche à l'ouverture de session",
                       isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                Toggle("Démarrer masquée", isOn: $startHidden)
                Caption("Pour l'ouverture de session, place Ruche dans le dossier Applications.")
            }
            Section("Liens") {
                Picker("Ouvrir les liens externes dans", selection: $externalLinks) {
                    Text("Le navigateur par défaut").tag("browser")
                    Text("Une fenêtre Ruche").tag("ruche")
                }
                Caption("Les pages de connexion (Google, Facebook…) et les pages du service lui-même restent toujours dans Ruche.")
            }
            Section("Barre des menus") {
                Toggle("Afficher l'icône avec le total des non-lus", isOn: $showMenuBar)
            }
            UpdatesSettingsSection(updater: Updater.shared)
            Section("Veille des services") {
                Picker("Mettre en veille les services inactifs", selection: $minutes) {
                    Text("Jamais").tag(0)
                    Text("Après 5 min").tag(5)
                    Text("Après 10 min").tag(10)
                    Text("Après 30 min").tag(30)
                    Text("Après 1 h").tag(60)
                }
                Caption("Les services « Toujours actif » ne sont jamais mis en veille. Un service en veille ne reçoit plus de notifications (sauf Gmail, relevé toutes les 2 min) ; il se réveille dès que tu cliques dessus.")
            }
        }
    }
}

struct AppearanceSettings: View {
    @AppStorage("sidebarWidth") private var sidebarWidth = Layout.defaultSidebarWidth
    @AppStorage("iconSizeBias") private var iconBias = 0.0

    var body: some View {
        SettingsPage {
            Section("Barre latérale") {
                LabeledContent("Largeur") {
                    HStack {
                        Slider(value: $sidebarWidth, in: Layout.sidebarRange, step: 2)
                        Text("\(Int(sidebarWidth)) px").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Picker("Icônes", selection: $iconBias) {
                    Text("Petites").tag(-8.0)
                    Text("Normales").tag(0.0)
                    Text("Grandes").tag(8.0)
                    Text("Très grandes").tag(16.0)
                }
                .pickerStyle(.segmented)
                Caption("Tu peux aussi glisser le bord droit de la barre (double-clic = 68 px).")
            }
        }
    }
}

struct NotificationSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsPage {
            Section("Modes") {
                Toggle("Mode silencieux (notifications sans son)", isOn: $model.silentMode)
                Toggle("Ne pas déranger", isOn: Binding(get: { model.doNotDisturb },
                                                        set: { _ in model.toggleDoNotDisturb() }))
                Caption(model.doNotDisturbDescription + ". Pour une durée précise, fais un clic droit sur la cloche de la barre latérale.")
            }
            Section("Autorisations macOS") {
                Text(model.notificationStatus)
                HStack {
                    Button("Demander l'autorisation") { model.requestNotificationPermission() }
                    Button("Réglages Système…") { model.openNotificationSettings() }
                }
                Caption("Les notifications et le son se règlent aussi service par service, dans l'onglet Services.")
            }
        }
        .onAppear { model.refreshNotificationStatus() }
    }
}

struct SecuritySettings: View {
    @AppStorage("lockEnabled") private var lockEnabled = false
    @AppStorage("lockOnScreenLock") private var lockOnScreenLock = true
    @AppStorage("lockAfterMinutes") private var lockAfterMinutes = 15

    var body: some View {
        SettingsPage {
            Section("Touch ID") {
                Toggle("Verrouiller Ruche automatiquement", isOn: $lockEnabled)
                Group {
                    Toggle("Quand le Mac est verrouillé", isOn: $lockOnScreenLock)
                    Picker("Après une inactivité de", selection: $lockAfterMinutes) {
                        Text("Jamais").tag(0)
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 h").tag(60)
                    }
                }
                .disabled(!lockEnabled)
                Caption("Inactivité = Ruche n'est pas au premier plan. Le verrouillage automatique s'applique aussi au lancement. Le cadenas de la barre latérale (⌃⌘L) verrouille à tout moment. Si Touch ID n'est pas disponible, le mot de passe du Mac est demandé. Tant que Ruche est verrouillée, les notifications n'affichent pas le contenu des messages.")
            }
        }
    }
}

struct AdvancedSettings: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsPage {
            Section("Configuration") {
                HStack {
                    Button("Exporter…") { model.exportConfig() }
                    Button("Importer…") { model.importConfig() }
                }
                Caption("Exporte la liste des services, leurs réglages et leurs icônes personnalisées. Les sessions ne sont jamais exportées : après un import, il faut se reconnecter à chaque service.")
            }
            Section("Recettes") {
                ForEach(model.recipes) { recipe in
                    LabeledContent(recipe.name) {
                        Text(recipe.isBuiltIn ? (recipe.script == nil ? "intégrée · générique" : "intégrée") : "perso")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Ouvrir le dossier des recettes") { model.revealRecipesFolder() }
                    Button("Recharger les recettes") { model.reloadRecipes() }
                }
                Caption("Une recette = un dossier avec recipe.json et recipe.js (voir l'exemple « _exemple » et RECETTES.md). Une recette perso avec le même id remplace l'intégrée. Recharger relance les services chargés.")
            }
            Section("Données") {
                Button("Afficher le dossier des données dans le Finder") { model.revealDataFolder() }
                Caption("Liste des services et icônes. Les sessions de connexion sont gardées par WebKit, isolées par service.")
            }
        }
    }
}

// MARK: - Onglet Services : liste à gauche, réglages à droite

struct ServicesSettings: View {
    @EnvironmentObject var model: AppModel

    private var selection: Binding<UUID?> {
        Binding(get: { model.settingsSelection }, set: { model.selectInSettings($0) })
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: selection) {
                    ForEach(model.services) { service in
                        HStack(spacing: 8) {
                            ServiceIcon(service: service)
                                .frame(width: 20, height: 20)
                            Text(service.name).lineLimit(1)
                            Spacer()
                            if let color = service.tint.color {
                                Circle().fill(color).frame(width: 8, height: 8)
                            }
                        }
                        .tag(service.id)
                    }
                    .onMove { from, to in model.moveServices(from: from, to: to) }
                }
                .listStyle(.sidebar)
                Divider()
                HStack(spacing: 2) {
                    Button { model.beginSettingsAdd() } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .help("Ajouter un service")
                    Button {
                        if let id = model.settingsSelection, let s = model.service(id) { model.confirmDelete(s) }
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(model.settingsSelection == nil)
                    .help("Supprimer le service sélectionné")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 200)

            Divider()

            Group {
                if model.settingsAdding {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Ajouter un service").font(.headline).padding(.horizontal, 20).padding(.top, 16)
                            PresetGrid(columns: 4).padding(.horizontal, 20)
                            ServiceForm().formStyle(.grouped)
                            HStack {
                                Spacer()
                                Button("Annuler") { model.cancelSettingsEdit() }
                                Button("Ajouter") { model.commitSettingsEdit() }
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(!model.draftIsValid)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                        }
                    }
                } else if let id = model.settingsSelection, model.service(id) != nil {
                    VStack(spacing: 0) {
                        ServiceForm().formStyle(.grouped)
                        Divider()
                        HStack {
                            Button("Supprimer…", role: .destructive) {
                                if let s = model.service(id) { model.confirmDelete(s) }
                            }
                            Button("Réinitialiser la session…") {
                                if let s = model.service(id) { model.confirmResetSession(s) }
                            }
                            Spacer()
                            Button("Annuler les modifications") { model.selectInSettings(id) }
                                .disabled(!model.draftIsDirty)
                            Button("Enregistrer") { model.commitSettingsEdit() }
                                .keyboardShortcut(.defaultAction)
                                .disabled(!model.draftIsDirty || !model.draftIsValid)
                        }
                        .padding(12)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "square.stack").font(.system(size: 34)).foregroundStyle(.secondary)
                        Text("Sélectionne un service à gauche, ou ajoute-en un avec +.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 520)
        .onAppear {
            if model.settingsSelection == nil, !model.settingsAdding, let first = model.services.first {
                model.selectInSettings(first.id)
            }
        }
    }
}
