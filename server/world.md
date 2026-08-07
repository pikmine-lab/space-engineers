# Le monde

Le serveur ne joue pas un scénario livré avec le jeu : il joue un **système solaire composé à la
main**. Ce document porte la conception de ce système, le registre des mods candidats, et les
raisons des choix. Il existe parce que le monde est la seule partie du serveur que le dépôt ne peut
pas entièrement décrire : les positions des planètes vivent dans un fichier binaire de sauvegarde,
pas dans du code.

`modpack.txt` dit *ce qui tourne sur le serveur*. Ce fichier dit *ce qui est envisagé*, et pourquoi.

**État : collecte des candidats.** Rien n'est sélectionné. Les tableaux ci-dessous s'allongent à
mesure que des planètes sont proposées, et la sélection se fera en une passe, quand la collecte sera
close.

## Le monde se construit en local, pas sur le serveur

Une planète ne se place qu'avec les outils créatifs, depuis le menu de spawn (`Shift+F10`), en
caméra spectateur. C'est un geste de jeu, pas une configuration. Le monde est donc **construit sur
un poste de jeu**, puis déposé dans le volume `se-data`.

Conséquence à assumer : le dépôt ne reconstruit pas ce monde à partir de rien. Il en décrit
l'intention, et le monde initial est déposé une fois.

## Les candidats : le corps

Les auteurs annoncent des **diamètres**, alors que le fichier de sauvegarde stocke des **rayons**.
Le menu de spawn plafonne à 120 km de diamètre : toute planète annoncée au-dessus demande un outil
externe.

La colonne des voxels est vide parce qu'aucun auteur ne la chiffre. Elle se remplit en comptant les
`VoxelMaterialDefinition` dans les fichiers du mod, une fois celui-ci téléchargé par abonnement.
C'est la mesure qui décidera de la taille possible de la sélection.

| Candidat | Diamètre | Gravité | Atmosphère | Minerais | Voxels |
|---|---|---|---|---|---|
| Orlunda `2873186053` | 120 km | 1.12 g | 0.89 atm, respirable | tous, U et Pt | ? |
| Ignis `3343005457` | 120 km | 1.08 g | 0.85 atm, 0 % O₂ | tous sauf U | ? |
| Kerbin `2941085186` | 120 km | n.c. | n.c. | répartis par zones | ? |
| Argus `3146087212` | 120 km | 1.45 g | 5 % O₂ | tous, U et Pt, **+ Hydronite** | ? |
| Miasma `3617496051` | 120 km | 1.2 g | 1.1 atm | tous sauf U | ? |
| Nivis `3684013414` | 120 km | n.c. | n.c. | tous, U et Pt | déclarés |
| Tharsis `3262558921` | 120 km | 0.75 g | 0.85 atm, 5 % O₂ | tous sauf U | ? |
| Mythu `3654267020` | 67 km | 0.63 g | aucune | tous, U et Pt | déclarés |
| Satreus `2266665708` | 60 km | 0.95 g | 0.9 atm, respirable | tous sauf U | ? |
| Tibur `3617040986` | 60 km | 0.5 g | 0.8 atm | tous, U et Pt | ? |
| Torvion `3028355567` | 50 km | 0.7 g | 1 atm, O₂ faible | tous, U et Pt | ? |
| Umbris `3118433062` | 45 km | 0.19 g | aucune | tous sauf U | ? |
| Tohil `2296726670` | 19 km | 0.33 g | 0.5 atm | tous sauf U et Pt | ? |
| Luma `2286318683` | 900 km | 1.86 g | 1 atm | glace seule | ? |
| Real Gas Giants `3232085677` | libre | conf. | conf. | 3 au choix | ? |

## Les candidats : faune, météo et suivi

`n.c.` veut dire non communiqué par l'auteur, ce qui n'équivaut pas à « aucune ». Une fiche muette
sur la faune ne prouve pas qu'il n'y en a pas.

| Candidat | Faune | Météo | Nourriture | Poids | Abonnés | MAJ |
|---|---|---|---|---|---|---|
| Orlunda | n.c. | aucun danger déclaré | oui | 186 Mo | 7 700 | 2025-12 |
| Ignis | aucune | canicules, pluies de cendre, vent faible | non | 167 Mo | 8 175 | 2025-09 |
| Kerbin | n.c. | n.c. | n.c. | 109 Mo | 1 306 | 2026-05 |
| Argus | aucune | **six types, dont pluie corrosive, tempête radioactive et un « Cataclysm »**, vent fort | non | 176 Mo | 3 794 | 2025-09 |
| Miasma | n.c. | aucun danger déclaré | oui | **588 Mo** | 5 216 | 2025-12 |
| Nivis | **Petrified Sabiroids** renforcés | tempêtes de neige, de grêle et de cendre, annoncées dangereuses | n.c. | 396 Mo | 2 795 | 2026-03 |
| Tharsis | aucune | tempêtes de poussière, vent faible | non | 145 Mo | 2 202 | 2025-09 |
| Mythu | n.c. | n.c. | non | 162 Mo | 868 | 2026-01 |
| Satreus | **araignées nocturnes** | tempêtes de sable, légèrement dangereuses | oui, sur les plateaux | 180 Mo | 21 412 | 2025-12 |
| Tibur | n.c. | aucun danger déclaré | non | 109 Mo | 3 032 | 2025-12 |
| Torvion | aucune | **orages électriques**, vent fort | n.c. | 110 Mo | 1 288 | 2025-09 |
| Umbris | n.c. | aucune, planète sans atmosphère | n.c. | **36 Mo** | 2 203 | 2025-09 |
| Tohil | n.c. | aucune, radiation solaire réduite | non | 60 Mo | 9 565 | 2025-09 |
| Luma | n.c. | températures élevées, pas de radiation | non | 124 Mo | 13 703 | 2025-09 |
| Real Gas Giants | aucune | zones de profondeur à dégâts progressifs, configurables | non | 334 Mo | 34 691 | 2026-01 |

