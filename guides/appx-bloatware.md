# Nettoyage des applications preinstallees

Fonctionnalite **separee** du debloat WinUtil (`winutil-appx.json`). La liste est versionnee dans `configs/appx-bloatware.json`.

## Principes

- **Protected** gagne toujours sur **Remove**.
- Paquet **inconnu** : jamais supprime (ignore).
- **Dry-run par defaut** : liste uniquement.
- Suppression reelle : `-Apply` / mode `appx-bloatware-apply` + **confirmation** (agent ou launcher).
- **Point de restauration** avant toute suppression reelle (echec ou limite 24h Windows gere proprement).
- Journal : `%LOCALAPPDATA%\FreshWindows\logs\appx-bloatware-*.log` (paquet | action | resultat).

## Utilisation

### Launcher (admin)

```powershell
# Simulation
$env:FRESH_WIN_MODE='appx-bloatware'; irm .../launcher.ps1 | iex

# Suppression (apercu puis confirmation)
$env:FRESH_WIN_MODE='appx-bloatware-apply'; irm .../launcher.ps1 | iex
```

Menu **Tweaks Windows** → option **5. Apps preinstallees**.

Apres un **Full setup** interactif, une etape optionnelle propose un apercu (refuse par defaut).

### Fresh Agent

- Panneau **Sante** → **Apps preinstallees** (simulation).
- Voix : « liste les apps preinstallees », « supprime le bloatware » (confirmation + admin).

## Desactiver les installations silencieuses

Lors d'une suppression reelle, les cles **ContentDeliveryManager** sont mises a 0 (voir `contentDeliveryManager` dans la config). Sauvegarde : `%LOCALAPPDATA%\FreshWindows\appx-bloatware-cdm-backup.json`.

Restaurer les valeurs :

```powershell
Invoke-FreshWindowsAppxBloatwareCleanup -RevertSilentInstall
```

(Depuis le module charge par le launcher ou l'agent.)

## Adapter la liste

1. Editer `configs/appx-bloatware.json` :
   - `protected.exact` / `prefixes` / `suffixes`
   - `remove.exact` / `prefixes`
   - `confirmLater` pour les paquets a valider manuellement
2. Pousser sur GitHub ; bumper `FreshWindowsLibEpoch` / `agent-content.json` epoch si besoin.

Prefixes : terminer par `.` (ex. `king.com.`). Suffixe systeme : `*_cw5n1h2txyewy` via `protected.suffixes`.

**Note Paint** : `Microsoft.MSPaint` = Paint 3D (remove). `Microsoft.Paint` = Paint classique (protected).

**Acer Configuration Manager** : dans `confirmLater`, pas dans `remove`.

## Restaurer des applications

- **Point de restauration Windows** (cree avant Apply).
- **Microsoft Store** : reinstaller l'app.
- **Provisionnement** : certaines apps reviennent apres mise a jour feature Windows ; relancer la simulation pour verifier.

## Mode jeu et Xbox Game Bar

La liste retire `Microsoft.XboxGamingOverlay` (barre de jeu). Le mode jeu du depot active surtout le **plan d'alimentation** et tue des processus ; il protege `XboxPcApp` / `GamingServices` mais pas l'overlay. Retirer la barre de jeu peut limiter raccourcis overlay / enregistrement clip ; le registre **Game Bar** pose par WinUtil (`AllowAutoGameMode`) reste independant. En cas de besoin gaming overlay, retirer l'entree de `remove.exact` dans votre fork.
