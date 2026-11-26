import Foundation
import WebKit

/// Relève les Gmail en veille via le flux Atom de la boîte de réception, en réutilisant
/// la session du service (ses cookies) : pas de vue web chargée, pas de mot de passe stocké.
extension AppModel {
    func checkGmailFeeds() async {
        for s in services where s.isGmail && isAsleep(s.id) {
            await checkGmail(s)
        }
    }

    /// - Parameter baselineOnly: mémorise les mails présents sans notifier (au moment de la mise en veille).
    func checkGmail(_ service: Service, baselineOnly: Bool = false) async {
        let store = WKWebsiteDataStore(forIdentifier: service.id)
        let cookies = await store.httpCookieStore.allCookies().filter {
            let domain = $0.domain.lowercased()
            return domain.hasSuffix("google.com")
        }
        guard !cookies.isEmpty,
              let url = URL(string: "https://mail.google.com/mail/u/0/feed/atom") else { return }

        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue(AppModel.userAgent, forHTTPHeaderField: "User-Agent")

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        guard let (data, response) = try? await URLSession(configuration: config).data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: data, encoding: .utf8) else { return }

        let feed = GmailAtom.parse(xml)
        setBadge(feed.unread, for: service.id)

        let ids = Set(feed.entries.map(\.id))
        if baselineOnly {
            gmailSeen[service.id] = ids
        } else if let seen = gmailSeen[service.id] {
            // Nouveaux mails depuis le dernier relevé → notification (la plus récente en premier).
            for entry in feed.entries where !seen.contains(entry.id) {
                notify(from: service, title: entry.author.isEmpty ? "Nouveau mail" : entry.author,
                       body: entry.title, jsID: "")
            }
            gmailSeen[service.id] = seen.union(ids)
        } else {
            gmailSeen[service.id] = ids // premier relevé : on mémorise sans notifier
        }
    }
}

enum GmailAtom {
    struct Entry { let id: String; let title: String; let author: String }
    struct Feed { let unread: Int; let entries: [Entry] }

    static func parse(_ xml: String) -> Feed {
        let unread = Int(firstMatch(xml, tag: "fullcount") ?? "") ?? 0
        let chunks = xml.components(separatedBy: "<entry>").dropFirst()
        let entries: [Entry] = chunks.compactMap { chunk in
            guard let id = firstMatch(chunk, tag: "id") else { return nil }
            let title = decode(firstMatch(chunk, tag: "title") ?? "")
            let author = decode(firstMatch(chunk, tag: "name") ?? "")
            return Entry(id: id, title: title, author: author)
        }
        return Feed(unread: unread, entries: entries)
    }

    private static func firstMatch(_ text: String, tag: String) -> String? {
        guard let start = text.range(of: "<\(tag)>"),
              let end = text.range(of: "</\(tag)>", range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