Real Gas Giants n'est pas une planète mais un moteur : il déclare trois dépendances obligatoires,
Text HUD API `758597413`, Visual Overrides API `3222232482` et Asteroid Filter API `3218645300`,
soit 3 Mo au total.

## Ce que la configuration du serveur neutralise déjà

C'est le point le plus important à savoir avant de choisir sur la faune et la météo : **une partie
de ce que ces mods promettent ne se produira pas**, à cause de réglages déjà en place.

| Réglage actuel | Effet sur les candidats |
|---|---|
| `EnableSpiders=false` | supprime les araignées de Satreus **et** les Petrified Sabiroids de Nivis, avec leur butin d'uranium |
| `EnableWolfs=false` | supprime toute faune terrestre du même type |
| `EnableEncounters=false` | supprime les rencontres ajoutées par Satreus, Tohil, Luma et Orlunda |
| `WeatherSystem=true` | la météo fonctionne, les effets visuels et les vents sont actifs |
| `WeatherLightingDamage=false` | **annule les dégâts de foudre**, donc les six météos d'Argus qui passent toutes par ce système, et probablement une partie de celles de Torvion et Nivis |
| `EnvironmentHostility=SAFE` | réduit l'hostilité générale de l'environnement |

Autrement dit, dans l'état actuel, les planètes-défi perdent leur défi. Argus est le cas extrême :
son auteur écrit explicitement que ses météos reposent sur le système de foudre. Chacun de ces
réglages peut être changé, mais **ils sont globaux au monde** : activer les dégâts de foudre pour
Argus les active partout.

### Les réglages globaux réclamés par un seul candidat

| Candidat | Réglage exigé | Portée du dégât collatéral |
|---|---|---|
| Argus | `WeatherLightingDamage=true` | la foudre devient dangereuse sur toutes les planètes |
| Orlunda | rotation du soleil désactivée, `SunDirectionNormalized` à `x=0 y=-1 z=0` | tout le système perd son cycle jour/nuit |
| Nivis, Satreus | `EnableSpiders=true` | faune hostile réintroduite partout |

Un candidat qui perd son concept sans son réglage reste utilisable : Orlunda garde sa géographie et
ses minerais, Argus garde son relief et son uranium. Ce sont des choix d'ambiance, pas des blocages.

## Réserves particulières

- **Luma** : son auteur annonce lui-même, en titre de page, des problèmes en multijoueur dus à ses
  fichiers de nuages haute résolution, non corrigeables de son côté. Son diamètre recommandé de
  900 km dépasse par ailleurs la limite du menu de spawn. Deux réserves indépendantes.
- **Argus** : introduit un minerai, **Hydronite**, qui se comporte comme la glace en moins
  volumineux. Un minerai supplémentaire consomme des emplacements de voxel en plus de ceux de sa
  surface. Elle apporte aussi son propre véhicule de réapparition.
- **Nivis** : son auteur reconnaît un coût en particules, dit l'avoir réduit, et **propose une
  version à météo vanilla sur demande** si les machines modestes souffrent. Licence restrictive,
  sans conséquence pour un usage sur serveur.
- **Mythu** : le moins éprouvé du lot avec 868 abonnés.
- **Kerbin** : livre deux variantes, une vanilla et une prête pour le Water Mod. La variante vanilla
  est celle à faire apparaître. Sa géographie est dessinée autour d'océans, donc à sec ses îles
  deviennent des plateaux entourés de fosses.
- **Miasma** : ses marais sont du relief et de la texture, pas du liquide. Sans le Water Mod, écarté,
  c'est un marais sec. Deuxième plus lourd du registre.
- **Umbris** : publiée comme la lune de **Valkor** `3112058236`, planète non encore examinée. Rien
  ne couple techniquement les deux, la lune se pose où on veut.
- **Torvion** : annoncée comme lune, mais 0.7 g et 1 atm lui donnent un profil de planète.
- **Real Gas Giants** : mod porteur de code, du même auteur que trois items disparus du Workshop en
  juillet 2026. Il n'exige ni Real Stars ni Real Solar Systems.

Ignis, Tharsis, Torvion, Umbris et Argus viennent de la même main, toutes mises à jour le
8 septembre 2025, avec des fiches au format identique. Tibur et Miasma partagent un autre auteur.

