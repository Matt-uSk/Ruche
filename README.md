<p align="center"><img src="docs/icon.png" width="128" alt="Ruche"></p>

<h1 align="center">Ruche</h1>

<p align="center">
  <b>Your web messengers and mailboxes in one native macOS window — without Chromium</b><br>
  Native macOS app — Apple Silicon &amp; Intel, macOS 14+, zero dependencies
</p>

<p align="center">
  <a href="https://github.com/Matt-uSk/Ruche/releases/latest"><img src="https://img.shields.io/github/v/release/Matt-uSk/Ruche?label=Release&color=2ea44f" alt="Release"></a>
  <a href="https://github.com/Matt-uSk/Ruche/releases"><img src="https://img.shields.io/github/downloads/Matt-uSk/Ruche/total?label=Downloads&color=0a84ff" alt="Downloads"></a>
  <a href="https://github.com/Matt-uSk/Ruche/stargazers"><img src="https://img.shields.io/github/stars/Matt-uSk/Ruche?label=Stars&color=f5a623&logo=github&logoColor=white" alt="Stars"></a>
  <a href="#installation"><img src="https://img.shields.io/badge/macOS-14%2B-8e8e93?logo=apple&logoColor=white" alt="macOS 14+"></a>
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/Changelog-view-6f42c1" alt="Changelog"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-0075ca" alt="MIT"></a>
  <a href="https://ko-fi.com/mattusk"><img src="https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-FF5E5B?logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
</p>

<p align="center">🇫🇷 <a href="README.fr.md">Version française</a></p>

Ruche (“beehive” in French) is a lightweight alternative to Ferdium / Franz / Rambox: WhatsApp, Messenger, Discord, Gmail, Trello, Infomaniak Mail… side by side in a sidebar. Instead of one Chromium per service, Ruche uses **WebKit**, the engine already built into macOS. In our measurements against Ferdium with the same services: **about 4× less CPU and energy, half the memory**.

## Origin and credits

- **Inspired by [Ferdium](https://github.com/ferdium/ferdium-app)** (sidebar layout, recipes, hibernation). Ruche is a native Swift/SwiftUI rewrite; no Ferdium application code is reused.
- The built-in WhatsApp and Infomaniak Mail recipes are adapted from **[Ferdium recipes](https://github.com/ferdium/ferdium-recipes)** (MIT, © Ferdium Contributors).
- **Most of the code was written by [Claude](https://claude.ai) (Anthropic)**.

## Features

- **Isolated storage per service**: several accounts of the same service (e.g. 3 Gmail, 2 WhatsApp) side by side, with colour tags or custom icons
- **Hibernation** of inactive services (delay of your choice), **Always on** per service, optional **periodic wake-up** per service to refresh unread counts
- **Gmail while hibernated**: unread count and new-mail notifications every 2 min via the inbox feed — no page loaded, no password stored
- **Native notifications**: click opens the right conversation, service icon attached, notifications and sound per service, **Do Not Disturb** (1 h, 3 h, until tomorrow…), **silent mode**
- **Unread badges** in the sidebar, the Dock and an optional menu bar icon
- **Recipes**: per-service unread counters (WhatsApp: exact count, archived chats excluded, muted chats as a dot) and **custom recipes** you can write and share — see [RECETTES.md](RECETTES.md)
- **Touch ID lock**: when the Mac locks, after inactivity, or instantly (padlock button, ⌃⌘L); message previews hidden while locked
- Per-service **zoom**, drag-and-drop **reordering**, resizable sidebar (drag its edge)
- **Tabbed settings** (General, Appearance, Services, Notifications, Security, Advanced) with a list/detail service editor
- External links open in your **default browser** (or in a Ruche window, your choice)
- **Built-in updater** from GitHub Releases (checksum-verified, one click)
- Launch at login, start hidden, configuration **export / import** (sessions are never exported)
- Shortcuts: ⌘1…⌘9 switch service, ⌘R reload, ⌘[ / ⌘] back/forward, ⌘+ / ⌘- / ⌘0 zoom, ⇧⌘N add a service

## Installation

Download the latest version from [Releases](https://github.com/Matt-uSk/Ruche/releases), unzip it and drag **Ruche.app** into `/Applications`.

The app is ad-hoc signed (no Apple Developer ID), so macOS blocks it on first launch. Remove the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Ruche.app
```

Universal app (Apple Silicon and Intel), macOS 14 or later.

## Build from source

Requires macOS 14+ and the Xcode Command Line Tools (or Xcode).

```bash
git clone https://github.com/Matt-uSk/Ruche.git
cd Ruche
./build.sh            # universal app in build/Ruche.app
NATIVE=1 ./build.sh   # faster: your Mac's architecture only
```

Optional: create a code-signing certificate named `Ruche Local` (Keychain Access › Certificate Assistant › Create a Certificate…, *Self-Signed Root*, *Code Signing*). `build.sh` uses it automatically, so macOS stops asking again for Keychain access and permissions after each rebuild.

## Privacy

- Everything stays on your Mac. Sessions (cookies) are kept by WebKit, isolated per service.
- Gmail checks go directly to Google over HTTPS with the existing session; only message identifiers are kept, in memory, to avoid duplicate notifications.
- Service icons in the “add service” grid come from Google's favicon service (it only sees which sites are listed).
- Data: `~/Library/Application Support/Ruche/` (service list, icons, recipes).

## Support

Ruche is free and open source. If it saves your battery, you can [buy me a coffee on Ko-fi](https://ko-fi.com/mattusk) ☕

## License

[MIT](LICENSE)
