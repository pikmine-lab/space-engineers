# Le monde

Le serveur ne joue pas un scénario livré avec le jeu : il joue un **système solaire composé à la
main**, construit sur un poste de jeu puis déposé dans le volume `se-data`. Ce document décrit ce
système, les mécaniques qui le gouvernent, et les décisions prises pour y arriver.

Il existe parce que le monde est la seule partie du serveur que le dépôt ne peut pas décrire
entièrement : les positions des corps vivent dans un fichier de sauvegarde binaire, pas dans du code.
`modpack.txt` dit *quels corps sont disponibles*, ce fichier dit *pourquoi et où*.

**État : déployé et vérifié en service le 8 août 2026**, image `sha-86a8234`. Le monde `Pikmine`
tourne sur pikmine avec ses douze corps et ses quatorze mods, en `Creative` le temps des tests.

## Le monde se construit en local, puis voyage en graine

Une planète ne se place qu'avec les outils créatifs, depuis le menu de spawn (`Shift+F10`), en caméra
spectateur. C'est un geste de jeu, pas une configuration, donc le monde ne peut pas être régénéré
depuis du code. Il vit dans `server/world-seed/` et l'image le porte comme **premade checkpoint** :
le jeu le recopie en monde vivant au premier démarrage. La mécanique est décrite dans le `CLAUDE.md`.

Il est né du preset **Empty World**, sur un poste de jeu, sous le nom `Monde vide 2026-08-07 14-56`.

### Ce que le premier déploiement a vérifié

| Vérification | Résultat |
|---|---|
| Monde créé depuis la graine | oui, nommé `Pikmine` |
| Planètes | **12** |
| Mods dans le monde en service | **14**, dans l'ordre de `modpack.txt` |
| Téléchargements Workshop | **14 réussis, 0 échec** |
| `OnlineMode` / `MaxPlayers` | `PUBLIC` / `8` |
| `EnvironmentHostility` | `NORMAL` |
| `SolarRadiationIntensity` | `1` |
| `WeatherLightingDamage` | `true` |
| `ProceduralDensity` | `0.35` |

**Trente-six valeurs avaient dû être alignées avant de pousser la graine.** Un monde bâti en solo
porte les défauts du menu de création et les impose au serveur, la configuration dédiée ne servant
qu'à la création : sans cette passe, le serveur serait parti en `OFFLINE`, deux joueurs, et des
multiplicateurs de triple. C'est le piège à ne pas réapprendre, et il est documenté dans le
`CLAUDE.md`.

**Une rencontre Factorum dort dans la graine**, à 3 880 km de Kerbin : un « Bio Research Facility »
de 4 294 blocs, deux drones miniers, treize BioStalk et un module Prototech, soit 21 grids. Elle a
spawné seule pendant la construction, ce qui apprend au passage que **`EnableEncounters=false` ne
bloque pas les rencontres Factorum** : elles passent par un système de spawn distinct, piloté par
`GlobalEncounterTimer`, `GlobalEncounterCap` et `EncounterDensity`. MES ne les gère pas non plus.
Elle réapparaîtra donc à chaque reset, tant qu'on ne l'aura pas retirée de la graine.

## Le système

Kerbin est à l'origine parce que c'est la planète de départ : toutes les coordonnées se lisent comme
des distances depuis chez soi. Les sauts comptent des bonds de jump drive vanilla, 2000 km.

| Corps | Diamètre | Position | Distance de Kerbin | Sauts |
|---|---|---|---|---|
| **Kerbin** | 120 km | `0, 0, 0` | — | départ |
| ↳ Moon *(vanilla)* | 28 km | `60 000, 150 000, -253 000` | 300 km | vol direct |
| Titan *(vanilla)* | 36 km | `-1 351 000, 553 000, -556 000` | 1 562 km | 1 |
| **Satreus** | 60 km | `-1 526 000, 628 000, -718 000` | 1 800 km | 1 |
| Umbris | 45 km | `2 379 000, 132 000, 1 214 000` | 2 674 km | 2 |
| **Géante gazeuse** | 360 km | `2 830 000, 403 000, 484 000` | 2 899 km | 2 |
| Torvion | 50 km | `2 950 000, -499 000, -298 000` | 3 007 km | 2 |
| Tohil | 19 km | `3 251 000, 754 000, 49 000` | 3 338 km | 2 |
| Moon *(vanilla)* | 23 km | `621 000, -4 213 000, -768 000` | 4 327 km | 3 |
| **Nivis** | 120 km | `786 000, -4 318 000, -996 000` | 4 501 km | 3 |
| **Argus** | 120 km | `-1 060 000, -1 556 000, 5 909 000` | 6 202 km | 4 |
| **Ignis** | 120 km | `3 077 000, 7 648 000, -3 077 000` | **8 799 km** | **5** |

