import SwiftUI
import UniformTypeIdentifiers

enum Layout {
    static let gutter: CGFloat = 6
    static let contentRadius: CGFloat = 8
    static let defaultSidebarWidth = 68.0
    static let sidebarRange = 44.0...100.0
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("sidebarWidth") private var sidebarWidth = Layout.defaultSidebarWidth

    /// Comme Ferdium : la page monte toujours en haut, les boutons de fenêtre passent par-dessus.
    private var contentTopInset: CGFloat { Layout.gutter }

    var body: some View {
        HStack(spacing: 0) {
            // La barre inclut la marge avec la page : les icônes sont centrées entre
            // le bord de la fenêtre et la carte du service. Le bord droit sert à redimensionner.
            Sidebar()
                .overlay(alignment: .trailing) { SidebarResizer() }
            ZStack {
                WebHost(host: model.hostView)
                if model.services.isEmpty {
                    EmptyStateView()
                } else if let id = model.selectedID, model.isAsleep(id) {
                    AsleepView(id: id)
                }
                if let hud = model.zoomHUD {
                    Text(hud)
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Layout.contentRadius))
            .animation(.easeOut(duration: 0.2), value: model.zoomHUD)
            // Comme Ferdium : le service est une « carte » encadrée par la couleur de la barre.
            .padding(.top, contentTopInset)
            .padding(.trailing, Layout.gutter)
            .padding(.bottom, Layout.gutter)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { LockOverlay(lock: model.lock) }
        .ignoresSafeArea()
        .background(WindowConfigurator(model: model))
        .navigationTitle(model.selectedID.flatMap { model.service($0)?.name } ?? "Ruche")
        .sheet(isPresented: $model.showAddSheet) {
            ServiceEditor(original: nil).environmentObject(model)
        }
        .sheet(item: $model.editing) { service in
            ServiceEditor(original: service).environmentObject(model)
        }
        .onAppear {
            model.openMainWindow = { openWindow(id: "main") }
        }
    }
}

/// Bord droit de la barre latérale : glisser pour changer la taille des icônes,
/// double-clic pour revenir à la taille par défaut.
struct SidebarResizer: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("sidebarWidth") private var sidebarWidth = Layout.defaultSidebarWidth

    var body: some View {
        Color.clear
            .frame(width: Layout.gutter)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if model.resizeStartSize == nil { model.resizeStartSize = sidebarWidth }
                        let proposed = (model.resizeStartSize ?? sidebarWidth) + value.translation.width
                        sidebarWidth = min(Layout.sidebarRange.upperBound,
                                           max(Layout.sidebarRange.lowerBound, proposed.rounded()))
                    }
                    .onEnded { _ in model.resizeStartSize = nil }
            )
            .onTapGesture(count: 2) { sidebarWidth = Layout.defaultSidebarWidth }
    }
}

/// Écran de verrouillage (Touch ID ou mot de passe du Mac).
struct LockOverlay: View {
    @ObservedObject var lock: LockManager

    var body: some View {
        if lock.isLocked {
            VStack(spacing: 14) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Ruche est verrouillée").font(.title3)
                Button {
                    lock.authenticate()
                } label: {
                    Label("Déverrouiller", systemImage: "touchid")
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
        }
    }
}

/// Contenu du menu de l'icône dans la barre des menus.
struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ForEach(model.services) { service in
            let count = model.badges[service.id] ?? 0
            Button(service.name + (count > 0 ? "  (\(count))" : count < 0 ? "  •" : "")) {
                model.select(service.id)
                model.showMainWindow()
            }
        }
        Divider()
        Button("Ouvrir Ruche") { model.showMainWindow() }
        Toggle("Ne pas déranger", isOn: Binding(get: { model.doNotDisturb }, set: { _ in model.toggleDoNotDisturb() }))
        Toggle("Mode silencieux", isOn: $model.silentMode)
        Button("Verrouiller") { model.lock.lockNow() }
        Divider()
        Button("Quitter Ruche") { NSApp.terminate(nil) }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.doNotDisturb ? "bell.slash.fill" : "circle.hexagongrid.fill")
            if model.totalUnread > 0 { Text("\(model.totalUnread)") }
        }
    }
}

