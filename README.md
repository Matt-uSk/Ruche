# Ruche

Petite alternative native à Ferdium : tes services web dans une barre latérale,
sur WebKit (pas de Chromium), avec un stockage isolé par service.

## Compiler

Prérequis : macOS 14+ et les Command Line Tools (ou Xcode).

```bash
./build.sh
open build/Ruche.app
```

### Signature stable (recommandé)

Avec une signature ad hoc, chaque recompilation change l'identité de l'app : macOS
redemande alors l'accès au trousseau (« Clé maîtresse WebCrypto ») et les autorisations.
Pour l'éviter, crée une fois un certificat de signature local :

1. Trousseaux d'accès → menu Trousseaux d'accès → Assistant de certification →
   Créer un certificat…
2. Nom : `Ruche Local`, Type d'identité : Racine auto-signée, Type de certificat : Signature de code.
3. Relance `./build.sh` : il l'utilisera automatiquement.

## Fonctionnement

- **Stockage isolé** : chaque service a ses propres cookies/session. Tu peux ajouter
  plusieurs Gmail ou WhatsApp avec des comptes différents (pastille de couleur pour les distinguer).
- **Veille automatique** : les services inactifs sont déchargés après le délai choisi
  dans les Réglages (10 min par défaut). « Toujours actif » = jamais mis en veille.
  Au lancement, seuls le service affiché et les « toujours actifs » sont chargés.
- **Notifications** : relayées en notifications macOS ; un clic ouvre la conversation.
  Pour Gmail, active les notifications de bureau dans les paramètres Gmail.
- **Badges** : nombre de non-lus lu dans le titre de la page, total sur l'icône du Dock.
- **Zoom par service** : menu Présentation, clic droit sur l’icône > Zoom, ou ⌘+ / ⌘- / ⌘0 (mémorisé par service).
- **Raccourcis** : ⌘1…⌘9 pour changer de service, ⌘R recharger, ⌘[ / ⌘] précédent/suivant,
  ⇧⌘N ajouter un service. Clic droit sur une icône : recharger, veille, ordre, modifier, supprimer.
- **Barre latérale** : glisse son bord droit pour changer la taille des icônes (double-clic = taille par défaut).
- **Ne pas déranger** : cloche en bas de la barre ; clic = activer/désactiver, clic droit = pour une durée.
- **Réorganiser** : glisse une icône de service vers le haut ou le bas.
- **Mode silencieux** : clic droit sur la cloche (ou menu Services) ; notifications sans son.
- **Touch ID** : Réglages > Sécurité ; verrouillage quand le Mac se verrouille et/ou après inactivité ; bouton cadenas ou ⌃⌘L pour verrouiller tout de suite (même sans verrouillage auto).
- **Gmail en veille** : relevé du flux de la boîte de réception toutes les 2 min (compteur + notification des nouveaux mails) sans charger la page.
- **Par service** : icône personnalisée, notifications et son activables séparément (Modifier… ou clic droit).
- **Réglages > Général** : ouverture de session, démarrage masqué, icône dans la barre des menus.
- **Réglages > Configuration** : export / import des services (sans les sessions).
- **Recettes** : compteurs adaptés par service (WhatsApp, Infomaniak…) et recettes perso partageables — voir RECETTES.md.
- **Réveil périodique** (par service) : un service en veille se réveille ~1 min toutes les X min pour relever ses non-lus ; notification si le compteur augmente.
- Fermer la fenêtre ne quitte pas l'app (⌘Q pour quitter).

Données : `~/Library/Application Support/Ruche/` (liste des services et icônes).
Supprimer un service efface aussi sa session.
