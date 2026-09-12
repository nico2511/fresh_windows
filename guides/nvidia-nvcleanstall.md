# Guide NVIDIA — installation propre avec NVCleanstall

Guide pas à pas pour installer les drivers NVIDIA **propres**, sans bloat GeForce Experience / télémétrie inutile, via [NVCleanstall](https://www.techpowerup.com/download/techpowerup-nvcleanstall/).

> Stack recommandée : **DDU** (nettoyage) → **NVCleanstall** (install ciblée) → réglages Windows / jeu.

---

## Prérequis

- PC Windows 10/11
- Connexion Internet
- [Display Driver Uninstaller (DDU)](https://www.wagnardsoft.com/) — déjà dans la liste *Apps Standard* du toolbox (`Wagnardsoft.DisplayDriverUninstaller`)
- [NVCleanstall](https://www.techpowerup.com/download/techpowerup-nvcleanstall/) — aussi via winget : `TechPowerUp.NVCleanstall`
- Page drivers NVIDIA : [https://www.nvidia.com/Download/index.aspx](https://www.nvidia.com/Download/index.aspx)

---

## Étape 1 — Télécharger le bon driver

1. Va sur le [site NVIDIA Drivers](https://www.nvidia.com/Download/index.aspx).
2. Sélectionne ta carte (ex. GeForce RTX 4070) + Windows 11 64-bit.
3. Télécharge le package **Game Ready** (ou Studio si tu fais surtout de la création).
4. **Ne lance pas** l’installeur NVIDIA pour l’instant — garde le fichier `.exe`.

Astuce : note le numéro de version (ex. `566.xx`).

---

## Étape 2 — Nettoyage avec DDU (recommandé)

À faire surtout si :
- tu changes de marque (AMD → NVIDIA) ou de génération,
- tu as des crashes / écrans noirs / driver corrompu,
- tu réinstalles Windows « sale » sans clean install.

1. Installe **DDU**.
2. Redémarre en **mode sans échec** :
   - *Paramètres → Système → Récupération → Démarrage avancé → Redémarrer maintenant*
   - *Dépannage → Options avancées → Paramètres de démarrage → Redémarrer → 4 (mode sans échec)*
3. Lance DDU → **GPU → NVIDIA** → **Clean and restart**.
4. Au retour sur Windows, n’installe **rien** automatiquement via Windows Update si possible (coupe temporairement les MAJ drivers ou débranche le réseau le temps d’installer via NVCleanstall).

---

## Étape 3 — NVCleanstall

1. Lance **NVCleanstall**.
2. Choisis **Use driver file on disk** et pointe vers le `.exe` NVIDIA téléchargé  
   *(ou « Download origin » si tu laisses NVCleanstall récupérer le driver)*.
3. Sur l’écran des composants, garde typiquement :

### À cocher (minimum utile)
- **Display Driver**
- **PhysX** (si tu y joues / vieux titres)
- **HD Audio Driver** (si tu sors le son via HDMI/DP vers le moniteur / TV)

### À décocher (souvent inutile / bloat)
- **GeForce Experience** / NVIDIA App (sauf si tu veux vraiment ShadowPlay / overlays NVIDIA)
- **Telemetry / App / Backend** (selon ce que propose ta version de NVCleanstall)
- Composants USB-C / Optimus / Notebook **si desktop desktop** et non listés comme nécessaires
- Tout ce que tu ne comprends pas et qui n’est pas Display / PhysX / HD Audio

> Les intitulés exacts changent selon les versions NVCleanstall — principe : **driver d’affichage + audio HDMI si besoin**, le reste hors.

4. Options d’installation utiles :
   - **Show expert options** / installation personnalisée
   - Désactive si proposé : télémétrie, services annexes non liés à l’affichage
   - Coche **Clean install** / equivalent si disponible
5. Lance l’installation et **redémarre**.

---

## Étape 4 — Réglages Windows / panneau NVIDIA (après install)

1. Vérifie le driver : clic droit Bureau → *Panneau de configuration NVIDIA* → Aide → Informations système.
2. **Affichage Windows** : Hz max sur ton moniteur.
3. Dans Gérer les paramètres 3D (global) — base saine :
   - Mode de gestion de l’alimentation : **Préférer les performances maximales** (desktop)
   - Low Latency Mode : **On** ou **Ultra** selon titres
   - Vertical Sync : **Application-controlled** (laisse le jeu / FreeSync-GSync décider)
4. Active **G-SYNC Compatible** si ton écran le supporte (Affichage → Set up G-SYNC).

---

## Étape 5 — Checklist de validation

- [ ] Device Manager : pas de point d’exclamation sur la GPU
- [ ] Jeu lance en plein écran sans stutter anormal au boot driver
- [ ] Hz max OK
- [ ] G-SYNC / VRR actif si supporté
- [ ] Pas de GeForce Experience si tu l’as volontairement exclu

---

## Problèmes courants

| Symptôme | Piste |
|----------|--------|
| Driver Windows Update qui écrase ton install | Pause des mises à jour / politique « ne pas inclure les drivers » |
| Écran noir après install | DDU en sans échec → réinstall NVCleanstall plus minimal |
| Pas de son HDMI | Recoche **HD Audio Driver** |
| Overlays / Record manquants | Normal sans NVIDIA App — utilise ShareX / OBS |

---

## Résumé one-page

1. Télécharge le driver NVIDIA (ne pas installer)  
2. DDU en sans échec si clean nécessaire  
3. NVCleanstall → Display (+ PhysX / HD Audio) → sans bloat Experience  
4. Redémarrage → Hz max + G-SYNC + perf max  
5. Joue
