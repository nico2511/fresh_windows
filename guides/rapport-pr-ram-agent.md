# Rapport PR — réduction RAM agent systray (epoch 53)

## Contexte

L’agent systray (`powershell.exe -STA` via `Launch-GameModeWatch.ps1` → `GameMode-WatchAgent.ps1`) affichait environ **207 Mo** de working set avec voix coupée et surveillance active. Whisper tourne dans `voice_worker.exe` (hors processus agent) ; le gros du coût venait du socle PowerShell 5.1 + WinForms et du **dot-source de nombreuses libs** au boot, ainsi que des timers toujours actifs.

## Causes identifiées

1. Boot asynchrone chargeant IA, RAG, Ollama, STT, TTS, VoiceWorker, audit, etc. dès le démarrage.
2. `WatchPollTimer` démarré même si `monitorEnabled=false` (tick inutile).
3. Timers voix (STT 400 ms, PTT 100 ms, watch 800 ms) non arrêtés proprement à l’OFF.
4. Pas de `GC` / trim du working set après l’initialisation.
5. Audit « processus Fresh » pouvant compter `WindowsTerminal.exe` / `conhost` (hôte console, pas l’agent).

## Correctifs

| # | Changement |
|---|------------|
| 1 | Mesures audit : WS, mémoire privée, threads, modules .NET notables ; option `-SampleMinutes` |
| 2 | `Import-FreshAgentLibOnce` + boot minimal ; IA/RAG/voix/tâches au premier usage |
| 3 | Timers surveillance / STT / PTT conditionnels + `Dispose` à l’arrêt |
| 4 | `Invoke-FreshAgentPostInitMemoryCleanup` (GC + `EmptyWorkingSet`), désactivable via `memoryTrimAfterInit` dans `watch-agent-user.json` |
| 5 | Exclusion `conhost.exe` (déjà WT) du décompte Fresh |
| 6 | Epoch **53**, tests `FreshAgent-RamLazyLoad.Tests.ps1` |

## Fichiers modifiés (principaux)

- `scripts/GameMode-WatchAgent.ps1`
- `scripts/lib/FreshAgent-Config.ps1`
- `scripts/lib/FreshAgent-Optimize.ps1`
- `scripts/lib/FreshWindows-BackgroundAudit.ps1`
- `scripts/Invoke-FreshWindowsBackgroundAudit.ps1`
- `scripts/ai/FreshAgent-VoiceWorker.ps1`
- `configs/agent-content.json`
- `tests/FreshAgent-RamLazyLoad.Tests.ps1`, `tests/FreshWindows-BackgroundAudit.Tests.ps1`, `tests/Run-AllTests.ps1`

## Procédure de mesure (Nicolas)

### Avant / après (même session, voix OFF, `monitorEnabled=true`)

1. Arrêter l’agent (menu Quitter) ou `Stop-FreshWatchAgent.ps1`.
2. Synchroniser scripts locaux (menu ou `Sync-FreshWindowsAgent.ps1`) pour epoch 53.
3. Relancer l’agent (tâche logon ou `Launch-GameModeWatch.ps1`).
4. Attendre **~30 s** après l’icône systray (boot modules + trim).
5. Exécuter :
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\FreshWindows\Invoke-FreshWindowsBackgroundAudit.ps1"
   ```
6. Lire la section **« Mémoire agent »** : total WS agent + enfants. Cible **≤ ~120 Mo** voix OFF.
7. Option croissance : `-SampleMinutes 5` sur le même script.

### Task Manager (contrôle rapide)

- Détails → `powershell.exe` dont la ligne de commande contient `GameMode-WatchAgent`.
- Colonne **Mémoire (ensemble de travail)** après 30 s à froid.

## Checklist retest

- [ ] Icône systray + menu complet (surveillance, IA, skills, Fresh Windows).
- [ ] Surveillance ON : alertes / tick sans erreur log ; OFF : pas de `WatchPollTimer` (log « poll arrêtée »).
- [ ] Écoute ON/OFF : `voice_worker` démarre à la demande, timers STT/PTT arrêtés à l’OFF.
- [ ] Dashboard s’ouvre (chargement lazy).
- [ ] Skill « État système » et session jeu OK.
- [ ] IA / Ollama / RAG au premier usage (pas au boot).
- [ ] Audit : pas de `WindowsTerminal` / `conhost` dans processus Fresh ; section mémoire présente.
