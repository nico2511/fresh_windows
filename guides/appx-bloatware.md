# Nettoyage des applications preinstallees

Outil **generique** pour tout PC Windows 10/11 : fonctionnalite **separee** du debloat WinUtil (`winutil-appx.json`). La liste est versionnee dans `configs/appx-bloatware.json`. Sur une machine sans bloat preinstalle, la simulation affiche simplement peu ou zero paquet a retirer.

## Principes

- **Protected** gagne toujours sur **Remove**.
- Paquet **inconnu** : jamais supprime (ignore).
- **Dry-run par defaut** : liste uniquement, sans modification.
- Suppression reelle : `-Apply` / mode `appx-bloatware-apply` + **confirmation** (agent ou launcher).
- **Point de restauration** avant toute suppression reelle (echec ou limite 24h Windows gere proprement).
- Journal : `%LOCALAPPDATA%\FreshWindows\logs\appx-bloatware-*.log` (paquet | action | resultat).

## Procedure recommandee

1. **Simulation** : lancer `appx-bloatware` (ou le bouton / skill agent) et lire les listes **a retirer** et **candidats a ajouter**.
2. **Verifier** : comparer avec `configs/appx-bloatware.json` ; deplacer les candidats vers `remove` / `remove.oem` ou `protected` selon le besoin.
3. **Apply** : seulement si la liste convient — `appx-bloatware-apply` ou skill avec `Apply=true` (confirmation + admin).

Rien n est supprime tant que vous n avez pas explicitement confirme l etape Apply.

## Utilisation

### Launcher (admin)

```powershell
# 1. Simulation (defaut)
$env:FRESH_WIN_MODE='appx-bloatware'; irm .../launcher.ps1 | iex

# 2. Suppression (apercu puis confirmation)
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
   - `remove.exact` / `prefixes` (Microsoft, partenaires, jeux)
   - `remove.oem` (bloc **OEM / constructeur** : preloads AppX editeur machine)
   - `confirmLater` pour reserver des paquets a revue manuelle (liste vide par defaut)
2. Pousser sur GitHub ; bumper `FreshWindowsLibEpoch` / `agent-content.json` epoch si besoin.

Prefixes : terminer par `.` (ex. `king.com.`). Suffixe systeme : `*_cw5n1h2txyewy` via `protected.suffixes`.

**Note Paint** : `Microsoft.MSPaint` = Paint 3D (remove). `Microsoft.Paint` = Paint classique (protected).

Tout paquet ni `protected` ni `remove` (y compris `remove.oem`) ni `confirmLater` = **inconnu**, jamais supprime.

## Ajouter une appli a la liste

1. **Trouver le nom AppX** (PowerShell admin sur la machine concernee) :

```powershell
Get-AppxPackage *motcle* | Select-Object Name, PackageFamilyName
```

Utiliser la colonne **`Name`** (ex. `Microsoft.BingNews`) dans la config.

2. **Choisir la categorie** dans `configs/appx-bloatware.json` :

| Objectif | Où ajouter | Format |
|----------|------------|--------|
| Retirer ce paquet | `remove.exact` ou `remove.oem.exact` | Nom exact |
| Retirer toute une famille | `remove.prefixes` ou `remove.oem.prefixes` | Prefixe finissant par `.` (ex. `king.com.`) |
| Ne jamais retirer | `protected.exact` ou `protected.prefixes` | Nom ou prefixe |
| Revoir plus tard sans auto-remove | `confirmLater.exact` | Nom exact |

3. **Verifier** :

```powershell
powershell -NoProfile -File .\tests\Validate-Configs.ps1
$env:FRESH_WIN_MODE='appx-bloatware'; irm .../launcher.ps1 | iex
```

La simulation affiche les paquets **a retirer** et, separement, les **candidats a ajouter** (inconnus installes) : utile pour enrichir la liste au fil des installations. Les candidats ne sont **jamais** supprimes, meme avec Apply.

## Restaurer des applications

- **Point de restauration Windows** (cree avant Apply).
- **Microsoft Store** : reinstaller l'app.
- **Provisionnement** : certaines apps reviennent apres mise a jour feature Windows ; relancer la simulation pour verifier.

## Mode jeu et Xbox

**`Microsoft.XboxGamingOverlay`** (barre de jeu / overlay) est en **remove**. L'app Xbox PC et les services associes sont **proteges** (`Microsoft.GamingApp`, `Microsoft.GamingServices`, `Microsoft.XboxApp` — aligne avec le mode jeu du depot). Le registre **Game Bar** pose par WinUtil (`AllowAutoGameMode`) reste independant de la suppression de l'overlay AppX.
