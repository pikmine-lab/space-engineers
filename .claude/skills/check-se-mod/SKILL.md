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

## 3. Conflits

Il n'existe aucune source de données sur les incompatibilités. Ce qui est réellement détectable :

- **Le même framework sous plusieurs identifiants.** WeaponCore existe en `1918681825` et en
  `3154371364` (« 3.0 »). Deux mods du pack peuvent pointer chacun sur un identifiant différent, et
  charger les deux est une collision franche. À chaque ajout, vérifier qu'aucune dépendance du pack
  n'est une autre version d'un mod déjà présent.
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

Le serveur tourne en `ExperimentalMode`, avec les scripts in-game autorisés : les mods porteurs de
code sont donc admis. Ils restent plus fragiles que les mods de blocs purs, puisqu'ils dépendent
d'une API qui bouge à chaque mise à jour du jeu. C'est un facteur de risque à peser, pas un motif
d'exclusion.

Ne jamais présenter un signal automatique comme une conclusion. « Mis à jour il y a 71 mois » est un
fait ; « ce mod est cassé » est une hypothèse tant que rien, ni commentaire ni test, ne l'a montré.
Beaucoup de mods de blocs purs fonctionnent des années sans mise à jour, alors qu'un mod à code
casse au moindre changement d'API.

## 5. Écrire dans le modpack

`server/modpack.txt`, un identifiant par ligne, commentaire de fin de ligne avec le nom du mod.

**L'ordre est significatif** : en cas de collision, le mod le plus bas l'emporte. Les frameworks et
les dépendances vont en haut, ce qui doit avoir le dernier mot en bas. Ne jamais trier la liste.

Rappeler ensuite les deux conséquences opérationnelles :

- l'ajout ne prend effet qu'après `nr provision`, qui met à jour la variable du service et
  redéploie ;
- **un monde neuf ignore les mods à son premier démarrage**, puisqu'il n'existe pas encore au moment
  de l'injection. Le premier lancement modé demande toujours un second démarrage.