Douze corps, dont trois vanilla qui ne coûtent **ni voxel ni téléchargement** : deux Moon de tailles
différentes et un Titan. `MaxPlanets` compte les *types* de planètes, pas les instances, d'où la
possibilité de poser deux Moon sans payer deux fois.

### La lecture du système

Kerbin est le carrefour : un saut vers Satreus, deux vers le système gazeux, trois vers Nivis, quatre
vers Argus, cinq vers Ignis. La difficulté croît avec la distance, et les deux mondes extrêmes sont
dans des quarts de ciel opposés, à 127,7° l'un de l'autre vus depuis Kerbin et 13 512 km l'un de
l'autre, soit sept sauts en direct.

**Les couples planète-lune**, tous atteignables sans jump drive :

| Planète | Lune | Écart | Marge surface à surface | Lune vue du sol | Vol direct |
|---|---|---|---|---|---|
| Kerbin | Moon 28 km | 300 km | 226 km | 5,4° | 50 min |
| Satreus | Titan 36 km | 250 km | 202 km | **8,2°** | 42 min |
| Nivis | Moon 23 km | 300 km | 229 km | 4,4° | 50 min |

Pour référence, la Lune vue de la Terre fait 0,52°.

**Les satellites de la géante** sont répartis en profondeur, dans trois directions distinctes :

| Satellite | Distance du centre | Rayon projeté dans le plan de l'anneau | Hauteur au-dessus du plan |
|---|---|---|---|
| Tohil | 700 km | 612 km, **dans la zone annulaire** | +339 km |
| Umbris | 900 km | 864 km, hors zone | -252 km |
| Torvion | 1 200 km | 768 km, hors zone | -922 km |

Tohil ne traverse pas l'anneau, il le **survole** à 339 km au-dessus de son plan, et y gagne le plus
beau point de vue du système : l'anneau y occupe **91° de ciel**. L'épaisseur réelle de l'anneau
(`RingLayerSpacingScale`) n'est pas documentée en mètres, donc ce dégagement n'est pas garanti par le
calcul. Si des astéroïdes apparaissent autour de Tohil, c'est qu'il est dans la zone et il faut
l'écarter vers 1 000 km.

## La géante gazeuse a deux tailles

Son **noyau voxel** ne fait que 9,5 km de rayon, ce que le menu de spawn a créé. Mais le mod dessine
par-dessus une enveloppe de **180 km de rayon**, définie par le champ `Radius` de son `Config.xml` et
exprimée en kilomètres. C'est ce qui explique qu'on puisse se retrouver « dans » la géante en la
croyant petite.

**Son anneau est bien plus large que le défaut documenté.** La commande `/RGG.AddRing` a généré un
`RingOuterScale` de **3,98** là où la documentation annonce 2,5 :

| | Multiplicateur | Rayon |
|---|---|---|
| Bord intérieur | 1,10 | 198 km |
| Bord extérieur | **3,98** | **716 km** |

L'ensemble occupe donc 716 km de rayon, 1 432 km de diamètre : le plus gros objet du système, et de
loin. Vu depuis Kerbin à 2 899 km, il fait **27,7°** de diamètre apparent.

`ConstrainNearbyAsteroidsToRing` est à `true`, donc les astéroïdes de la zone sont concentrés dans
l'anneau plutôt que dispersés autour. Combiné à la densité procédurale, l'anneau devient une vraie
ceinture minière.

**Les ressources collectables**, par bloc collecteur externe :

| Zone | Ressource | Quantité par cycle |
|---|---|---|
| Anneau | `Iron,Iron,Iron,Nickel,Nickel,Nickel,Silicon,Silicon,Gold` pondéré 40/30/20/10 % | 100 |
| Haute atmosphère | Ice | 1 000 |
| Basse atmosphère | Silicon | 1 000 |

Un cycle vaut cinq secondes par collecteur. Les seuils de profondeur : sous 82 % du rayon les
ressources basses commencent à apparaître, sous 78 % elles sont seules.

