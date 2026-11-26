import Foundation

// MARK: - Recettes de services
//
// Une recette décrit un service (nom, URL, icône) et peut fournir un script qui compte
// les non-lus directement dans la page. Recettes intégrées + recettes perso dans
// ~/Library/Application Support/Ruche/Recipes/<dossier>/ (recipe.json + recipe.js).
// Format documenté dans RECETTES.md. Une recette perso de même id remplace l'intégrée.

struct RecipeManifest: Codable {
    var id: String
    var name: String
    var url: String
    /// Hôtes sur lesquels la recette s'applique (sous-domaines inclus).
    var matchHosts: [String]
    var keepAwake: Bool?
    var iconDomain: String?
    var iconURL: String?
    var author: String?
    var version: String?
    /// Catégorie dans la grille d'ajout : messaging, social, mail, productivity, other (ou texte libre).
    var category: String?
}

struct Recipe: Identifiable {
    var manifest: RecipeManifest
    /// Script de comptage (nil = détection générique par le titre de la page).
    var script: String?
    var isBuiltIn: Bool

    var id: String { manifest.id }
    var name: String { manifest.name }
    var url: String { manifest.url }
    var keepAwake: Bool { manifest.keepAwake ?? false }
    var category: String { manifest.category ?? "other" }

    /// Icône 64 px pour la grille d'ajout.
    var iconURL: URL? {
        if let explicit = manifest.iconURL { return URL(string: explicit) }
        guard let host = manifest.iconDomain ?? URL(string: url)?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }

    func matches(host: String) -> Bool {
        let h = host.lowercased()
        return manifest.matchHosts.contains { h == $0 || h.hasSuffix("." + $0) }
    }
}