## Écartés, et pourquoi

| Écarté | Motif |
|---|---|
| Water Mod `2200451495` | le plus coûteux en simulation de la sélection, pour un gain esthétique, sur un hôte mono-thread. Une régression non corrigée depuis la 1.210 |
| Jormun `3618043241` | sa dépendance au Water Mod est obligatoire et tout son intérêt est un fleuve qui ceinture la planète |
| Real Solar Systems | l'éditeur ne fonctionne qu'en solo, les transitions de zone sont reconnues instables en multijoueur par son auteur, et une dépendance obligatoire a disparu du Workshop |
| Real Stars | même dépendance disparue, `Solar Blocks Override`, qui porte précisément la production des panneaux solaires alors que le mod supprime le soleil du skybox |

**Aucune lune ne peut orbiter une planète.** Les voxels ne se déplacent pas dans ce moteur. Les
lunes de ce système seront posées et immobiles. C'est une limite du jeu, pas un choix, et c'est
exactement ce que Real Solar Systems contourne par une illusion.

## Le vanilla est gratuit

Huit planètes sont livrées avec le jeu : EarthLike, Mars, Alien, Triton, Pertam, Moon, Europa,
Titan. Elles ne coûtent **ni téléchargement aux joueurs, ni emplacement de voxel**, puisqu'elles
sont déjà comptées dans le budget de base. Tout ce qu'un mod de planète apporte se paye ; le vanilla
non.

## La limite qui décide de tout : 128 voxels

Space Engineers ne supporte que **128 matériaux voxel actifs**, sur une structure de 8 bits. Le
vanilla en consomme déjà **62** (19 pour les astéroïdes, 43 pour le planétaire), mesurés dans les
fichiers du jeu. Il reste **66 emplacements** pour l'ensemble des planètes moddées.

Keen a classé la demande d'augmentation en « Considered (Not Planned) » après quatre ans et plus de
deux cents votes. Ça ne bougera pas.

Le dépassement est **silencieux** : aucune erreur, les planètes se contentent d'afficher de la
pierre d'astéroïde partout et les minerais perdent leurs textures. C'est le risque principal de ce
monde, et c'est pourquoi le nombre de voxels d'un mod de planète est devenu un critère d'examen à
part entière dans `.claude/skills/check-se-mod/`.

## Ce qui calibre les distances

Le jump drive vanilla porte à **2000 km**. Le système livré par Keen est dimensionné là-dessus :
1 934 km entre EarthLike et Mars, soit un saut tout juste. Les repères tirés de son preset :

- une lune à **200 à 300 km** de sa planète ;
- **100 km** de centre à centre, c'est le minimum que Keen se permet (Mars et Europa) ;
- deux planètes voisines à **moins de 2000 km**, pour rester à un saut.

La vitesse est plafonnée à 100 m/s et **ne se règle pas dans les paramètres de session** :
`AdjustableMaxVehicleSpeed` ne concerne que les blocs de suspension. Les 1 934 km entre deux planètes
représentent donc plus de cinq heures de vol direct. Le jump drive est l'infrastructure de base d'un
système solaire, pas un confort.

### Le système de Keen, comme référence

Positions relevées dans `Content/CustomWorlds/Star System`, rayons en mètres.

| Corps | Rayon | Position | Distance du centre |
|---|---|---|---|
| Moon | 9 500 | `0, 120000, -130000` | 177 km |
| EarthLike | 60 000 | `-131072, -131072, -131072` | 227 km |
| Mars | 60 000 | `900000, 0, 1500000` | 1 749 km |
| Europa | 9 500 | `900000, 0, 1600000` | 1 836 km |
| Triton | 40 126 | `-350000, -2500000, 300000` | 2 542 km |
| Pertam | 30 000 | `-4000000, -65000, -800000` | 4 080 km |
| Alien | 60 000 | `0, 0, 5600000` | 5 600 km |
| Titan | 9 500 | `20000, 210000, 5780000` | 5 784 km |

## Les réglages du monde qui comptent

L'**Empty World** part avec un axe solaire incliné d'environ 45°, là où le preset *Star System* l'a
à plat. Les cycles jour/nuit en dépendent, donc l'axe est corrigé à la main sur la sauvegarde :

| Fichier | Valeurs à poser |
|---|---|
| `Sandbox.sbc` | `BaseSunDirection` à `x=0 y=0 z=1` |
| `SANDBOX_0_0_0_.sbs` | `SunAzimuth` à `3.14159274`, `SunElevation` à `0` |

Le fichier `SANDBOX_0_0_0_.sbsB5` est supprimé après l'édition : c'est une sauvegarde de secours qui
réintroduirait les anciennes valeurs.

**L'économie reste désactivée pendant toute la construction.** Les stations commerciales ne se
placent correctement sur des planètes ajoutées après coup que dans un monde où l'économie n'a jamais
tourné. Elle s'active quand la géométrie est figée. À savoir aussi : plus un monde porte de
planètes, moins chacune reçoit de stations.