**Réserve sur la pondération** : un joueur rapporte dans la discussion du mod que seule la première
entrée de la liste est réellement collectée, malgré les poids, et l'échange s'arrête sans résolution.
À vérifier au premier collecteur posé. Le repli est une ressource unique par zone.

**Modifier la config de la géante** demande de passer `OverrideFromConfig` à `true`, et **il repasse à
`false` de lui-même à la sauvegarde suivante** : c'est un déclencheur à usage unique, pas un
interrupteur. Le fichier déclare par ailleurs `encoding="utf-16"` alors qu'il est physiquement en
UTF-8 sans BOM. Cette incohérence vient du mod : la laisser telle quelle, c'est ce qu'il relit.

## Les astéroïdes

`ProceduralDensity` vaut **0.35**, la densité « Infinite Normal » qu'utilise Keen sur ses propres
serveurs, sur une échelle de 0 à 1. Le champ était **absent** du monde, ce qui équivaut à 0, et à
zéro aucun astéroïde n'apparaît jamais.

Les astéroïdes procéduraux sont générés à la volée autour des joueurs et détruits quand on s'éloigne.
Ils sont en nombre pratiquement infini et **ne consomment pas de mémoire** : seuls ceux qu'un joueur
creuse deviennent des fichiers dans la sauvegarde.

**`ProceduralSeed` est figé à 0 et ne doit plus jamais changer.** Modifier cette graine déplacerait
tous les astéroïdes du monde, y compris ceux abritant une base. Elle a été écrite pendant que le monde
n'en contenait aucun, ce qui était le seul moment sûr.

Un filtre installé automatiquement par Real Gas Giants complète le dispositif :

```xml
<AsteroidFilterInfo Name="RemoveNearGasGiant" Priority="10" />
```

Aucun astéroïde n'apparaît à l'intérieur de la géante.

## Le modpack retenu

| Mod | Rôle | Voxels | Poids |
|---|---|---|---|
| Text HUD API `758597413` | dépendance RGG | 0 | 1 Mo |
| Visual Overrides API `3222232482` | dépendance RGG | 0 | 1 Mo |
| Asteroid Filter API `3218645300` | dépendance RGG | 0 | 1 Mo |
| Real Gas Giants `3232085677` | moteur de géante gazeuse | **0** | 334 Mo |
| Kerbin `2941085186` | départ, variante **vanilla** | **0** | 109 Mo |
| Umbris `3118433062` | satellite | 1 | 36 Mo |
| Torvion `3028355567` | satellite | 1 | 110 Mo |
| Ignis `3343005457` | monde en fusion, le plus lointain | 5 | 167 Mo |
| Tohil `2296726670` | satellite | 5 | 60 Mo |
| Argus `3146087212` | l'enfer, quatre sauts | 6 | 176 Mo |
| Satreus `2266665708` | second monde respirable | 8 | 180 Mo |
| Nivis `3684013414` | monde gelé, trois sauts | 8 | 396 Mo |

Douze mods, **34 emplacements de voxel**, environ **1,53 Go** à télécharger au premier join.

### Le budget voxel

Space Engineers ne supporte que **128 matériaux voxel actifs**, sur une structure de 8 bits. Keen a
classé la demande d'augmentation en « Considered (Not Planned) » après quatre ans et plus de deux
cents votes.

| | |
|---|---|
| Vanilla | 62 (19 astéroïdes, 43 planétaire) |
| Les douze mods | 34 |
| **Total** | **96 / 128** |
| **Marge** | **32 emplacements** |

Le dépassement est **silencieux** : aucune erreur, les planètes affichent de la pierre d'astéroïde
partout et les minerais perdent leurs textures. C'est pourquoi le décompte des voxels est un critère
d'examen à part entière dans `.claude/skills/check-se-mod/`.

**Un mod actif consomme ses emplacements même si sa planète n'est pas posée** : les définitions sont
chargées au démarrage du monde. Retirer une planète du système veut donc dire retirer son mod, pas
seulement renoncer à la placer. C'est ce qui a libéré 28 emplacements en abandonnant cinq candidats.

## L'environnement, tranché

Tous ces réglages sont **globaux au monde**. Aucun ne s'applique à une planète en particulier, donc
en activer un pour un corps l'active pour tous. Ils vivent en double : dans `Sandbox.sbc` (le
checkpoint) et dans `Sandbox_config.sbc` (le sous-ensemble que le serveur lit sans charger le monde).
Les deux doivent concorder.

