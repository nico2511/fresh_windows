# Audit arrière-plan Fresh Windows

Outil de **lecture seule** par défaut pour lister les tâches planifiées Fresh et les processus de maintenance lancés depuis `%LOCALAPPDATA%\FreshWindows`.

## Impact (résumé)

| Niveau | Éléments |
|--------|----------|
| **Élevé** | `FreshWindows-WinUtilReapply` (WinUtil + ShutUp10, fenêtre visible) |
| **Moyen** | `FreshWindows-WingetUpgrade` (pic winget) |
| **Faible** | `FreshWindows-SyncLocalScripts` (téléchargement scripts, nettoyage artefacts obsolètes) |

## Tâches planifiées Fresh

| Tâche | Fréquence | Source |
|-------|-----------|--------|
| `FreshWindows-WingetUpgrade` | Quotidien 12:00 | `Launcher-Tasks.ps1` |
| `FreshWindows-WinUtilReapply` | Dimanche 12:00 | `Launcher-Tasks.ps1` |
| `FreshWindows-SyncLocalScripts` | Dimanche 12:30 | `Launcher-Tasks.ps1` |

La tâche historique `FreshWindows-WatchAgent` (agent systray) n’est plus créée par Fresh ; le sync hebdomadaire tente de la supprimer si elle subsiste d’une ancienne install.

## Lancer l’audit

- Menu **9 → 4**, ou mode silencieux `background-audit`
- Script : `scripts/Invoke-FreshWindowsBackgroundAudit.ps1`

`Invoke-FreshWindowsBackgroundAudit -Apply` désactive uniquement des entrées du catalogue (tâches Fresh), avec journal réversible (`-Restore`).
