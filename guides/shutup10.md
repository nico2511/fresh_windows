# O&O ShutUp10++ — profil recommandé

## Important
Le fichier `%LOCALAPPDATA%\OO Software\OO ShutUp10\OOSU10.cfg` est l’**état UI** de l’app.
Ce n’est **pas** un profil importable en CLI.

Le fichier applyable est `configs/shutup10-recommended.cfg` au format :
```
SettingID<TAB>+|-
```
(+ = appliquer la restriction, - = laisser désactivé)

## CLI officiel
```text
ooshutup10.exe <ConfigFile> [/quiet] [/nosrp] [/lang:<code>] [/ignorereadonlycfg]
```
Exemple :
```text
ooshutup10.exe shutup10-recommended.cfg /quiet /nosrp /lang:fr
```

## Dans ce toolbox
1. Après install standard, le launcher tente l’import quiet du cfg GitHub.
2. Menu **7 → 6** : même logique / GUI si besoin.
3. Tâche hebdo maintenance : WinUtil + ShutUp10 quiet (pas de GUI).
