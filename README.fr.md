<p align="center"><img src="docs/icon.png" width="128" alt="Ruche"></p>

<h1 align="center">Ruche</h1>

<p align="center">
  <b>Tes messageries et boîtes mail web dans une seule fenêtre macOS native — sans Chromium</b><br>
  App macOS native — Apple Silicon &amp; Intel, macOS 14+, zéro dépendance
</p>

<p align="center">
  <a href="https://github.com/Matt-uSk/Ruche/releases/latest"><img src="https://img.shields.io/github/v/release/Matt-uSk/Ruche?label=Release&color=2ea44f" alt="Release"></a>
  <a href="https://github.com/Matt-uSk/Ruche/releases"><img src="https://img.shields.io/github/downloads/Matt-uSk/Ruche/total?label=T%C3%A9l%C3%A9chargements&color=0a84ff" alt="Téléchargements"></a>
  <a href="#installation"><img src="https://img.shields.io/badge/macOS-14%2B-8e8e93?logo=apple&logoColor=white" alt="macOS 14+"></a>
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/Changelog-voir-6f42c1" alt="Changelog"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/Licence-MIT-0075ca" alt="MIT"></a>
  <a href="https://ko-fi.com/mattusk"><img src="https://img.shields.io/badge/Ko--fi-Offre%20moi%20un%20caf%C3%A9-FF5E5B?logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
</p>

<p align="center">🇬🇧 <a href="README.md">English version</a></p>

Ruche est une alternative légère à Ferdium / Franz / Rambox : WhatsApp, Messenger, Discord, Gmail, Trello, Infomaniak Mail… côte à côte dans une barre latérale. Au lieu d'un Chromium par service, Ruche utilise **WebKit**, le moteur déjà intégré à macOS. Mesuré face à Ferdium avec les mêmes services : **environ 4 fois moins de CPU et d'énergie, 2 fois moins de mémoire**.

## Origine et crédits

- **Inspiré de [Ferdium](https://github.com/ferdium/ferdium-app)** (disposition de la barre latérale, recettes, mise en veille). Ruche est une réécriture native en Swift/SwiftUI ; aucun code de l'application Ferdium n'est réutilisé.
- Les recettes intégrées WhatsApp et Infomaniak Mail sont adaptées des **[recettes Ferdium](https://github.com/ferdium/ferdium-recipes)** (MIT, © Ferdium Contributors).
- **La majorité du code a été écrite par [Claude](https://claude.ai) (Anthropic)**.

## Fonctionnalités

- **Stockage isolé par service** : plusieurs comptes du même service (ex. 3 Gmail, 2 WhatsApp) côte à côte, avec pastilles de couleur ou icônes personnalisées
- **Mise en veille** des services inactifs (délai au choix), **Toujours actif** par service, **réveil périodique** optionnel par service pour relever les non-lus
- **Gmail en veille** : compteur et notifications des nouveaux mails toutes les 2 min via le flux de la boîte de réception — sans charger la page, sans mot de passe stocké
- **Notifications natives** : un clic ouvre la bonne conversation, icône du service jointe, notifications et son par service, **Ne pas déranger** (1 h, 3 h, jusqu'à demain…), **mode silencieux**
- **Compteurs de non-lus** dans la barre latérale, le Dock et une icône optionnelle dans la barre des menus
- **Recettes** : compteurs adaptés par service (WhatsApp : nombre exact, conversations archivées exclues, sourdine en simple point) et **recettes perso** à écrire et partager — voir [RECETTES.md](RECETTES.md)
- **Verrouillage Touch ID** : au verrouillage du Mac, après inactivité ou immédiatement (cadenas, ⌃⌘L) ; contenu des notifications masqué tant que Ruche est verrouillée
- **Zoom** par service, **réorganisation** par glisser-déposer, barre latérale redimensionnable (glisser son bord)
- **Réglages à onglets** (Général, Apparence, Services, Notifications, Sécurité, Avancé) avec un éditeur de services en liste/détail
- Liens externes ouverts dans ton **navigateur par défaut** (ou dans une fenêtre Ruche, au choix)
- Ouverture à la session, démarrage masqué, **export / import** de la configuration (les sessions ne sont jamais exportées)
- Raccourcis : ⌘1…⌘9 changer de service, ⌘R recharger, ⌘[ / ⌘] précédent/suivant, ⌘+ / ⌘- / ⌘0 zoom, ⇧⌘N ajouter un service

## Installation

Télécharge la dernière version dans les [Releases](https://github.com/Matt-uSk/Ruche/releases), décompresse-la et glisse **Ruche.app** dans `/Applications`.

L'app est signée ad hoc (pas d'Apple Developer ID) : macOS la bloque au premier lancement. Retire une fois l'attribut de quarantaine :

```bash
xattr -dr com.apple.quarantine /Applications/Ruche.app
```

App universelle (Apple Silicon et Intel), macOS 14 ou plus récent.

## Compiler soi-même

Prérequis : macOS 14+ et les Command Line Tools de Xcode (ou Xcode).

```bash
git clone https://github.com/Matt-uSk/Ruche.git
cd Ruche
./build.sh            # app universelle dans build/Ruche.app
NATIVE=1 ./build.sh   # plus rapide : architecture du Mac uniquement
```

Facultatif : crée un certificat de signature nommé `Ruche Local` (Trousseaux d'accès › Assistant de certification › Créer un certificat…, *Racine auto-signée*, *Signature de code*). `build.sh` l'utilise automatiquement, et macOS ne redemande plus l'accès au trousseau ni les autorisations après chaque recompilation.

## Confidentialité

- Tout reste sur ton Mac. Les sessions (cookies) sont gardées par WebKit, isolées par service.
- La relève Gmail interroge directement Google en HTTPS avec la session existante ; seuls des identifiants de messages sont gardés, en mémoire, pour éviter les doublons de notifications.
- Les icônes de la grille d'ajout viennent du service d'icônes de Google (qui voit seulement quels sites sont proposés).
- Données : `~/Library/Application Support/Ruche/` (liste des services, icônes, recettes).

## Soutien

Ruche est gratuite et open source. Si elle sauve ta batterie, tu peux [m'offrir un café sur Ko-fi](https://ko-fi.com/mattusk) ☕

## Licence

[MIT](LICENSE)
