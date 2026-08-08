---
name: se-server
description: Atteindre le serveur Space Engineers en service sur pikmine et lire ce qu'il contient vraiment : journaux, monde vivant, configuration, mods téléchargés, réglages de Modular Encounters Systems. À utiliser dès qu'une question porte sur l'état réel du serveur plutôt que sur le dépôt : diagnostiquer un démarrage ou un plantage, vérifier ce qu'un mod déclare, relire les paramètres du monde en service, mesurer avant de conclure.
---

# Regarder dans le serveur plutôt que le déduire

Le dépôt décrit comment un serveur *neuf* démarre. Passé le premier démarrage, **c'est le volume qui
fait foi** : la configuration vivante, le monde, les mods téléchargés et les journaux n'existent que
là. Un raisonnement tenu sur les seuls fichiers du dépôt est une hypothèse.

## Le geste

```sh
.claude/skills/se-server/se.sh <commande...>            # dans le conteneur
.claude/skills/se-server/se.sh --host <commande...>     # sur pikmine, $SE = le conteneur
```

Le script existe pour deux raisons, et les deux ont déjà coûté du temps :

- **Le nom du conteneur porte un hash Dokploy** (`compose-<mots>-<hash>-space-engineers-1`) qui
  change à chaque redéploiement. Il est donc résolu par le label `com.docker.compose.service`,
  jamais écrit en dur.
- **La commande voyage par l'entrée standard**, pas par la ligne d'arguments : `ssh`, `docker exec`
  et un shell imbriqués les uns dans les autres se disputent les guillemets, et le symptôme est un
  `Unterminated quoted string` qui n'apprend rien.

`SE_HOST` change l'hôte si besoin. Le mode `--host` sert à ce qui parle au conteneur plutôt qu'à ce
qui vit dedans : `docker logs "$SE"`, `docker stats "$SE"`, `docker exec "$SE" ps -ef`.

## La carte

Tout ce qui compte est sous `/data`, le volume `se-data`. Le reste de l'image est jetable.

| Chemin | Ce qu'on y trouve |
|---|---|
| `/data/server` | racine du jeu **et** de Torch, qui tourne depuis là |
| `/data/server/Content/Data` | les définitions vanilla : `CubeBlocks/`, `VoxelMaterials_*.sbc`, `PlanetGeneratorDefinitions.sbc` |
| `/data/server/Logs` | `Keen-<date>.log`, `Torch-<date>.log`, `workshop_log.txt`, `connection_log_27016.txt` |
| `/data/server/Torch.cfg` | la configuration de Torch en service |
| `/data/server/premade-world` | la graine, **réécrite depuis l'image à chaque démarrage** |
| `/data/server/instance/SpaceEngineers-Dedicated.cfg` | la configuration dédiée vivante |
| `/data/server/instance/Saves/*/` | le monde vivant : `Sandbox.sbc`, `Sandbox_config.sbc`, `SANDBOX_0_0_0_.sbs`, les `.vx2`, `Backup/` |
| `/data/server/instance/Saves/*/Storage/` | l'état des mods à code, dont **la configuration de MES** |
| `/data/server/instance/content/244850/<id>` | **les mods téléchargés**, décompressés |

Le nom du monde (`Pikmine`) n'est pas garanti : passer par `Saves/*/` plutôt que l'écrire.

## Ce que seul le serveur peut dire

**Les mods téléchargés, en clair.** `instance/content/244850/<id>` est la seule façon de lire les
`.sbc` d'un mod sans être abonné sur un poste de jeu, et c'est ce qui répond aux questions qu'une
page Steam ne tranche jamais : les conditions de spawn réelles d'un mod de rencontres, le nombre de
matériaux voxel qu'il consomme, les `SubtypeId` qu'il définit. Limite à connaître : **seuls les mods
du modpack en service y sont**. Examiner un candidat suppose donc de le provisionner d'abord.

```sh
se.sh 'grep -rho "\[.*TerrainTypes:[^]]*\]" /data/server/instance/content/244850/<id> | sort -u'
```

**Trois journaux distincts, pour trois questions distinctes.** Se tromper de source fait conclure
sur du vide :

| Source | Ce qu'elle porte |
|---|---|
| `docker logs "$SE"` (mode `--host`) | l'entrypoint : mise à jour du jeu, DLL Steam, injection des admins et du modpack, séquence d'arrêt |
| `Logs/Keen-<date>.log` | le jeu lui-même : création du monde, chargement des mods, « Game ready », plantages |
| `Logs/Torch-<date>.log` | Torch : plugins, watchdog, sauvegardes planifiées |
| `Logs/workshop_log.txt` | le détail des téléchargements Workshop, mod par mod |

**La configuration de MES.** Elle vit dans le `Storage` du monde, pas dans le dépôt, et c'est là que
se règlent les fréquences de rencontres :
`instance/Saves/*/Storage/1521905890.sbm_ModularEncountersSystems/Config-*.xml`, dont
`Config-PlanetaryInstallations.xml` et `Config-General.xml`. C'est l'endroit à regarder quand un mod
de rencontres ne produit rien, ou au contraire sature le monde de grids.

**L'arbre des processus.** Un conteneur `Up` ne prouve rien, ce dépôt s'est fait avoir trois fois :

```sh
se.sh ps -ef
```

S'il ne reste que `Xvfb` et l'entrypoint, le jeu est mort et les journaux ne le diront pas.

## Ce qui se fait, et ce qui se demande

**Lire, toujours.** C'est sans risque et c'est le but de cette skill.

**Écrire, presque jamais.** La configuration du volume fait foi et n'est pas versionnée : ce qu'on y
change échappe au dépôt et disparaîtra au prochain reset du monde. Écrire directement ne se justifie
que pour un test, en le disant, et en sachant que c'est éphémère.

Deux réserves valent d'être connues avant de toucher quoi que ce soit ici. Les valeurs déclarées
dans `server/config/overrides.txt` sont **réappliquées à chaque démarrage**, donc les modifier dans
le volume, ou par commande de chat `/MES.Settings…`, ne tient que jusqu'au prochain redémarrage. Et
les fichiers de configuration de MES sont **réécrits par MES lui-même** pendant qu'il tourne : les
éditer sur un serveur en service, c'est écrire dans un fichier qui sera écrasé.

**Redémarrer ou arrêter, jamais sans demander.** L'arrêt déclenche la sauvegarde par `SIGINT`, qui
**n'aboutit pas à tous les coups** : c'est une limite connue et non résolue. Un redémarrage peut donc
coûter tout ce qui s'est passé depuis le dernier autosave.
