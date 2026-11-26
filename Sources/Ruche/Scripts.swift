/// JavaScript injecté dans les pages des services.
enum Scripts {
    /// Remplace l'API Notification du web : chaque notification est relayée à l'app,
    /// qui la transforme en notification macOS. Un clic dessus rappelle le onclick de la page
    /// (ce qui ouvre la bonne conversation dans WhatsApp, Messenger, etc.).
    static let notificationShim = #"""
    (function () {
      if (window.__rucheInstalled) return;
      window.__rucheInstalled = true;
      const post = (m) => { try { window.webkit.messageHandlers.ruche.postMessage(m); } catch (e) {} };
      const live = {};
      const order = [];
      window.__rucheClick = function (id) {
        const n = live[id];
        if (!n) return;
        const ev = new Event("click", { cancelable: true });
        try { n.dispatchEvent(ev); } catch (e) {}
        try { if (typeof n.onclick === "function") n.onclick(ev); } catch (e) {}
      };
      class RucheNotification extends EventTarget {
        constructor(title, options) {
          super();
          options = options || {};
          this.title = String(title || "");
          this.body = String(options.body || "");
          this.tag = options.tag || "";
          this.icon = options.icon || "";
          this.data = options.data;
          this.silent = !!options.silent;
          this.onclick = null; this.onshow = null; this.onclose = null; this.onerror = null;
          const id = Math.random().toString(36).slice(2) + Date.now().toString(36);
          live[id] = this;
          order.push(id);
          if (order.length > 50) { delete live[order.shift()]; }
          post({ type: "notification", id: id, title: this.title, body: this.body, tag: String(this.tag) });
          setTimeout(() => {
            const ev = new Event("show");
            try { this.dispatchEvent(ev); } catch (e) {}
            if (typeof this.onshow === "function") this.onshow(ev);
          }, 0);
        }
        close() {}
        static get permission() { return "granted"; }
        static requestPermission(cb) {
          if (typeof cb === "function") cb("granted");
          return Promise.resolve("granted");
        }
      }
      RucheNotification.maxActions = 0;
      try {
        Object.defineProperty(window, "Notification", { value: RucheNotification, writable: true, configurable: true });
      } catch (e) { window.Notification = RucheNotification; }
      if (window.ServiceWorkerRegistration && ServiceWorkerRegistration.prototype) {
        ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
          new RucheNotification(title, options);
          return Promise.resolve();
        };
      }
      if (navigator.permissions && navigator.permissions.query) {
        const orig = navigator.permissions.query.bind(navigator.permissions);
        navigator.permissions.query = function (d) {
          if (d && d.name === "notifications") {
            return Promise.resolve({ state: "granted", status: "granted", onchange: null,
                                     addEventListener() {}, removeEventListener() {} });
          }
          return orig(d);
        };
      }
    })();
    """#

    /// Calcule le nombre de non-lus et le remonte à l'app toutes les 3 s (si changement).
    /// Sources : API Badging (navigator.setAppBadge), titre de la page "(3) …",
    /// et pour WhatsApp, les pastilles de non-lus de la liste des discussions.
    static let badgeReporter = #"""
    (function () {
      if (window.__rucheBadge) return;
      window.__rucheBadge = true;
      const post = (n) => { try { window.webkit.messageHandlers.ruche.postMessage({ type: "badge", count: n }); } catch (e) {} };
      let appBadge = null, last = null;
      try {
        navigator.setAppBadge = function (n) { appBadge = (n === undefined) ? -1 : (Number(n) || 0); check(); return Promise.resolve(); };
        navigator.clearAppBadge = function () { appBadge = 0; check(); return Promise.resolve(); };
      } catch (e) {}
      function fromTitle() {
        const t = document.title || "";
        const m = t.match(/\((\d+)\)/);
        if (m) return parseInt(m[1], 10);
        if (/^[•●]/.test(t)) return -1;
        return 0;
      }
      function fromWhatsApp() {
        if (!location.host.endsWith("whatsapp.com")) return 0;
        const side = document.querySelector("#pane-side");
        if (!side) return 0;
        let total = 0;
        side.querySelectorAll("span[aria-label]").forEach((el) => {
          const label = el.getAttribute("aria-label") || "";
          if (/unread|non lu|ungelesen|non lett|no le[ií]d/i.test(label)) {
            const n = parseInt((el.textContent || "").trim(), 10);
            if (!isNaN(n)) total += n;
          }
        });
        return total;
      }
      function check() {
        if (window.__rucheRecipeBadge) return; // une recette gère le compteur
        const values = [fromTitle(), fromWhatsApp()];
        if (appBadge !== null) values.push(appBadge);
        let n = Math.max.apply(null, values);
        if (n === 0 && values.indexOf(-1) !== -1) n = -1;
        if (n !== last) { last = n; post(n); }
      }
      setInterval(check, 3000);
      document.addEventListener("DOMContentLoaded", check);
    })();
    """#

    /// Renvoie l'URL de la meilleure icône déclarée par la page (apple-touch-icon en priorité).
    static let bestIcon = #"""
    (function () {
      const links = Array.from(document.querySelectorAll(
        'link[rel~="icon"], link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]'));
      let best = null, bestSize = -1;
      for (const l of links) {
        if (!l.href || l.href.toLowerCase().endsWith(".svg")) continue;
        let size = 0;
        const m = (l.getAttribute("sizes") || "").match(/(\d+)x/);
        if (m) size = parseInt(m[1], 10);
        if ((l.rel || "").includes("apple-touch-icon")) size = Math.max(size, 180);
        if (size > bestSize) { bestSize = size; best = l.href; }
      }
      return best || (location.origin + "/favicon.ico");
    })();
    """#
}
