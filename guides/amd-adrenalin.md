# Guide AMD Adrenalin — réglages recommandés (2026)

Guide simple pour une config **propre, stable et orientée jeux** sur les drivers AMD Software: Adrenalin Edition.

> Objectif : FreeSync + FSR correctement réglés, sans activer les options qui cassent la fluidité.

---

## 1. Installation des drivers

1. Désinstalle d’abord l’ancien driver avec **DDU** (mode sans échec) si tu viens de NVIDIA / d’une install sale.
2. Installe Adrenalin (setup minimal ou install complète).
3. Redémarre.
4. Ouvre **AMD Software: Adrenalin Edition**.

Liens utiles :
- [Page drivers AMD](https://www.amd.com/en/support/download/drivers.html)
- Setup minimal (exemple) : Adrenalin Edition minimal web installer

---

## 2. Affichage (écran) — à faire en premier

Dans **Affichage / Display** :

| Option | Réglage | Pourquoi |
|--------|---------|----------|
| **FreeSync / VRR** | **Activé** | Fluidité variable, moins de tearing |
| **GPU Scaling** | **Désactivé** | Laisse Windows / le jeu gérer le scaling |
| **Pixel Format** | **RGB 4:4:4 Full** | Couleurs correctes (surtout écran desktop) |
| **Taux de rafraîchissement** | **Max** (dans Windows aussi) | Ex. 144 / 165 / 240 Hz |

Dans Windows : *Paramètres → Système → Affichage → Affichage avancé* → choisir le Hz max.

---

## 3. Graphiques (Gaming → Graphics) — profil Custom

Crée un **profil Custom** (ne reste pas sur HYPR-RX).

| Option | Réglage | Note |
|--------|---------|------|
| **FSR Upscaling Upgrade** | **Activé** | Point le plus important en 2026 (FSR 4 sur GPU compatibles) |
| **Frame Generation Upgrade** | **Activé** (RX 9000) | Utile sur séries récentes ; ignore si non dispo |
| **Anti-Lag 2** | **Activé** | Latence input |
| **Image Sharpening** | **~50–55 %** | Assez pour le piqué, sans halo |
| **Radeon Boost** | **Désactivé** | Peut dégrader la netteté / stabilité |
| **Radeon Chill** | **Désactivé** | Ou remplace par un limiteur FPS si besoin thermique |
| **RSR** | **Désactivé** | Préfère FSR in-game / FSR Upgrade |
| **Fluid Motion Frames** | **Désactivé** | Souvent pire que FG / FSR natif selon jeux |
| **Enhanced Sync** | **Désactivé** | Instable ; FreeSync suffit |
| **HYPR-RX** | **Ne pas utiliser** | Ou tester puis repasser en **Custom** |

---

## 4. Vérification rapide en jeu

1. Lance un jeu compatible FSR.
2. Ouvre l’overlay Adrenalin : **Alt + R**.
3. Vérifie que **FSR** est bien actif (indicateur / coche verte selon version).
4. Si ce n’est pas le cas : active FSR **dans le jeu** (Quality / Balanced) + laisse Upgrade Adrenalin actif.

---

## 5. Bonnes pratiques

1. Garde un profil **Custom** nommé clairement (`Fresh-Gamer`, etc.).
2. Une fois satisfait : **exporter / Snap Settings** Adrenalin pour restaurer après réinstall.
3. Après une grosse MAJ Adrenalin : revérifie FreeSync + FSR + Sharpening (AMD reset parfois des options).
4. Pour le competitive / esports : priorise Hz max + FreeSync + Anti-Lag ; désactive Frame Gen si tu veux la latence minimale.

---

## 6. Ce qu’il ne faut surtout pas empiler

Évite d’activer en même temps :
- HYPR-RX + tout le Custom
- RSR + FSR in-game
- Enhanced Sync + FreeSync
- Chill + Boost + Frame Gen

Un réglage **simple et stable** bat une usine à gaz.

---

## Résumé one-page

**Écran** : FreeSync ON · GPU Scaling OFF · RGB Full · Hz max  
**Graphics** : FSR Upgrade ON · FG ON (si RX 9000) · Anti-Lag 2 ON · Sharpening ~50–55% · Boost/Chill/RSR/FMF/Enhanced Sync OFF · pas de HYPR-RX  
**Check** : Alt+R en jeu · profil Custom · export Snap Settings
