# O&O ShutUp10++ — profil recommandé

## Ce que fait WinUtil
WinUtil **lance** ShutUp10 (outil Config), mais **n’applique pas** tout seul le profil recommandé.

## Édition Free vs Premium
| | Free | Premium |
|---|---|---|
| Appliquer « paramètres recommandés » | Oui, via le menu **Actions** | Oui |
| Ré-appliquer après Windows Update | Non (WU peut tout remettre) | Oui (**Automatic Protection**) |
| Profils export/import avancés (`.pcfg`) | Limité | Oui |

## Dans ce toolbox
1. `OO-Software.ShutUp10` est dans **apps-standard.json**.
2. Après install, le launcher **ouvre ShutUp10** et te rappelle le clic :
   - **Actions → Appliquer tous les paramètres recommandés**
3. Menu **7 → 6** : relancer ShutUp10 pour ça.
4. Si tu déposes un `configs/shutup10-recommended.cfg` (export après apply), le script tentera un import `/quiet`.

## Exporter un profil pour l’automation
1. Applique le profil recommandé une fois.
2. Exporte / copie `%LOCALAPPDATA%\OO Software\OO ShutUp10\OOSU10.cfg`
3. Commit dans le repo sous `configs/shutup10-recommended.cfg`
4. Les prochaines installs tenteront l’apply silencieux.