| Réglage | Valeur | Ce qu'il apporte |
|---|---|---|
| `WeatherLightingDamage` | `true` | les météos d'Argus, Torvion et Nivis passent par le système de foudre pour infliger leurs dégâts. Sans lui, les six tempêtes d'Argus ne font strictement rien. Contrepartie : la foudre devient mortelle partout |
| `EnvironmentHostility` | `NORMAL` | une vague de météorites toutes les 30 à 60 min, la première à 30 min. Ne gouverne que ça |
| `SolarRadiationIntensity` | `1` | allume le gradient de radiation. Valeur neutre d'un multiplicateur, **non mesurée** : à calibrer en jeu |
| `EnableSunRotation` | `true` | le cycle jour/nuit est un acquis, avec son intervalle de 120 min |
| `EnableSpiders`, `EnableWolfs`, `EnableEncounters` | `false` | supprime la faune de Satreus et Nivis, et les rencontres. Laissé en l'état |
| `EnableEconomy` | `false` | à n'activer qu'une fois la géométrie figée |

### Le mécanisme de radiation a quatre niveaux

| Niveau | Réglage | Portée |
|---|---|---|
| Le mécanisme | `EnableRadiation` | global, actif |
| L'intensité au soleil | `SolarRadiationIntensity` | global, à 1 |
| La protection d'une planète | `SolarRadiationProtectionFactor` | **par planète** |
| L'émission propre d'une planète | `RadiationGain` | **par planète** |

Valeurs vanilla relevées dans `PlanetGeneratorDefinitions.sbc` : EarthLike, Alien et Titan protègent
à 1.8, Mars à 0.2, et **Europa à 0** avec une émission propre de 0,6 par seconde, commentée dans le
fichier « No protection from solar radiation ».

**Une planète mortelle sans protection, c'est la planète qui le décide**, par son `RadiationGain`.
Aucun réglage global ne peut rendre radioactive une planète qui ne l'a pas déclaré. Ce que le réglage
global apporte, c'est le gradient : les mondes mal protégés deviennent dangereux au soleil, les mondes
bien protégés restent vivables. Les deux paramètres sont visibles, la formule de leur combinaison ne
l'est pas : le gradient est certain, son ampleur non.

Les météos vanilla portent un `RadiationGain` **négatif** (`-0.6` pour pluies, brouillards et orages,
plage `[-100, 100]`), donc elles protègent du soleil. S'abriter d'une tempête a un sens mécanique.

### Un réglage refusé

Orlunda réclamait la **désactivation de la rotation du soleil** pour que son verrouillage de marée
soit fidèle. Refusé : tout le système aurait perdu son cycle jour/nuit pour un effet sur une seule
planète. Elle a finalement été écartée pour d'autres raisons.

## Les mécaniques à ne pas réapprendre

### Déplacer un corps, jamais le redimensionner

La position d'une planète vit dans `SANDBOX_0_0_0_.sbs` comme un simple attribut, indépendamment de
son fichier `.vx2`. La déplacer ne touche pas son terrain. **Son rayon, en revanche, est encodé dans
le nom du fichier voxel** (`Kerbin-1119735009d120000.vx2`, où `d120000` est le diamètre) et ne se
change jamais après coup : la taille se choisit définitivement au spawn.

D'où la méthode de travail : poser tous les corps **en grappe serrée près de l'origine**, sans
voyager, puis les disperser en écrivant leurs coordonnées. Le `.sbsB5` est supprimé après chaque
écriture, il restaurerait l'état précédent au chargement.

Ces fichiers sont écrits par le jeu : les modifier par **substitution de texte**, jamais par un aller
et retour dans un sérialiseur XML, qui réordonnerait les attributs et réécrirait les namespaces. Et
l'ordre des éléments compte : le sérialiseur .NET les lit en séquence, donc un élément inséré au
mauvais endroit corrompt le monde sans que rien ne le signale avant longtemps.

### L'axe solaire de l'Empty World est de travers

L'Empty World part avec un axe incliné d'environ 45°, là où le preset *Star System* l'a à plat. Les
cycles jour/nuit en dépendent. Corrigé sur ce monde, valeurs copiées du Star System :

