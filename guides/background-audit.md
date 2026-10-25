# Audit arrière-plan Fresh Windows

Ce guide recense **tout ce que le dépôt `fresh_windows` installe ou fait tourner** en arrière-plan sur un PC Windows (Nicolas / MSI B450), avec impact CPU/RAM probable, commandes PowerShell de vérification et de désactivation, et les pièges connus (polling, doublons, modèles en RAM).

**Outil machine :** `scripts/Invoke-FreshWindowsBackgroundAudit.ps1` (lecture seule par défaut). Menu launcher **9 → 4**, mode silencieux `background-audit`, ou systray **Fresh Windows → Audit arrière-plan**.

---

## Classement par impact (résumé)

| Impact | Éléments |
|--------|----------|
| **Élevé** | Agent systray (`GameMode-WatchAgent.ps1`), `voice_worker.exe` (faster-whisper), Ollama + modèle chargé, tâche `FreshWindows-WinUtilReapply`, double démarrage (tâche + Startup) |
| **Moyen** | Surveillance CPU/RAM/disque (timer ~12 s + `Get-Process`), tâche `FreshWindows-WingetUpgrade`, timers STT/PTT quand la voix est active |
| **Faible** | Sync scripts hebdo, rapport santé hebdo, workers IA ponctuels (`FreshAgent-BackgroundWorker.ps1`) |

---

## Inventaire détaillé

### Tâches planifiées (noms exacts)

Créées par `scripts/lib/Launcher-Tasks.ps1` et `launcher.ps1` — **compte utilisateur courant**, déclencheurs ci-dessous.

| Nom exact | Déclencheur | Fréquence | Compte / niveau | Fichier source | Impact | Vérifier | Désactiver (Fresh seulement) |
|-----------|-------------|-----------|-----------------|----------------|--------|----------|------------------------------|
| `FreshWindows-WingetUpgrade` | Daily 12:00 | Quotidien (+ rattrapage) | Interactive, **Highest** | `Launcher-Tasks.ps1` | Moyen (pic court winget) | `Get-ScheduledTask -TaskName 'FreshWindows-WingetUpgrade'` | `Disable-ScheduledTask -TaskName 'FreshWindows-WingetUpgrade'` |
| `FreshWindows-WinUtilReapply` | Weekly Sunday 12:00 | Hebdo | Interactive, **Highest** | `Launcher-Tasks.ps1` | Élevé (WinUtil + ShutUp10) | `Get-ScheduledTaskInfo -TaskName 'FreshWindows-WinUtilReapply'` | `Disable-ScheduledTask -TaskName 'FreshWindows-WinUtilReapply'` |
| `FreshWindows-SyncLocalScripts` | Weekly Sunday 12:30 | Hebdo | Interactive, **Highest** | `Launcher-Tasks.ps1` | Faible (réseau + I/O) | `Get-ScheduledTask -TaskName 'FreshWindows-SyncLocalScripts'` | `Disable-ScheduledTask -TaskName 'FreshWindows-SyncLocalScripts'` |
| `FreshWindows-WatchAgent` | **AtLogOn**, délai **PT45S** | Chaque session | Interactive, **Limited** | `launcher.ps1` → `Register-FreshWindowsWatchAgentLogon` | Élevé (lance le systray) | `Get-ScheduledTask -TaskName 'FreshWindows-WatchAgent'` | `Disable-ScheduledTask -TaskName 'FreshWindows-WatchAgent'` |

Réactiver : `Enable-ScheduledTask -TaskName '<nom>'`.

Activation globale (admin) : menu launcher **9 → 1** ou `$env:FRESH_WIN_MODE='tasks'`.

### Démarrage (Startup / Run)

