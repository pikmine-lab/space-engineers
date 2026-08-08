---
name: check-se-mod
description: Examiner un mod Space Engineers avant de l'ajouter au modpack du serveur : compatibilité avec la version en service, dépendances manquantes, conflits avec les mods déjà retenus. À utiliser dès que Pierre propose un lien Steam Workshop ou un identifiant de mod, qu'il demande si un mod « passe », s'il est à jour, ce qu'il requiert, ou qu'il veut ajouter, retirer ou réordonner une entrée de server/modpack.txt.
---

# Examiner un mod avant de l'ajouter au modpack

Le but n'est pas de dire « ce mod a l'air bien ». C'est de répondre à trois questions vérifiables :
**tourne-t-il sur la version en service, que lui manque-t-il, et avec quoi se cogne-t-il ?**

## Le périmètre, décidé et non rediscuté

**Steam Workshop uniquement.** Les mods mod.io exigent le crossplay, donc `NetworkType=eos`, ce qui
change le réseau du serveur et met en jeu l'accès au Workshop. Un mod qui n'existe que sur mod.io
n'est pas ajouté : on cherche un équivalent Steam, ou on s'en passe. Ce choix se rouvre seulement si
des joueurs console rejoignent le groupe.

## 1. Collecte automatique

```sh
python .claude/skills/check-se-mod/check-mod.py <url-ou-id> [...] --modpack server/modpack.txt
```

Accepte des URLs ou des identifiants bruts, plusieurs à la fois. Il lit la date de publication du
serveur dédié à chaque exécution : la référence de fraîcheur n'est jamais une date en dur qui
vieillit dans un fichier.

Ce que l'outil bloque tout seul, parce que c'est mécanique :

- **un item qui n'est pas de Space Engineers 1** : `consumer_app_id` doit valoir `244850`. C'est le
  garde-fou contre Space Engineers 2, qui vit sous un autre identifiant.
- **un item qui n'est pas un mod** : le Workshop héberge sous la même forme d'URL des scripts
  in-game, des blueprints, des mondes et des scénarios. Seuls les items tagués `mod` ont leur place
  dans `<Mods>`. Un script in-game se colle dans un bloc programmable ; l'inscrire au modpack ne
  produit aucune erreur, le serveur ne charge simplement jamais ce qu'on croyait avoir ajouté.
- **un item banni ou masqué** : le serveur ne pourra pas le télécharger.

Le reste sort en `WARNING` ou `CHECK` : ce sont des pistes, pas des verdicts.

## 2. Ce que l'outil ne peut pas faire, et qu'il faut faire

**Lire la description en entier.** Les dépendances déclarées sur Steam sont peu fiables. Exemple
mesuré : « Shield Controller Weaponcore » ne déclare aucune dépendance alors que sa description
exige Defense Shields et WeaponCore. L'outil signale les identifiants cités dans le texte,
l'interprétation reste à faire.

**Distinguer un framework d'un mod de contenu.** Une page Workshop ne le dit pas toujours, et
plusieurs des mods les plus populaires de l'écosystème **n'ajoutent strictement rien seuls** :
Modular Encounters Systems ne fait apparaître aucune rencontre, Planet Creature Spawner aucune
créature, Real Gas Giants aucune planète, les API rien du tout. Ce sont des moteurs qui attendent
qu'un mod de contenu se pose dessus.

Le symptôme à repérer dans la description : « does not add », « expansion for », « add-on », ou une
invitation à s'en servir « with any other mod that ». Le poids trahit souvent : un framework pèse
quelques mégaoctets, un mod de contenu des dizaines. Se tromper là-dessus coûte une installation qui
ne produit rien, et l'illusion d'avoir réglé un problème.

Un cas particulier vaut d'être connu : un mod peut n'être qu'un **drapeau**. Planet Creature Spawner
pèse 0,2 Mo et sa seule fonction est d'exister pour que MES détecte son identifiant, ce que le
réglage `OverrideVanillaCreatureSpawns` de MES fait tout aussi bien. Lire le code du framework quand
il est public répond à ce genre de question en une minute.

**Lire les commentaires récents.** C'est le seul endroit où l'on apprend qu'un mod est cassé quand
l'auteur a disparu. Trier par les plus récents et chercher les signalements postérieurs à la
dernière grosse mise à jour du jeu.

```sh
https://steamcommunity.com/sharedfiles/filedetails/comments/<id>
```

**Lire le changelog**, qui date les vraies corrections plutôt que les retouches de description :

```sh
https://steamcommunity.com/sharedfiles/filedetails/changelog/<id>
```

**Regarder le dépôt de code quand il existe.** L'outil extrait les liens GitHub ou GitLab de la
description. Un dépôt en dit plus qu'une page Steam : date du dernier commit, issues ouvertes
mentionnant la version courante, présence de correctifs non encore publiés. Un mod dont la page
Steam semble morte mais dont le dépôt bouge n'est pas le même risque qu'un mod mort des deux côtés.

**Compter les voxels d'un mod de planète.** C'est le seul critère qui puisse invalider une sélection
entière, et il est **silencieux** : le jeu ne supporte que **128 matériaux voxel actifs**, sur une
structure de 8 bits, et au-delà les planètes affichent de la pierre d'astéroïde partout tandis que
les minerais perdent leurs textures. Aucune erreur, aucun message. Keen a classé la demande
d'augmentation en « Considered (Not Planned) » après quatre ans.