| Fichier | Valeurs posées |
|---|---|
| `Sandbox.sbc` | `BaseSunDirection` et `SunDirectionNormalized` à `x=0 y=0 z=1` |
| `SANDBOX_0_0_0_.sbs` | `SunAzimuth` à `3.14159274`, `SunElevation` à `0` |

`SunDirectionNormalized` est recalculé en continu par le jeu, seul `BaseSunDirection` compte vraiment.

### Se déplacer dans un système de 8 800 km

| Touche | Effet |
|---|---|
| `F8` | caméra spectateur libre |
| **`Shift` + molette** | débride la vitesse de la caméra |
| `Ctrl` + molette | vitesse de rotation de la vue |
| **`Alt+F10` → Entity list → Planets** | téléporte la caméra à la planète choisie |
| **`Ctrl + Espace`** | téléporte l'ingénieur, **et le vaisseau où il est assis**, à la caméra |
| `F6` | rend le contrôle à l'ingénieur |

### Il n'y a pas d'étoile

Le soleil vanilla est une **direction de lumière globale** plus un skybox, pas un objet. Toutes les
planètes reçoivent la même lumière, dans la même direction, au même moment. « Proche de l'étoile »
n'a donc aucune existence mécanique : la chaleur d'Ignis est une propriété de sa définition, pas de
sa position. Le placement est libre, et gouverné par un seul critère réel, le temps de trajet.

### Ce qui calibre les distances

Le jump drive vanilla porte à **2000 km**, le Prototech à 6000 km. La vitesse est plafonnée à 100 m/s
et **ne se règle pas dans les paramètres de session** : `AdjustableMaxVehicleSpeed` ne concerne que
les blocs de suspension. Un trajet de 2000 km représente donc 5 h 30 de vol direct : le jump drive est
l'infrastructure de base d'un système solaire, pas un confort.

Repères tirés du preset Star System de Keen, où EarthLike et Mars sont à 1 934 km, soit un saut tout
juste : une lune à 200 à 300 km de sa planète, et 100 km de centre à centre comme minimum absolu
(Mars et Europa).

### Aucune lune ne peut orbiter

Les voxels ne se déplacent pas dans ce moteur. Les lunes de ce système sont posées et immobiles.
C'est une limite du jeu, pas un choix, et c'est exactement ce que Real Solar Systems contourne par une
illusion : fausses planètes en mouvement, vraies planètes parquées au loin, téléportation du joueur.

## Ce qui a été écarté, et pourquoi

| Écarté | Motif |
|---|---|
| **Real Solar Systems** | l'éditeur ne fonctionne qu'en solo, son auteur reconnaît les transitions de zone instables en multijoueur, et une dépendance obligatoire a disparu du Workshop |
| **Real Stars** | même dépendance disparue, `Solar Blocks Override`, qui porte précisément la production des panneaux solaires alors que le mod supprime le soleil du skybox |
| **Water Mod** `2200451495` | le plus coûteux en simulation, pour un gain esthétique, sur un hôte mono-thread. Une régression non corrigée depuis la 1.210 |
| **Jormun** `3618043241` | dépendance obligatoire au Water Mod, et 12 emplacements de voxel, le plus gourmand du lot |
| **Luma** `2286318683` | son auteur annonce des problèmes en multijoueur dus à ses fichiers de nuages, non corrigeables. Et 900 km de diamètre, au-delà du menu de spawn |
| **Orlunda** `2873186053` | 9 voxels, et son concept réclamait de figer le soleil pour tout le système |
| **Miasma** `3617496051` | 9 voxels et 588 Mo, et ses marais sont secs sans le Water Mod |
| **Mythu** `3654267020` | 5 voxels, le moins éprouvé du lot avec 868 abonnés |
| **Tharsis** `3262558921` | 4 voxels, redondant avec les autres mondes arides retenus |
| **Tibur** `3617040986` | 1 voxel seulement, mais redondant |

## Réserves sur les mods retenus

- **Argus** introduit un minerai, **Hydronite**, qui se comporte comme la glace en moins volumineux,
  et apporte son propre véhicule de réapparition.
