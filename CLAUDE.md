# space-engineers

Serveur dédié **Space Engineers 1** pour jouer entre amis, sur le VPS `pikmine`. Dépôt autonome :
l'image, la configuration, le modpack et le provisionnement vivent ici, et ces fichiers suffisent à
reconstruire le serveur.

Le socle partagé (`pikmine-lab/infra`) n'est pas sollicité : ce serveur ne consomme ni base de
données, ni inférence, ni Traefik. Il n'en emprunte que les conventions.

## La contrainte de départ

**Il n'existe pas de serveur dédié Space Engineers natif Linux.** Le binaire est un exécutable
Windows en .NET Framework, exécuté ici sous **Wine**. Tout le reste du dépôt découle de là :
le prefix Wine, l'installation de .NET 4.8, Xvfb, et le fait qu'aucune de ces briques ne soit
fournie par un projet officiel.

## Ce qui a été évalué, et écarté

Le paysage des images Docker Space Engineers a été inspecté par l'API GitHub, dates réelles à
l'appui (les pages Docker Hub sont trompeuses). Aucune n'est maintenue :

| Projet | Étoiles | Dernier commit | Écarté parce que |
|---|---|---|---|
| `mmmaxwwwell/space-engineers-dedicated-docker-linux` | 205 | fév. 2022 | abandonné, malgré sa popularité |
| `Devidian/docker-spaceengineers` | 140 | oct. 2024 | à l'arrêt, Wine 9 |
| `krobertson/space-engineers-torch` | 0 | fév. 2026 | dépôt personnel non éprouvé, mais **c'est la meilleure référence technique** : ses configs Torch et serveur, validées sur SE 1.208, sont la base de `server/config/` |
| `joshschools/space-engineers-dedicated-docker-linux` | 1 | mai 2026 | dépôt de deux jours, pas de correctif des DLL Steam |

D'où le choix d'un Dockerfile maison : une soixantaine de lignes, entièrement épinglées, plutôt
qu'une dépendance à un dépôt d'une personne qui peut disparaître.

**Torch, en revanche, est bien vivant** (dernier commit en juillet 2026) et c'est la brique la plus
solide de tout l'écosystème. Il apporte les plugins, les sauvegardes, les redémarrages planifiés et
les commandes d'administration. Le serveur tourne donc sous Torch, pas en direct.

## Le piège des DLL Steam, à ne pas réapprendre

Depuis le **11 juillet 2025**, le Steam Workshop stocke son contenu en chunks compressés zstd. Le
serveur dédié embarque des bibliothèques Steam d'**octobre 2023** qui ne savent pas les lire :
**le téléchargement des mods échoue**. Le correctif de Keen n'a pas réglé le cas de tout le monde.

`image/entrypoint.sh` télécharge donc le *Steamworks SDK Redist* (**appid 1007**, plateforme forcée
Windows) et écrase `steamclient64.dll`, `tier0_s64.dll` et `vstdlib_s64.dll`. **À refaire après
chaque mise à jour du jeu** : SteamCMD remet ses versions à lui, c'est pourquoi l'étape est dans
l'entrypoint et non dans le Dockerfile.

## Ce qui est épinglé, et la seule chose qui ne peut pas l'être

Épinglés : Wine (`10.0.0.0~noble-1`), Torch (build Jenkins `347`), l'image de base, et le tag
d'image déployé (`provision/src/specs.ts`).

**Le jeu, lui, ne peut pas être épinglé.** Les clients Steam se mettent à jour tout seuls, et un
serveur resté sur une version antérieure devient injoignable dès que Keen publie une mise à jour.
SteamCMD le rafraîchit donc à chaque démarrage. C'est le seul endroit où la règle « jamais
`latest` » du socle ne s'applique pas, et c'est subi, pas choisi.

Wine 11.0 stable existe aussi. Le choix de 10.0 est prudentiel : l'installation de .NET 4.8 est la
partie la plus fragile de l'image. Changer l'`ARG WINE_VERSION` et reconstruire suffit à essayer.

## Anatomie

```
image/          Dockerfile, entrypoint, injection du modpack
server/         compose, configuration de référence, modpack
provision/      provisionneur Dokploy idempotent
```

