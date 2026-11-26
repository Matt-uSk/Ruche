# Changelog

## 0.8.7

- Drag and drop files from the Finder into WhatsApp and Messenger (and any other service)
- WhatsApp / Messenger: thin, discreet scrollbars instead of light system ones

## 0.8.0

- Built-in updater: checks GitHub Releases (automatically once a day, or Ruche › Check for Updates…), shows what's new, then downloads, verifies (SHA-256 + app identifier), replaces and relaunches Ruche — administrator password only if needed. Stable or beta channel, “Skip this version”
- New “About” settings tab: version, updates, credits, links and Ko-fi

## 0.7.1

- “Add service” grid: services grouped by category (Messaging, Social, Mail, Productivity, Other) with a search field
- Recipes: new optional `category` field
- Shared Facebook links (and other non-login Facebook / Discord pages) now open in the default browser instead of a Ruche window

## 0.7.0

First public release.

- Web services in a sidebar, rendered with WebKit (no Chromium), each with its own isolated storage — several accounts of the same service side by side
- Automatic hibernation of inactive services, “Always on” per service, optional periodic wake-up per service
- Gmail unread count and new-mail notifications while hibernated (inbox Atom feed, no page loaded)
- Native notifications (click opens the conversation), service icon attached, per-service notifications and sound, Do Not Disturb (timed), silent mode
- Unread badges in the sidebar, Dock and optional menu bar icon
- Recipes: per-service unread counters (WhatsApp, Infomaniak Mail…) and shareable custom recipes
- Touch ID lock (on Mac lock, after inactivity, or instantly), message previews hidden while locked
- Per-service zoom, custom icon, colour tag, drag-and-drop reordering, resizable sidebar
- External links open in the default browser (setting: or in a Ruche window); login pages stay in-app
- Reset a service's session (keeps its settings); no Keychain prompt (Ruche provides WebKit's WebCrypto key)
- Tabbed settings with a Services list/detail editor, launch at login, start hidden, configuration export/import (sessions are never exported)
