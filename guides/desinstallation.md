# Désinstallation de Fresh Windows

Ce guide décrit comment retirer Fresh Windows de la machine **sans** désinstaller les applications ni annuler les réglages déjà appliqués par winget, WinUtil ou ShutUp10.

## Ce qui est supprimé

- L’**agent** (systray) et tout processus dont la ligne de commande contient `FreshWindows` ou `GameMode-Watch` (hors session PowerShell du script).
- Les **tâches planifiées** dont le nom commence par `FreshWindows-*`, notamment :
  - `FreshWindows-SyncLocalScripts`
  - `FreshWindows-WatchAgent`
  - `FreshWindows-WingetUpgrade`
  - `FreshWindows-WinUtilReapply`
- Les **raccourcis Bureau** « Fresh Windows » / `FreshWindows.lnk` (profil utilisateur et Bureau public).
- Le dossier **`%LOCALAPPDATA%\FreshWindows`** (scripts mis en cache, configs locales, logs).
- Les dossiers temporaires de test **`%TEMP%\fw-test*`** s’ils existent.

## Ce qui est conservé

- Les **applications installées via winget** (ou le menu Fresh Windows) : elles ne sont pas désinstallées.
- Les **réglages WinUtil** et **ShutUp10++** déjà appliqués : le script ne les annule pas.
- Les **dossiers de modèles vocaux externes** éventuels (hors `%LOCALAPPDATA%\FreshWindows`), si vous les aviez placés ailleurs pour Piper / STT.

## Méthode recommandée (script du dépôt)

1. Ouvrir **PowerShell en administrateur**.
2. Lancer d’abord une **simulation** (`-DryRun`) : aucun fichier ni tâche n’est supprimé ; le script affiche ce qu’il ferait.
3. Si la simulation convient, relancer **sans** `-DryRun` pour la suppression réelle.

Depuis une copie locale du dépôt :

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
cd chemin\vers\fresh_windows\scripts
.\Uninstall-FreshWindows.ps1 -DryRun
# puis, si OK :
.\Uninstall-FreshWindows.ps1
```

### Sans cloner le dépôt (une ligne, simulation)

Télécharge le script depuis la branche `main` dans `%TEMP%` et lance la simulation :

```powershell
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/scripts/Uninstall-FreshWindows.ps1 -OutFile $env:TEMP\Uninstall-FreshWindows.ps1; & $env:TEMP\Uninstall-FreshWindows.ps1 -DryRun
```

Pour la suppression réelle, exécuter la même commande **sans** `-DryRun` :

```powershell
irm https://raw.githubusercontent.com/nico2511/fresh_windows/main/scripts/Uninstall-FreshWindows.ps1 -OutFile $env:TEMP\Uninstall-FreshWindows.ps1; & $env:TEMP\Uninstall-FreshWindows.ps1
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