| Nom | Type | Fréquence | Source | Impact | Vérifier | Désactiver |
|-----|------|-----------|--------|--------|----------|------------|
| `Fresh Windows Surveillance.lnk` | Dossier Startup utilisateur | Connexion (fallback) | `launcher.ps1` si la tâche Limited échoue | **Élevé si doublon avec la tâche** | `Test-Path "$([Environment]::GetFolderPath('Startup'))\Fresh Windows Surveillance.lnk"` | Supprimer ou `-Apply` audit (backup dans `%LOCALAPPDATA%\FreshWindows\background-audit-backup\`) |

Fresh Windows **ne crée pas** d’entrée `Run` registre pour l’agent ; les tweaks WinUtil touchent d’autres clés (thème, Game Bar, etc.) via `Launcher-WinUtil.ps1`.

### Services Windows

Le dépôt **n’enregistre pas** de service Windows dédié « Fresh ». La maintenance peut **désactiver** des services tiers (ex. Everything) dans certains presets WinUtil — hors périmètre de l’outil `-Apply` (jamais de modification de services non-Fresh).

### Processus résidents

| Processus | Quand | Source | CPU / RAM probable | Vérifier | Réduire |
|-----------|-------|--------|-------------------|----------|---------|
| `powershell.exe` + `GameMode-WatchAgent.ps1` | Tâche ou Startup | `scripts/GameMode-WatchAgent.ps1` | Moyen–élevé si surveillance ON | `Get-CimInstance Win32_Process \| ? { $_.CommandLine -match 'GameMode-WatchAgent' }` | Tray **Quitter**, désactiver tâche, `monitorEnabled=false` |
| `voice_worker.exe` | Écoute vocale ON | `scripts/ai/FreshAgent-VoiceWorker.ps1` | **Élevé** (Whisper) | `Get-Process voice_worker` | Écoute OFF / `voice.enabled=false` |
| `ollama.exe` / `ollama app.exe` | IA ON + autoStart | `scripts/ai/Ollama-Manager.ps1` | **Élevé** (modèle en RAM) | `Test-OllamaApi` ; `Get-Process ollama*` | IA OFF dans le tray |
| `powershell.exe` + `FreshAgent-BackgroundWorker.ps1` | Pull modèle, RAG | `scripts/ai/FreshAgent-BackgroundWorker.ps1` | Pic temporaire | CommandLine match `BackgroundWorker` | Attendre fin ; IA OFF |
| `powershell.exe` + `idle-ai-run.ps1` | Idle + Ollama déjà up | `FreshAgent-IdleSuggest.ps1` | Pic court | match `idle-ai-run` | IA OFF ; idle 12 h entre suggestions |

### Timers / polling (dans le process Watch Agent)

| Timer | Intervalle | Condition | Source | Impact |
|-------|------------|-----------|--------|--------|
| `WatchPollTimer` | `max(5 s, pollIntervalSeconds)` — défaut **12 s** | Toujours (tick global) | `GameMode-WatchAgent.ps1` + `configs/game-mode-watch.json` | Moyen si `monitorEnabled` (scan `Get-Process`) |
| `FaSttPollTimer` | **400 ms** | Écoute STT active | `GameMode-WatchAgent.ps1` | Moyen |
| `FaPttTimer` | **100 ms** | PTT + écoute | `FreshAgent-VoiceWorker.ps1` | Faible–moyen |
| `FaVoiceWatchTimer` | **800 ms** | Session voix | `FreshAgent-VoiceWorker.ps1` | Faible |
| `FaAiPollTimer` / skill / bg | **1000 ms** | Pendant travail async | `GameMode-WatchAgent.ps1` | Faible (pendant opération) |
| `FaHealthSampleAt` | ~**5 min** | Agent prêt | `FreshAgent-Health.ps1` via tick | Faible (CIM) |
| Dashboard refresh | **4000 ms** | Dashboard ouvert | `FreshAgent-Dashboard.ps1` | Faible |
| Idle suggest | **600 s** idle, cooldown **12 h** | IA ON optionnel | `FreshAgent-IdleSuggest.ps1` | Faible (sauf spawn Ollama idle) |

Config surveillance : `%LOCALAPPDATA%\FreshWindows\watch-agent-user.json` (`monitorEnabled`, `autoSuggestKill`).

### Maintenances planifiées (logique applicative)

| Nom | Fréquence | Source | Impact |
|-----|-----------|--------|--------|
| Rapport santé hebdo | 7 jours | `FreshAgent-Optimize.ps1` | Faible |
| Winget / WinUtil / Sync | Voir tâches planifiées | `Launcher-Tasks.ps1` | Variable |

---

## Problèmes repérés dans le code

1. **Doublon agent** : tâche `FreshWindows-WatchAgent` + ancien `Fresh Windows Surveillance.lnk` → deux icônes et deux processus. Le launcher retire le `.lnk` quand la tâche est créée ; vérifier les deux si pics CPU inexpliqués.
2. **Scan processus** : à chaque tick de surveillance, `Invoke-WatchTick` énumère **`Get-Process`** (coût qui monte avec le nombre de processus Windows). Désactiver **Surveillance** dans le tray ou `monitorEnabled=false` coupe ce coût.
3. **Voix + Whisper** : `voice_worker.exe` est le principal suspect CPU/RAM si l’écoute est ON (même en PTT, modèle chargé côté worker).
4. **Ollama** : `Enable-FreshAgentAi` force `autoStart` ; modèles 7B+ sur B450 → pics soutenus. `keepAliveMinutes: 0` dans `agent-ai.json` (comportement Ollama côté API à surveiller).
5. **Timers rapides** : STT 400 ms, PTT 100 ms (anciennement 50 ms — corrigé en PR pour limiter le polling clavier).
6. **Tâches admin** : dimanche 12:00 maintenance + 12:30 sync peuvent chevaucher (charge disque/CPU ponctuelle).
7. **Legacy** : `scripts/ai/_legacy/FreshAgent-WhisperLoop.ps1` (boucle Python) — **non utilisé** par le chemin voice_worker actuel.

---

## Utilisation de l’outil d’audit

```powershell
# Lecture seule + fichier rapport
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-FreshWindowsBackgroundAudit.ps1

# Désactivation ciblée (confirmation interactive)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-FreshWindowsBackgroundAudit.ps1 `
  -Apply -TargetIds scheduled-task-watch-agent,prefs-monitor-off,prefs-voice-off

# Restaurer le journal
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-FreshWindowsBackgroundAudit.ps1 -Restore
```

Journal : `%LOCALAPPDATA%\FreshWindows\background-audit-journal.jsonl`.

**Périmètre `-Apply` :** uniquement les 4 tâches Fresh, le raccourci Startup Fresh, et les prefs `watch-agent-user.json` / `agent-ai.user.json`. Aucune modification de tâches ou services Windows tiers (lecture seule possible dans le rapport console pour info future).

---

## Causes probables de pics CPU (Nicolas / B450)

1. **Écoute vocale** + `voice_worker` (Whisper `base` ou profil `accurate`).
2. **Ollama** avec `qwen2.5:7b` pendant chat / tool calling / idle AI.
3. **Surveillance auto** + enumération processus toutes les ~12 s.
4. **Maintenance WinUtil** le dimanche ou **winget upgrade** quotidien.
5. **Deux agents** si Startup + tâche planifiée coexistants.

Pistes sans désinstaller Fresh : surveillance OFF, écoute OFF, IA OFF, désactiver tâche WatchAgent si l’agent n’est pas nécessaire en permanence, conserver uniquement le raccourci « Mode Jeu » manuel.