/// Règle la fenêtre : déplaçable en cliquant-glissant sur la barre latérale.
struct WindowConfigurator: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> WindowConfiguratorView {
        let view = WindowConfiguratorView()
        view.model = model
        return view
    }
    func updateNSView(_ nsView: WindowConfiguratorView, context: Context) {}
}

/// Barre de titre invisible : seuls les boutons de fenêtre natifs restent, posés sur la barre latérale
/// (comme Ferdium). Mesure leur largeur pour que la barre latérale ne soit jamais plus étroite.
final class WindowConfiguratorView: NSView {
    weak var model: AppModel?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = false
        }
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, let zoom = window.standardWindowButton(.zoomButton) else { return }
            let maxX = zoom.convert(zoom.bounds, to: nil).maxX
            if maxX > 0 { self?.model?.trafficLightsWidth = Double(maxX) + 10 }
        }
    }
}

/// Zone vide qui permet de déplacer la fenêtre (la barre de titre est masquée).
struct WindowDragArea: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        } else {
            Color.clear
        }
    }
}

/// Insère la vue AppKit qui contient toutes les vues web.
struct WebHost: NSViewRepresentable {
    let host: NSView
    func makeNSView(context: Context) -> NSView { host }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Aucun service pour l'instant").font(.title3)
            Button("Ajouter un service") { model.beginAdd() }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

struct AsleepView: View {
    @EnvironmentObject var model: AppModel
    let id: UUID
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("\(model.service(id)?.name ?? "Service") est en veille").font(.title3)
            Button("Réveiller") { model.wake(id) }.controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

// MARK: - Barre latérale

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("sidebarWidth") private var width = Layout.defaultSidebarWidth

    var body: some View {
        VStack(spacing: 0) {
            // Place pour les boutons de fenêtre natifs (zone de déplacement de la fenêtre)
            Color.clear.frame(height: 30)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(model.services) { service in
                        ServiceButton(service: service)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
            Button { model.beginAdd() } label: {
                Image(systemName: "plus").font(.system(size: 15, weight: .medium)).frame(width: 36, height: 30)
            }
            .buttonStyle(.plain)
            .help("Ajouter un service")
            Button { model.lock.lockNow() } label: {
                Image(systemName: "lock").font(.system(size: 15)).frame(width: 36, height: 30)
            }
            .buttonStyle(.plain)
            .help("Verrouiller maintenant (⌃⌘L)")
            Button { model.toggleDoNotDisturb() } label: {
                Image(systemName: model.doNotDisturb ? "bell.slash.fill" : "bell")
                    .font(.system(size: 15))
                    .foregroundStyle(model.doNotDisturb ? Color.purple : Color.primary)
                    .overlay(alignment: .bottomTrailing) {
                        if model.silentMode && !model.doNotDisturb {
                            Image(systemName: "speaker.slash.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Color.orange)
                                .offset(x: 4, y: 2)
                        }
                    }
                    .frame(width: 36, height: 30)
            }
            .buttonStyle(.plain)
            .help(model.doNotDisturbDescription + (model.silentMode ? " · Mode silencieux" : "") + " — clic droit pour plus d'options")
            .contextMenu {
                Toggle("Mode silencieux (notifications sans son)", isOn: $model.silentMode)
                Divider()
                Text("Ne pas déranger")
                Button("Pendant 1 heure") { model.enableDoNotDisturb(hours: 1) }
                Button("Pendant 3 heures") { model.enableDoNotDisturb(hours: 3) }
                Button("Jusqu'à demain 8 h") { model.doNotDisturbUntilTomorrowMorning() }
                Button("Jusqu'à réactivation") { model.setDoNotDisturb(until: .distantFuture) }
                if model.doNotDisturb {
                    Divider()
                    Button("Désactiver") { model.setDoNotDisturb(until: nil) }
                }
            }
            SettingsLink {
                Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 36, height: 30)
            }
            .buttonStyle(.plain)
            .help("Réglages")
            .padding(.bottom, 10)
        }
        .frame(width: width + Layout.gutter)
        .background(WindowDragArea())
    }
}

struct ServiceButton: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("sidebarWidth") private var width = Layout.defaultSidebarWidth
    @AppStorage("iconSizeBias") private var iconBias = 0.0
    let service: Service

