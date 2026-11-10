# Désinstallation de Fresh Windows

Ce guide décrit comment retirer Fresh Windows de la machine **sans** désinstaller les applications ni annuler les réglages déjà appliqués par winget, WinUtil ou ShutUp10.

## Ce qui est supprimé

- Les processus Fresh ciblés par chemin `%LOCALAPPDATA%\FreshWindows\` (y compris reliquats d’anciennes versions : Watch Agent, VoiceHost, `voice_worker` sous `bin\` uniquement) — **pas** les apps tierces type CyberScribe installées ailleurs.
- Les **tâches planifiées** dont le nom commence par `FreshWindows-*`, notamment :
  - `FreshWindows-SyncLocalScripts`
  - `FreshWindows-WatchAgent`
  - `FreshWindows-WingetUpgrade`
  - `FreshWindows-WinUtilReapply`
- Les **raccourcis Bureau** attribués à Fresh (cible vérifiable) : « Fresh Windows » / `FreshWindows.lnk`, `Mode Jeu.lnk` si pointeur Fresh ; homonymes tiers conservés.
- Le dossier **`%LOCALAPPDATA%\FreshWindows`** (scripts mis en cache, configs locales, logs).
- Les dossiers **`%TEMP%\fw-test*`** portant le fichier marqueur **`.fresh-windows-uninstall-owned`** (les autres `fw-test*` sont signalés mais non supprimés).

## Ce qui est conservé

- Les **applications installées via winget** (ou le menu Fresh Windows) : elles ne sont pas désinstallées.
- Les **réglages WinUtil** et **ShutUp10++** déjà appliqués : le script ne les annule pas.

## Via le menu Fresh Windows (recommandé)

1. Lancer le **launcher** en PowerShell **administrateur** (one-liner README ou raccourci Bureau).
2. Choisir **12 — Désinstallation**.
3. Options :
   - **3 — Simulation (DryRun)** : aucune suppression agent/tâches/cache ; depuis un clone local, exécution **en mémoire** ; sinon staging temporaire sous `%TEMP%\FreshWindows-UninstallRun-{session}\` (annoncé). Le staging est supprimé à la fin du DryRun **et** le menu renvoie le code **1** si la suppression échoue (même si la simulation elle-même a réussi). Échec de préparation du staging : dossier partiel nettoyé si possible, code **1**.
   - **2 — Désinstallation complète** : confirmation **OUI** requise ; supprime l’installation locale Fresh puis quitte le launcher.
   - **1 — Désinstaller puis réinstaller** : taper exactement **OUI** ; nettoyage vérifié puis **suppression du staging UninstallRun** avant d’ouvrir la fenêtre de relance. Stub sous `%TEMP%\FreshWindows-Reinstall-*\` (nettoyé en `finally` ou si le délai de 8 minutes expire avec cache encore présent, code **3**). Code **5** = fenêtre de relance démarrée uniquement, pas succès `irm` garanti ; code **1** si le staging Run ne peut pas être supprimé avant relance.
4. Seule la saisie exacte **OUI** confirme ; toute autre réponse **annule** sans effet.

## Méthode CLI (script du dépôt)

1. Ouvrir **PowerShell en administrateur**.
2. Lancer d’abord une **simulation** (`-DryRun`) : aucun fichier ni tâche n’est supprimé ; le script affiche ce qu’il ferait.
3. Pour une suppression réelle : ajouter **`-Confirmed`** (obligatoire hors DryRun).
4. Pour **réinstaller ensuite** : `-Confirmed -ReinstallAfter` (relance `main` uniquement après vérification du nettoyage).

Depuis une copie locale du dépôt :

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd chemin\vers\fresh_windows\scripts
.\Uninstall-FreshWindows.ps1 -DryRun
# puis, si OK :
.\Uninstall-FreshWindows.ps1 -Confirmed
```

### Sans cloner le dépôt (simulation DryRun)

Télécharger le **wrapper** et la **bibliothèque** dans la même arborescence :

```powershell
$dir = Join-Path $env:TEMP ('FreshWindows-UninstallCli-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path (Join-Path $dir 'lib') -Force | Out-Null
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/scripts/Uninstall-FreshWindows.ps1 -OutFile (Join-Path $dir 'Uninstall-FreshWindows.ps1')
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/scripts/lib/FreshWindows-Uninstall.ps1 -OutFile (Join-Path $dir 'lib/FreshWindows-Uninstall.ps1')
& (Join-Path $dir 'Uninstall-FreshWindows.ps1') -DryRun
```

Suppression réelle (PowerShell **admin**) :

```powershell
& (Join-Path $dir 'Uninstall-FreshWindows.ps1') -Confirmed
```

Réinstallation après nettoyage : `-Confirmed -ReinstallAfter`. Le staging `FreshWindows-UninstallRun-{session}` doit être supprimé **avant** `Start-Process` du stub ; sinon code **1** sans relance. Code **5** = fenêtre démarrée ; succès `irm` / `main` non garanti. Vérification finale : échec d’énumération processus (autre qu’absence normale d’un nom) bloque le succès et la relance.

### Vérification non destructive (Windows PS 5.1)

Utiliser le **SHA de la branche `feat/uninstall-procedure` (PR #61)** — pas `main` tant que la PR n’est pas fusionnée.

Fichiers minimum (sans clone complet) :

| Fichier | Rôle |
|---------|------|
| `scripts/lib/FreshWindows-Uninstall.ps1` | Logique testable hors admin en `-DryRun` |
| `tests/Invoke-UninstallSafeHarness.ps1` | Sandbox GUID sous `%TEMP%` + DryRun (aucun admin) |
| `tests/Uninstall-NativeCsvProbe.ps1` | (Optionnel) Sonde `powershell.exe -File` + `-ImmuneProcessIdsCsv` |

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd chemin\vers\dossier_téléchargé
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-UninstallSafeHarness.ps1
# Frontière native (remplacer 12345 par $PID) :
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Uninstall-NativeCsvProbe.ps1 -ImmuneProcessIdsCsv "12345"
```

## Méthode manuelle (sans script)

1. **Arrêter l’agent** : quitter l’icône systray Fresh Agent si présente, ou tuer les processus PowerShell / associés dont la commande contient `FreshWindows` ou `GameMode-Watch` (Gestionnaire des tâches ou `Stop-Process`).
2. **Supprimer les tâches planifiées** : Planificateur de tâches → tâches `FreshWindows-*` → Supprimer (ou `Unregister-ScheduledTask` en admin).
3. **Supprimer les raccourcis** sur le Bureau utilisateur et le Bureau public (`Fresh Windows.lnk`, `FreshWindows.lnk`).
4. **Supprimer le dossier** `%LOCALAPPDATA%\FreshWindows`.
5. **Nettoyer** les dossiers `%TEMP%\fw-test*` le cas échéant.
6. **Vérifier** qu’il ne reste plus de tâche `FreshWindows-*`, plus de dossier `%LOCALAPPDATA%\FreshWindows`, et plus de processus Fresh Windows actif.

## Après la désinstallation

Le launcher `irm …/launcher.ps1 | iex` peut être relancé à tout moment pour réinstaller la toolbox sur la machine. Les apps et tweaks déjà en place restent tels quels.
