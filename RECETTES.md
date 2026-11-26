# Recettes Ruche

Une **recette** décrit un service (nom, URL, icône) et peut fournir un petit script qui
compte les non-lus directement dans la page. Les recettes perso se rangent dans :

```
~/Library/Application Support/Ruche/Recipes/<dossier>/
    recipe.json
    recipe.js      (facultatif)
```

Réglages › Avancé › « Ouvrir le dossier des recettes », puis « Recharger les recettes ».
Les dossiers qui commencent par `_` sont ignorés (voir `_exemple`).
Une recette perso avec le même `id` qu'une recette intégrée la remplace.

## recipe.json

```json
{
  "id": "mon-service",
  "name": "Mon service",
  "url": "https://app.exemple.com",
  "matchHosts": ["app.exemple.com"],
  "keepAwake": false,
  "iconDomain": "exemple.com",
  "iconURL": null,
  "author": "Ton nom",
  "version": "1.0"
}
```

| Champ | Rôle |
|---|---|
| `id` | identifiant unique (lettres, chiffres, tirets) |
| `name`, `url` | nom et adresse proposés dans la grille d'ajout |
| `matchHosts` | hôtes où la recette s'applique (sous-domaines inclus) — un service existant utilise la recette dont l'hôte correspond à son URL |
| `keepAwake` | coche « Toujours actif » par défaut à l'ajout |
| `iconDomain` / `iconURL` | icône de la grille (domaine pour le service d'icônes, ou URL directe) |

## recipe.js

Le script est exécuté dans la page du service une fois celle-ci chargée. API :

| Fonction | Effet |
|---|---|
| `Ruche.loop(fn, ms)` | exécute `fn` tout de suite puis toutes les `ms` (3000 par défaut) |
| `Ruche.setBadge(directs, autres)` | `directs` = compteur affiché ; `autres > 0` sans directs = simple point |
| `Ruche.safeParseInt(texte)` | `"12 non lus"` → `12` (0 si rien) |
| `Ruche.injectCSS(css)` | ajoute du CSS à la page |

Dès qu'une recette appelle `Ruche.setBadge`, la détection générique (titre de la page) s'efface.

```js
Ruche.loop(() => {
  const badge = document.querySelector(".unread-count");
  Ruche.setBadge(badge ? Ruche.safeParseInt(badge.textContent) : 0);
});
```

Partager une recette = partager son dossier.

Les recettes intégrées WhatsApp et Infomaniak Mail sont adaptées des recettes Ferdium
(https://github.com/ferdium/ferdium-recipes, licence MIT, © Ferdium Contributors).
