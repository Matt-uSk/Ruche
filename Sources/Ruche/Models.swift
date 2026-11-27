import SwiftUI

enum TintColor: String, Codable, CaseIterable, Identifiable {
    case none, red, orange, yellow, green, blue, purple, pink
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Aucune"
        case .red: return "Rouge"
        case .orange: return "Orange"
        case .yellow: return "Jaune"
        case .green: return "Vert"
        case .blue: return "Bleu"
        case .purple: return "Violet"
        case .pink: return "Rose"
        }
    }

    var color: Color? {
        switch self {
        case .none: return nil
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        }
    }
}

struct Service: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    /// Jamais mis en veille (pour les services dont tu veux les notifications en continu).
    var keepAwake = false
    var notifications = true
    /// Pastille de couleur pour distinguer deux instances du même service.
    var tint: TintColor = .none
    /// Zoom de la page (1.0 = 100 %).
    var zoom: Double = 1.0
    /// Son des notifications pour ce service.
    var sound = true
    /// Icône choisie par l'utilisateur (sinon icône du site).
    var customIcon = false
    /// Réveil périodique quand le service est en veille (0 = jamais), pour relever les non-lus.
    var wakeEveryMinutes = 0
    /// Son de notification propre au service (nil = réglage général).
    var soundName: String? = nil

    var isGmail: Bool { URL(string: url)?.host?.lowercased() == "mail.google.com" }
}

extension Service {
    /// Décodage tolérant : les champs ajoutés au fil des versions prennent leur valeur par défaut.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? false
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? true
        tint = try c.decodeIfPresent(TintColor.self, forKey: .tint) ?? .none
        zoom = try c.decodeIfPresent(Double.self, forKey: .zoom) ?? 1.0
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        customIcon = try c.decodeIfPresent(Bool.self, forKey: .customIcon) ?? false
        wakeEveryMinutes = try c.decodeIfPresent(Int.self, forKey: .wakeEveryMinutes) ?? 0
        soundName = try c.decodeIfPresent(String.self, forKey: .soundName)
    }
}
