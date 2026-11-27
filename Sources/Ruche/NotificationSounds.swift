import AppKit

/// Sons de notification : ceux de macOS (/System/Library/Sounds) et ceux ajoutés par
/// l'utilisateur dans ~/Library/Sounds. Le son est joué par Ruche (NSSound) au moment
/// où la notification est envoyée, la notification elle-même partant sans son.
enum NotificationSounds {
    /// Valeur spéciale : son par défaut des notifications macOS.
    static let systemDefault = "__default__"

    static var available: [String] {
        let fm = FileManager.default
        let dirs = [URL(fileURLWithPath: "/System/Library/Sounds"),
                    fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Sounds")]
        var names = Set<String>()
        for dir in dirs {
            for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where ["aiff", "aif", "caf", "wav", "mp3", "m4a"].contains(file.pathExtension.lowercased()) {
                names.insert(file.deletingPathExtension().lastPathComponent)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Son global choisi dans les Réglages.
    static var globalChoice: String {
        UserDefaults.standard.string(forKey: "notificationSound") ?? systemDefault
    }

    /// Son effectif pour un service (son propre choix, sinon le réglage général).
    static func resolved(for service: Service) -> String {
        service.soundName ?? globalChoice
    }

    private static var current: NSSound?

    static func play(_ name: String) {
        guard name != systemDefault, let sound = NSSound(named: NSSound.Name(name)) else {
            NSSound.beep()
            return
        }
        current?.stop()
        current = sound
        sound.play()
    }

    static func label(_ name: String) -> String {
        name == systemDefault ? "Par défaut (macOS)" : name
    }
}
