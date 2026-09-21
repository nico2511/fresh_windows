# Guide chipset — Intel / AMD

Après un formatage, les pilotes **chipset** (SMBus, USB, stockage, plans d’alimentation Ryzen, etc.) complètent les pilotes GPU. Fresh Windows propose un parcours guidé via le menu **10 → 3 Chipset**.

> Ce n’est **pas** une install silencieuse totale : l’outil officiel ou l’installeur constructeur reste interactif.

---

## Détection

Le launcher lit :

- CPU (`Win32_Processor`) → vendor Intel / AMD + motifs Ryzen (AM4 / AM5)
- Carte mère (`Win32_BaseBoard`) → affichage seulement
- Châssis portable → avertissement (packs constructeur souvent préférables)

---

## Intel (desktop ou portable)

1. Menu **10 → 3 → 1**
2. Installation de **Intel Driver & Support Assistant** via winget (`Intel.IntelDriverAndSupportAssistant`)
3. Lancement de DSA → **Scan for drivers**
4. Accepte les mises à jour chipset / ME / réseau Intel proposées

Fallback : [page Intel Detect](https://www.intel.com/content/www/us/en/support/detect.html)

---

## AMD (PC fixe)

1. Menu **10 → 3 → 1**
2. Selon le CPU (AM5 / AM4), téléchargement de **AMD Chipset Software**
3. Lance l’installeur, laisse les composants cochés par défaut
4. **Redémarre** si demandé

Fallback : [AMD Drivers & Support](https://www.amd.com/en/support/download/drivers.html) → Chipsets → ton socket.

Les URL directes dans `configs/gpu.json` périment comme Adrenalin : mets-les à jour quand AMD sort une nouvelle build.

### Portable AMD

Pas d’URL chipset desktop forcée : ouverture de la page support AMD. Préfère le pack **ASUS / Lenovo / HP / Dell** de ta machine.

---

## Ordre conseillé après formatage

1. Chipset (ce guide)
2. GPU (Adrenalin / NVCleanstall — guides dédiés)
3. Apps / tweaks Fresh Windows

---

## Limites

- Pas de package winget « Chipset » AMD
- Pas d’install auto via Windows Update (évite les génériques qui écrasent un flux NVIDIA propre)
- Threadripper / plateformes pro : vérifier la page AMD du chipset exact (TRX50, WRX90…)