enum RecipeLibrary {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ruche/Recipes", isDirectory: true)
    }

    /// Recettes intégrées + recettes perso (une recette perso de même id remplace l'intégrée).
    static func loadAll() -> [Recipe] {
        ensureExample()
        var byID: [String: Recipe] = [:]
        var order: [String] = []
        for r in builtIn {
            byID[r.id] = r
            order.append(r.id)
        }
        for r in loadUser() {
            if byID[r.id] == nil { order.append(r.id) }
            byID[r.id] = r
        }
        return order.compactMap { byID[$0] }
    }

    private static func loadUser() -> [Recipe] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return folders.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { folder in
            guard !folder.lastPathComponent.hasPrefix("_"), !folder.lastPathComponent.hasPrefix("."),
                  let data = try? Data(contentsOf: folder.appendingPathComponent("recipe.json")),
                  let manifest = try? JSONDecoder().decode(RecipeManifest.self, from: data) else { return nil }
            let script = try? String(contentsOf: folder.appendingPathComponent("recipe.js"), encoding: .utf8)
            return Recipe(manifest: manifest, script: script, isBuiltIn: false)
        }
    }

    /// Crée un exemple commenté (ignoré grâce au « _ ») pour démarrer une recette perso.
    private static func ensureExample() {
        let fm = FileManager.default
        let example = directory.appendingPathComponent("_exemple", isDirectory: true)
        guard !fm.fileExists(atPath: example.path) else { return }
        try? fm.createDirectory(at: example, withIntermediateDirectories: true)
        let manifest = """
        {
          "id": "mon-service",
          "name": "Mon service",
          "url": "https://exemple.com",
          "matchHosts": ["exemple.com"],
          "keepAwake": false,
          "iconDomain": "exemple.com",
          "author": "Ton nom",
          "version": "1.0",
          "category": "other"
        }
        """
        let script = """
        // Recette d'exemple : copie ce dossier sans le « _ » initial pour l'activer.
        // API disponible :
        //   Ruche.loop(fonction, ms)        exécute la fonction tout de suite puis toutes les ms (3000 par défaut)
        //   Ruche.setBadge(directs, autres) directs = compteur affiché ; autres > 0 sans directs = simple point
        //   Ruche.safeParseInt(texte)       "12 non lus" → 12 (0 si rien)
        //   Ruche.injectCSS(css)            ajoute du CSS à la page
        Ruche.loop(() => {
          const badge = document.querySelector(".unread-count");
          Ruche.setBadge(badge ? Ruche.safeParseInt(badge.textContent) : 0);
        });
        """
        try? manifest.write(to: example.appendingPathComponent("recipe.json"), atomically: true, encoding: .utf8)
        try? script.write(to: example.appendingPathComponent("recipe.js"), atomically: true, encoding: .utf8)
    }

    // MARK: Recettes intégrées
    // Les scripts WhatsApp et Infomaniak sont adaptés des recettes Ferdium
    // (https://github.com/ferdium/ferdium-recipes, licence MIT, © Ferdium Contributors).

    private static func make(_ id: String, _ name: String, _ url: String, hosts: [String], category: String,
                             keepAwake: Bool = false, iconDomain: String? = nil, iconURL: String? = nil,
                             script: String? = nil) -> Recipe {
        Recipe(manifest: RecipeManifest(id: id, name: name, url: url, matchHosts: hosts, keepAwake: keepAwake,
                                        iconDomain: iconDomain, iconURL: iconURL, author: "Ruche", version: "1.0",
                                        category: category),
               script: script, isBuiltIn: true)
    }

    /// Catégories connues, dans l'ordre d'affichage, avec leur libellé.
    static let categories: [(id: String, label: String)] = [
        ("messaging", "Messageries"),
        ("social", "Réseaux sociaux"),
        ("mail", "Mail"),
        ("productivity", "Productivité"),
        ("other", "Autres"),
    ]

    static func label(forCategory id: String) -> String {
        categories.first { $0.id == id }?.label ?? id
    }

    static let builtIn: [Recipe] = [
        make("whatsapp", "WhatsApp", "https://web.whatsapp.com", hosts: ["web.whatsapp.com"], category: "messaging",
             keepAwake: true, iconDomain: "whatsapp.com", script: whatsAppScript),
        make("messenger", "Messenger", "https://www.messenger.com", hosts: ["messenger.com"], category: "messaging", keepAwake: true),
        make("discord", "Discord", "https://discord.com/app", hosts: ["discord.com"], category: "messaging"),
        make("gmail", "Gmail", "https://mail.google.com", hosts: ["mail.google.com"], category: "mail",
             iconURL: "https://ssl.gstatic.com/ui/v1/icons/mail/rfr/gmail.ico"),
        make("trello", "Trello", "https://trello.com", hosts: ["trello.com"], category: "productivity"),
        make("telegram", "Telegram", "https://web.telegram.org", hosts: ["web.telegram.org"], category: "messaging",
             keepAwake: true, iconDomain: "telegram.org"),
        make("outlook", "Outlook", "https://outlook.live.com/mail", hosts: ["outlook.live.com", "outlook.office.com"], category: "mail"),
        make("proton-mail", "Proton Mail", "https://mail.proton.me", hosts: ["mail.proton.me"], category: "mail", iconDomain: "proton.me"),
        make("infomaniak-mail", "Infomaniak Mail", "https://mail.infomaniak.com", hosts: ["mail.infomaniak.com"], category: "mail",
             iconDomain: "infomaniak.com", script: infomaniakScript),
    ]

    /// Lit la base interne de WhatsApp Web : non-lus exacts, archivées exclues, sourdine à part.
    private static let whatsAppScript = #"""
    let db = null;
    let opening = false;
    const openDB = () => {
      if (opening || !indexedDB.databases) return;
      opening = true;
      indexedDB.databases().then((dbs) => {
        if (!dbs.some((d) => d.name === "model-storage")) { opening = false; return; }
        const req = indexedDB.open("model-storage");
        req.onsuccess = () => {
          db = req.result;
          db.onversionchange = () => { db.close(); db = null; };
          opening = false;
        };
        req.onerror = () => { opening = false; };
      }).catch(() => { opening = false; });
    };
    Ruche.loop(() => {
      if (!db) { openDB(); return; }
      try {
        const query = db.transaction("chat", "readonly").objectStore("chat").getAll();
        query.onsuccess = (event) => {
          let unread = 0, muted = 0;
          for (const chat of event.target.result) {
            if (chat.unreadCount > 0 && !chat.archive) {
              if (chat.muteExpiration != 0 || chat.isAutoMuted) muted += chat.unreadCount;
              else unread += chat.unreadCount;
            }
          }
          Ruche.setBadge(unread, muted);
        };
      } catch (e) { db = null; }
    });
    """#

    /// Pastille du premier dossier (boîte de réception) ; sinon simple point si un autre dossier a des non-lus.
    private static let infomaniakScript = #"""
    Ruche.loop(() => {
      const inbox = document.querySelector(".ws-tree-node-content");
      if (!inbox) return;
      const badge = inbox.querySelector(".ws-tree-node-badge");
      const count = badge ? Ruche.safeParseInt(badge.textContent) : 0;
      let others = 0;
      if (count === 0) {
        const any = document.querySelector(".ws-tree-node-badge");
        others = any ? Ruche.safeParseInt(any.textContent) : 0;
      }
      Ruche.setBadge(count, others);
    });
    """#
}

extension Scripts {
    /// API exposée aux recettes (objet global `Ruche`).
    static let recipeAPI = #"""
    (function () {
      if (window.Ruche) return;
      const post = (m) => { try { window.webkit.messageHandlers.ruche.postMessage(m); } catch (e) {} };
      let last = null;
      window.Ruche = {
        setBadge(direct, indirect) {
          window.__rucheRecipeBadge = true; // la détection générique s'efface
          direct = Number(direct) || 0;
          indirect = Number(indirect) || 0;
          const n = direct > 0 ? direct : (indirect > 0 ? -1 : 0);
          if (n !== last) { last = n; post({ type: "badge", count: n }); }
        },
        loop(fn, ms) {
          const run = () => { try { fn(); } catch (e) { console.error("[Ruche] recette :", e); } };
          run();
          return setInterval(run, ms || 3000);
        },
        safeParseInt(text) {
          const n = parseInt(String(text == null ? "" : text).replace(/[^\d]/g, ""), 10);
          return isNaN(n) ? 0 : n;
        },
        injectCSS(css) {
          const style = document.createElement("style");
          style.textContent = css;
          (document.head || document.documentElement).appendChild(style);
        },
      };
    })();
    """#

    static func wrapRecipe(_ script: String, id rawID: String) -> String {
        let id = rawID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return "(function (Ruche) {\ntry {\n\(script)\n} catch (e) { console.error('[Ruche] recette \(id) :', e); }\n})(window.Ruche);"
    }
}