- **Nivis** annonce des matériaux voxel personnalisés, est taguée `Character` parce qu'elle ajoute des
  *Petrified Sabiroids* (neutralisés par `EnableSpiders=false`, avec leur butin d'uranium), et son
  auteur reconnaît un coût en particules tout en **proposant une version à météo vanilla sur demande**
  si les machines modestes souffrent. Licence restrictive, sans conséquence sur serveur.
- **Kerbin** livre deux variantes, vanilla et prête pour le Water Mod : **la vanilla est celle
  posée**. Sa géographie étant dessinée autour d'océans, ses îles sont à sec des plateaux entourés de
  fosses.
- **Satreus** embarque des araignées nocturnes et des rencontres, tous deux neutralisés.
- **Torvion** est annoncée comme lune, mais 0.7 g et 1 atm lui donnent un profil de planète.
- **Real Gas Giants** est un mod porteur de code, du même auteur que trois items disparus du Workshop
  en juillet 2026.

Ignis, Torvion, Umbris et Argus viennent de la même main, toutes mises à jour le 8 septembre 2025.

## Ce qui reste à faire

- **Basculer en `Survival`.** La cible est décidée : ce système sera joué en survie, et c'est ce qui
  donne son sens à l'étagement des gravités, des minerais et des distances. `Creative` est maintenu le
  temps des tests, sur le monde local comme sur le serveur, et se bascule dans les paramètres avancés
  du monde une fois la géométrie éprouvée.
- **Choisir les rencontres.** Modular Encounters Systems `1521905890` est le socle retenu : framework
  de spawn très vivant (432 000 abonnés, 30 Mo, maintenu par enenra et CptArthur depuis la retraite de
  Meridius_IX). Il gère neuf types de spawn, du cargo spatial à la rencontre de boss, et **désactive
  de lui-même** Cargo Ships, Random Encounters, Wolves et Spiders pour les remplacer. Mais il
  **n'apporte aucun contenu seul** : tout dépendra des mods de rencontres posés dessus, qui restent à
  examiner. Il va en tête du modpack, avant eux.
  Deux points de vigilance : le message `Reference issue detected (circular reference or wrong order)`
  qui fait échouer le téléchargement des mods sur certains serveurs dédiés se soigne par la mise à jour
  des DLL Steam, que l'entrypoint fait déjà, et par Torch, que nous utilisons. Et
  `AutodetectDependencies=true` est le mécanisme qui produit ce genre de boucle quand plusieurs mods
  déclarent le même framework : à repasser à `false` si le symptôme apparaît.
- **Régler les créatures.** Décidé : MES seul, avec `OverrideVanillaCreatureSpawns` à `true` dans sa
  configuration admin, plutôt que le mod séparé `Planet Creature Spawner` `2371761016` qui allume
  exactement le même drapeau. MES scanne alors les planètes, récupère les créatures qu'elles
  déclarent déjà et les fait spawner par son propre système, avec ses conditions de météo, de terrain
  et de score de menace, plus une liste noire par planète. Cette configuration vit dans le `Storage`
  du monde, donc elle se fait **sur le serveur**.
- **Décider du contenu de rencontres au-delà d'Abandoned Settlements**, qui ne peuple que les
  planètes à atmosphère.
- **Nettoyer ou garder la rencontre Factorum** présente dans la graine.
- **Vérifier en jeu** : la visibilité d'Ignis et d'Argus à 6 000 et 8 800 km, le puits de gravité de
  la géante autour de Tohil, la pondération des ressources de l'anneau, et la calibration de
  `SolarRadiationIntensity`.
- **Basculer en `Survival`** quand les tests seront finis.

## Régénérer la graine après une modification du monde

Le monde vivant du serveur et la graine du dépôt sont deux choses distinctes. Modifier le système
suppose de refaire le trajet complet :

1. récupérer ou rouvrir le monde sur un poste de jeu, y faire les changements ;
2. **aligner ses paramètres de session** sur `server/config/SpaceEngineers-Dedicated.cfg`, sur
   `Sandbox.sbc` et `Sandbox_config.sbc` ;
3. recopier le dossier dans `server/world-seed/`, **sans le dossier `Backup/`** qui pèse cinq fois le
   monde, et sans `SANDBOX_0_0_0_.sbsB5` ;
4. vérifier qu'aucun Steam64 n'y figure, le dépôt étant public ;
5. commiter : le workflow reconstruit l'image, puisque `server/world-seed/**` est dans ses chemins ;
6. pointer `specs.ts` sur le nouveau tag et provisionner ;
7. sur le serveur, supprimer `instance/Saves` pour que le monde soit recréé depuis la graine.
