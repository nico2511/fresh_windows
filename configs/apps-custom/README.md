# Paquets custom

Dépose ici tes listes d’apps au format JSON (même schéma que `apps-standard.json`).

Chaque fichier `*.json` devient un paquet installable via le menu **Apps custom**.

## Format

Tableau d’IDs winget et/ou d’objets téléchargement :

```json
[
  "7zip.7zip",
  "Microsoft.PowerToys",
  {
    "name": "MonApp",
    "url": "https://example.com/MonApp.exe",
    "destDir": "%LOCALAPPDATA%\\Programs\\MonApp",
    "fileName": "MonApp.exe",
    "shortcut": true
  }
]
```

## Trouver un ID winget

1. [winstall.app](https://winstall.app) — cherche l’app, copie l’ID.
2. Ou en local : `winget search NomDeLApp`

## Où placer les fichiers

| Emplacement | Usage |
|-------------|--------|
| `configs/apps-custom/*.json` (ce dossier, dans le repo / fork) | Partagé via GitHub |
| `%LOCALAPPDATA%\FreshWindows\apps-custom\*.json` | Machine locale, sans toucher au repo |

Les paquets locaux ont priorité s’ils portent le même nom qu’un paquet distant.