    private var tile: CGFloat { width - 10 }
    private var iconSize: CGFloat { min(tile - 6, max(16, width / 2 + iconBias)) }

    var body: some View {
        let selected = model.selectedID == service.id
        let asleep = model.isAsleep(service.id)

        Button { model.select(service.id) } label: {
            ServiceIcon(service: service)
                .frame(width: iconSize, height: iconSize)
                .overlay(alignment: .bottomTrailing) {
                    if let color = service.tint.color {
                        let dot = max(8, iconSize * 0.3)
                        Circle().fill(color)
                            .frame(width: dot, height: dot)
                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                            .offset(x: dot * 0.25, y: dot * 0.25)
                    }
                }
                .frame(width: tile, height: tile)
                .background(RoundedRectangle(cornerRadius: tile * 0.22)
                    .fill(selected ? Color.primary.opacity(0.12) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: tile * 0.22)
                    .strokeBorder(selected ? Color.primary.opacity(0.10) : Color.clear, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    BadgeView(count: model.badges[service.id] ?? 0)
                }
                .opacity(asleep && !selected ? 0.45 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(service.name + (asleep ? " (en veille)" : ""))
        .scaleEffect(model.draggingID == service.id ? 1.08 : 1)
        .shadow(color: .black.opacity(model.draggingID == service.id ? 0.35 : 0), radius: 6, y: 2)
        .zIndex(model.draggingID == service.id ? 1 : 0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { value in
                    model.dragService(service.id, translation: value.translation.height, rowHeight: tile + 2)
                }
                .onEnded { _ in model.endDrag() }
        )
        .contextMenu {
            Button("Recharger") { model.reload(service.id) }
            if asleep {
                Button("Réveiller") { model.wake(service.id) }
            } else {
                Button("Mettre en veille") { model.hibernate(service.id) }
            }
            if service.isGmail && asleep {
                Button("Relever les mails maintenant") { Task { await model.checkGmail(service) } }
            }
            Toggle("Notifications", isOn: Binding(get: { service.notifications },
                                                  set: { _ in model.toggleNotifications(service.id) }))
            Toggle("Son des notifications", isOn: Binding(get: { service.sound },
                                                          set: { _ in model.toggleSound(service.id) }))
                .disabled(!service.notifications)
            Menu("Zoom (\(Int((service.zoom * 100).rounded())) %)") {
                ForEach(AppModel.zoomPresets, id: \.self) { z in
                    Button {
                        model.setZoom(z, for: service.id)
                    } label: {
                        let label = "\(Int((z * 100).rounded())) %"
                        if abs(service.zoom - z) < 0.01 {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }
            Divider()
            Button("Monter") { model.move(service.id, by: -1) }
            Button("Descendre") { model.move(service.id, by: 1) }
            Divider()
            Button("Modifier…") { model.beginEdit(service) }
            Button("Réinitialiser la session…") { model.confirmResetSession(service) }
            Button("Supprimer…", role: .destructive) { model.confirmDelete(service) }
        }
    }
}

struct ServiceIcon: View {
    @EnvironmentObject var model: AppModel
    let service: Service

    var body: some View {
        if let image = model.icons[service.id] {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else if let host = URL(string: service.url)?.host,
                  let url = URL(string: "https://\(host)/favicon.ico") {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    Placeholder(name: service.name)
                }
            }
        } else {
            Placeholder(name: service.name)
        }
    }
}

struct Placeholder: View {
    let name: String
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.25))
            .overlay(Text(String(name.prefix(1)).uppercased()).font(.system(size: 15, weight: .semibold)))
    }
}

struct BadgeView: View {
    let count: Int
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 17, minHeight: 17)
                .background(Capsule().fill(Color.red))
                .overlay(Capsule().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                .offset(x: -2, y: 2)
        } else if count < 0 {
            Circle().fill(Color.red).frame(width: 9, height: 9).offset(x: -4, y: 4)
        }
    }
}