Le vanilla en occupe déjà **62** (19 pour les astéroïdes, 43 pour le planétaire), ce qui laisse **66
emplacements** pour l'ensemble des mods. Presque aucun auteur ne chiffre sa consommation, et ceux qui
la mentionnent se contentent d'un « custom voxels » sans nombre : elle se **mesure**, elle ne se lit
pas.

La mesure demande d'être abonné au mod. Compter, dans les `.sbc` du dossier téléchargé, les
`VoxelMaterialDefinition` dont le `SubtypeId` n'existe pas déjà dans `Content/Data/VoxelMaterials*.sbc`
du jeu. Un matériau qui surcharge un matériau vanilla ne coûterait rien, mais en pratique les mods de
planètes ajoutent au lieu de surcharger. Les ordres de grandeur observés vont de 0 à 12 par planète,
sans corrélation avec le poids du mod : une planète de 109 Mo peut ne rien coûter quand une autre en
consomme neuf.

**Le piège** : un mod actif consomme ses emplacements **même si sa planète n'est jamais posée**, les
définitions étant chargées au démarrage du monde. Renoncer à une planète ne libère rien ; il faut
retirer son mod.

## 3. Conflits

Il n'existe aucune source de données sur les incompatibilités. Ce qui est réellement détectable :

- **Le même framework sous plusieurs identifiants.** Un framework republié change d'identifiant, et
  les mods qui en dépendent ne suivent pas tous. WeaponCore en est le cas d'école : `1918681825` et
  `2496225055` (« CoreSystems ») ont **disparu du Workshop**, seul `3154371364` (« 3.0 ») subsiste.
  D'où deux risques, et le second est le plus fréquent : charger deux versions du même framework est
  une collision franche, et une dépendance déclarée peut pointer vers un identifiant **mort**, que le
  serveur ne pourra jamais télécharger. À chaque ajout, résoudre les dépendances déclarées *et*
  citées, et vérifier qu'elles répondent encore : l'outil ne teste que les identifiants qu'on lui
  passe, pas ceux qu'il découvre.
- **Deux mods qui remplacent la même chose.** Deux remplaçants d'armes vanilla, deux jeux de
  vaisseaux de réapparition, deux surcouches d'un même bloc : c'est le dernier de la liste qui
  gagne, l'autre est chargé pour rien et parfois à moitié.
- **Ce que les auteurs écrivent.** Beaucoup nomment explicitement les mods incompatibles. C'est la
  source la plus fiable dont on dispose.

Ce qui **n'est pas** détectable sans télécharger les mods : deux définitions portant le même
`SubtypeId` dans des fichiers `.sbc` distincts. Le dire quand le risque existe, ne jamais le
prétendre vérifié.

## 4. Rendre le verdict

Pour chaque mod, trois issues et rien d'autre : **retenu**, **retenu sous condition** (en nommant la
condition : une dépendance à ajouter d'abord, un mod à retirer), ou **écarté** avec le motif.

**Les blocs DLC ne sont jamais un motif d'écart**, et personne ici n'en possède : leurs définitions
sont livrées avec le jeu de base comme avec le serveur dédié, donc les prefabs qui en emploient
spawnent normalement. Le détail est dans le `CLAUDE.md`.

Le serveur tourne en `ExperimentalMode`, avec les scripts in-game autorisés : les mods porteurs de
code sont donc admis. Ils restent plus fragiles que les mods de blocs purs, puisqu'ils dépendent
d'une API qui bouge à chaque mise à jour du jeu. C'est un facteur de risque à peser, pas un motif
d'exclusion.

Ne jamais présenter un signal automatique comme une conclusion. « Mis à jour il y a 71 mois » est un
fait ; « ce mod est cassé » est une hypothèse tant que rien, ni commentaire ni test, ne l'a montré.

**Le signal d'âge ne se lit pas seul : il se croise avec le tag `NoScripts`.** L'outil sort les deux,
et c'est leur combinaison qui informe.

| | `NoScripts` | pas de `NoScripts` |
|---|---|---|
| **Récent** | très sûr | à surveiller aux mises à jour du jeu |
| **Ancien** | **souvent sans conséquence** | le vrai risque |

Un mod sans code ne dépend d'aucune API : ses définitions et ses prefabs survivent des années. Cas
mesuré : *Abandoned Settlements*, 49 mois sans mise à jour, tagué `NoScripts`, 95 000 abonnés, aucun
signalement de rupture dans ses commentaires récents. À l'inverse, un mod à code sorti il y a six
mois peut être tombé au dernier patch, comme Real Solar Systems l'a été par la 1.210. Écarter sur
l'âge seul fait perdre de bons mods et en garde de mauvais.

## 5. Écrire dans le modpack

`server/modpack.txt`, un identifiant par ligne, commentaire de fin de ligne avec le nom du mod.

**L'ordre est significatif** : en cas de collision, le mod le plus bas l'emporte. Les frameworks et
les dépendances vont en haut, ce qui doit avoir le dernier mot en bas. Ne jamais trier la liste.

Rappeler ensuite les deux conséquences opérationnelles :

- l'ajout ne prend effet qu'après `nr provision`, qui met à jour la variable du service et
  redéploie ;
- **un monde neuf ignore les mods à son premier démarrage**, puisqu'il n'existe pas encore au moment
  de l'injection. Le premier lancement modé demande toujours un second démarrage.
