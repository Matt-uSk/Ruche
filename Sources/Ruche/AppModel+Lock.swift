import AppKit
import LocalAuthentication

/// Verrouillage de l'app par Touch ID (ou mot de passe du Mac).
@MainActor
final class LockManager: ObservableObject {
    @Published private(set) var isLocked = false
    private var resignedAt: Date?
    private var authInProgress = false
    private var observers: [NSObjectProtocol] = []
    var onLockChange: ((Bool) -> Void)?

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "lockEnabled") }
    private var lockOnScreenLock: Bool { UserDefaults.standard.bool(forKey: "lockOnScreenLock") }
    private var lockAfterMinutes: Int { UserDefaults.standard.integer(forKey: "lockAfterMinutes") }

    func start() {
        UserDefaults.standard.register(defaults: ["lockOnScreenLock": true, "lockAfterMinutes": 15])
        if Self.enabled { lock() }

        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, Self.enabled, self.lockOnScreenLock else { return }
                self.lock()
            }
        })

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resignedAt = Date() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Self.enabled, self.lockAfterMinutes > 0, let resigned = self.resignedAt,
                   Date().timeIntervalSince(resigned) >= Double(self.lockAfterMinutes) * 60 {
                    self.lock()
                }
                self.resignedAt = nil
                if self.isLocked { self.authenticate() }
            }
        })
    }

    func lock() {
        guard !isLocked else { return }
        isLocked = true
        onLockChange?(true)
    }

    /// Verrouille immédiatement (bouton, menu ou raccourci), même si le verrouillage automatique est désactivé.
    func lockNow() {
        lock()
    }

    func authenticate() {
        guard isLocked, !authInProgress else { return }
        authInProgress = true
        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authInProgress = false
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "déverrouiller Ruche") { [weak self] success, _ in
            Task { @MainActor in
                guard let self else { return }
                self.authInProgress = false
                if success {
                    self.isLocked = false
                    self.onLockChange?(false)
                }
            }
        }
    }
}