**L'image porte le runtime, le volume porte les données.** Le prefix Wine et Torch sont dans
l'image ; le jeu, le monde, les journaux et la configuration vivante sont dans le volume `se-data`.
Un conteneur peut être détruit et recréé sans rien perdre.

La configuration de `server/config/` n'est **recopiée que si le volume n'en a pas**. Une fois le
serveur en service, c'est le fichier du volume qui fait foi : l'écraser à chaque démarrage
annulerait silencieusement les réglages faits en jeu. Le dépôt décrit comment démarre un serveur
*neuf*.

## Le modpack comme code

`server/modpack.txt` est la source de vérité : un identifiant Workshop par ligne. Le provisionneur
en fait la variable `SE_MODS` du service Dokploy, et l'entrypoint réécrit l'élément `<Mods>` du
monde à chaque démarrage. **Ajouter un mod, c'est `nr provision`**, pas un fichier édité en SSH.

Trois choses à savoir :

- **L'ordre compte.** Quand deux mods touchent la même chose, celui du bas gagne. La liste n'est
  jamais triée, ni ici, ni dans le provisionneur.
- **Un monde neuf ignore les mods à son premier démarrage** : il n'existe pas encore au moment de
  l'injection, il est créé ensuite depuis le scénario. Le premier lancement modé demande donc un
  second démarrage.
- **`ExperimentalMode` doit passer à `true`** dans la configuration dédiée pour les scripts en jeu
  et pour un certain nombre de mods, qui plantent sans lui.

## Ce qui vit hors du dépôt

**Ce dépôt est public.** Rien qui désigne une machine ou une personne n'y entre. Tout ça vit dans le
`.env` du projet, ignoré par git, dont `.env.example` donne le gabarit :

| Variable | Contenu |
|---|---|
| `DOKPLOY_URL` | l'adresse du tableau de bord |
| `SE_ADMINS` | les Steam64 des administrateurs, séparés par des virgules |

Une seule exception, `~/.config/dokploy/token` : le jeton d'API sert aussi au dépôt `infra`, donc il
n'appartient pas à ce projet. `DOKPLOY_AUTH_TOKEN` dans le `.env` reste prioritaire s'il est défini.

Les administrateurs sont **réinjectés à chaque démarrage**, comme le modpack : la liste est du code.
En contrepartie, promouvoir quelqu'un depuis le jeu ne survit pas à un redémarrage.

## Déploiement

Image construite par GitHub Actions et publiée sur GHCR, déploiement par le provisionneur. Une
construction ne déploie rien : elle rend un candidat disponible, et c'est le tag écrit dans
`specs.ts` qui décide de ce qui tourne.

```sh
cd provision
ni                 # installe les dépendances
nr plan            # montre l'écart, ne change rien
nr provision       # applique
```

Le provisionneur lit l'état avant d'agir, n'agit que sur une différence réelle et **ne supprime
jamais rien** : vider la spec laisse le serveur tourner plutôt que de perdre un monde.

## Coordonnées

| Élément | Valeur |
|---|---|
| Hôte | `pikmine` |
| Port joueurs | **27016/udp** |
| Port de requête Steam | **8766/udp** |
| Projet Dokploy | `space-engineers`, service `server` |
| Volume | `se-data` |

Aucun port TCP n'est publié : ni Traefik, ni TLS, ni Remote API exposée.

## Limites connues

- **L'arrêt propre n'est pas garanti.** Wine s'intercale entre le `SIGTERM` de Docker et le jeu, et
  rien ne prouve que la sauvegarde de fin aboutisse. `stop_grace_period` est à 120 s et l'autosave
  à 5 minutes sert de filet. À vérifier sur un vrai arrêt avant de s'y fier.
- **La tenue en charge n'est pas mesurée.** La simulation de Space Engineers est essentiellement
  mono-thread et l'hôte est un EPYC virtualisé à 2,0 GHz. Ça devrait suffire à quelques joueurs,
  mais tant que rien n'a été mesuré, ce n'est qu'une hypothèse.
- **Le pré-téléchargement des mods par SteamCMD n'est pas tranché.** Le serveur les télécharge
  lui-même, DLL corrigées à l'appui. Si cela s'avère insuffisant, le repli est de les pré-télécharger
  avec `workshop_download_item 244850`, dont le fonctionnement en login anonyme reste à vérifier.
