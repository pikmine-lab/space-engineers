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
image/            Dockerfile, entrypoint, injection du modpack
server/           compose, configuration de référence, modpack
server/world-seed/  le monde lui-même, en premade checkpoint
provision/        provisionneur Dokploy idempotent
```

**L'image porte le runtime, le volume porte les données.** Le prefix Wine et Torch sont dans
l'image ; le jeu, le monde, les journaux et la configuration vivante sont dans le volume `se-data`.
Un conteneur peut être détruit et recréé sans rien perdre.

La configuration de `server/config/` n'est **recopiée que si le volume n'en a pas**. Une fois le
serveur en service, c'est le fichier du volume qui fait foi : l'écraser à chaque démarrage
annulerait silencieusement les réglages faits en jeu. Le dépôt décrit comment démarre un serveur
*neuf*.

## Le monde est une graine, pas un scénario

Le serveur ne joue pas un scénario de Keen : il joue un **système solaire composé à la main**,
douze corps autour de Kerbin. Or **une planète ne se place qu'avec le menu de spawn créatif**, en
caméra spectateur : c'est un geste de jeu, pas une configuration, donc le monde ne peut pas être
généré depuis du code.

Il voyage donc dans l'image comme **premade checkpoint**, et le jeu le recopie en monde vivant au
premier démarrage, exactement comme il le faisait avec `Star System`. Réutiliser ce mécanisme plutôt
que d'inventer une étape de déploiement était le point : c'est le chemin par lequel le serveur crée
son monde depuis toujours.

`server/world.md` porte la conception du système, les mesures et les décisions. Ce fichier-ci ne
porte que la mécanique.

**Le reset tient en trois gestes.** La graine est rafraîchie depuis l'image à chaque démarrage,
puisque le jeu lit ce dossier et n'y écrit jamais. Après un test qui casse tout : arrêter le
conteneur, supprimer `instance/Saves`, redémarrer. Le monde recréé est celui du dépôt.

**Le piège qui coûte cher : une fois le monde créé, c'est lui qui décide.** La configuration dédiée
ne sert qu'à sa création ; ensuite le serveur lit le `Sandbox_config.sbc` du monde. Un monde
construit en solo arrive donc avec les défauts du menu de création, et les impose au serveur en
silence : `OnlineMode` à `OFFLINE`, deux joueurs, des multiplicateurs de triple. **Aligner les
paramètres de session du monde sur `server/config/` avant de régénérer la graine**, sur ses deux
copies, `Sandbox.sbc` et `Sandbox_config.sbc`.

La graine est déclarée `binary` dans `.gitattributes` : les `.vx2` sont des flux gzip que la
conversion de fins de ligne corromprait.

## Le modpack comme code

`server/modpack.txt` est la source de vérité : un identifiant Workshop par ligne. Le provisionneur
en fait la variable `SE_MODS` du service Dokploy, et l'entrypoint réécrit l'élément `<Mods>` du
monde à chaque démarrage. **Ajouter un mod, c'est `nr provision`**, pas un fichier édité en SSH.

Trois choses à savoir :

- **L'ordre compte**, deux fois plutôt qu'une. Quand deux mods touchent la même chose, celui du bas
  gagne, donc la liste n'est jamais triée, ni ici, ni dans le provisionneur. Et les **frameworks vont
  en tête** : un mauvais ordre est l'une des causes du `Reference issue detected` ci-dessous.
- **La graine reçoit le modpack comme les mondes vivants.** L'ancienne règle « un monde neuf ignore
  ses mods jusqu'au second démarrage » ne vaut plus : l'entrypoint patche aussi
  `premade-world`, donc le monde naît avec son élément `<Mods>` déjà juste.
- **Seul le Workshop Steam est admis.** Les mods mod.io exigent le crossplay, donc `NetworkType=eos`,
  ce qui change le réseau du serveur et met en jeu l'accès au Workshop. À rouvrir seulement si des
  joueurs console rejoignent.

`.claude/skills/check-se-mod/` porte la procédure d'examen d'un mod avant ajout, avec son outil de
collecte. Elle existe parce que les données Steam trompent : les dépendances déclarées sont souvent
absentes alors que la description les nomme, et le Workshop héberge sous la même forme d'URL des
scripts in-game et des blueprints, qui n'ont rien à faire dans `<Mods>`.

## Scripts

Le serveur tourne en **`ExperimentalMode`**, avec **`EnableIngameScripts`** : les blocs programmables
et les mods porteurs de code sont autorisés. Ce sont deux réglages distincts, et le second est ignoré
sans le premier, la partie serveur traitant le scripting comme expérimental.

`EnableScripterRole` reste à `false` : tout le monde peut écrire des scripts, sans promotion
préalable. Conséquence à connaître : n'importe quel joueur peut faire tourner du code sur le serveur.
Acceptable entre gens qui se connaissent, à revoir si le serveur s'ouvre.

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

**Vérifié en service le 2026-08-07** : Wine 10 + .NET Framework 4.8 + Torch `v1.3.1.347` font tourner
Space Engineers **1.210.12**. Le monde se crée depuis le scénario, le serveur atteint « Game ready »
sans intervention, et il répond aux requêtes Steam depuis Internet sur 27016/udp en s'annonçant
`Pikmine, 0/8 joueurs`. Consommation au repos, monde vide : **45 % d'un cœur et 1,7 Go**.

Le pare-feu n'a demandé aucune règle : les ports publiés par Docker passent par la chaîne `FORWARD`,
que `ufw` ne filtre pas ici, et non par `INPUT`.

## Trois pièges rencontrés, corrigés, à ne pas réapprendre

**Wine installe Mono tout seul et casse le prefix.** Laissé à lui-même, `wineboot --init` déclenche
l'installation automatique de Mono dans un prefix à moitié construit. Elle se bloque cinq minutes,
puis toute commande Wine ultérieure échoue sur `could not load kernel32.dll, status c0000135`.
`WINEDLLOVERRIDES="mscoree=d"` sur le seul appel d'initialisation suffit à l'éviter. Mono n'est de
toute façon pas voulu ici : Torch est une application WPF, que seul le vrai .NET Framework exécute.

**Sans TTY, le serveur meurt en silence.** Space Engineers écrit ses journaux par l'API console de
Windows. Sans pseudo-terminal, l'écriture lève `System.IO.IOException: Pipe not connected` et le
serveur s'arrête pendant son démarrage, avant même de créer le monde. Le symptôme trompe :
**le conteneur reste `Up`**, parce que `xvfb-run` attend toujours, alors que plus rien ne tourne à
l'intérieur. D'où `tty: true` dans le compose. Devant un conteneur en vie mais un serveur injoignable,
vérifier d'abord la liste des processus : s'il n'y a que `xvfb-run` et `Xvfb`, le jeu est mort.

**`xvfb-run` ne peut pas être PID 1.** Le conteneur démarrait, Xvfb tournait, et le jeu ne se lançait
jamais, sans une ligne de journal. L'arbre des processus donnait la réponse : `xvfb-run` restait
bloqué en `sigsuspend`. Un processus en PID 1 ignore les signaux dont le gestionnaire est celui par
défaut, donc le réveil que `xvfb-run` attend après avoir lancé Xvfb ne lui parvient jamais, et il
n'exécute jamais la commande qu'on lui a confiée. L'entrypoint lance donc Xvfb lui-même puis fait
`exec wine`. Bénéfice au passage : **le jeu est PID 1**, donc `docker stop` lui envoie `SIGTERM`
directement au lieu de le confier à une enveloppe shell qui l'absorberait.

La leçon commune à ces trois pièges : **un conteneur `Up` ne prouve rien**. Les trois se
présentaient comme un conteneur en bonne santé sans serveur dedans. Le premier réflexe de diagnostic
est `docker exec <nom> ps -ef`, pas la lecture des journaux.

**`Reference issue detected`, à ne pas confondre avec un échec.** Au téléchargement des mods, le
serveur écrit `Reference issue detected (circular reference or wrong order)`, une fois par mod que
plusieurs autres déclarent en dépendance. **C'est un avertissement du résolveur, pas une erreur** :
mesuré le 8 août 2026, les quatorze mods rapportent `k_EResultOK` juste après. Ce qui signalerait un
vrai problème est `Unable to download mods. Result = Fail`, qui bloque tout le démarrage et pour
lequel le remède connu est double : les DLL Steam à jour, que l'entrypoint fait déjà, et Torch, que
nous utilisons. Chercher cette ligne-là, pas la première.

Voir aussi `AutodetectDependencies`, à `true` : c'est lui qui résout les dépendances déclarées et
produit ces boucles. Le passer à `false` rendrait le contrôle total à `modpack.txt`, au prix de
devoir y déclarer chaque dépendance à la main.

## Quatre impasses sur l'arrêt propre, à ne pas rejouer

Faire sauvegarder le serveur quand Docker l'arrête a demandé cinq tentatives. Les quatre premières
échouent, chacune pour une raison différente, et toutes sont mesurées :

| Tentative | Pourquoi ça échoue |
|---|---|
| `wine taskkill` sans `/F` | annonce le message de fermeture envoyé, ne fait rien : `-nogui` n'a aucune fenêtre |
| idem, avec l'interface WPF rendue à Torch | l'interface démarre bien sous Wine, mais ne réagit pas davantage |
| Remote API HTTP | journalise « Remote API started on port 8080 », le port écoute, aucune requête n'aboutit : elle repose sur `HttpListener`, donc `http.sys`, que Wine n'implémente pas |
| `save` sur l'entrée standard | en `-nogui`, Torch n'installe aucune boucle de commandes, sa console ne fait qu'afficher (voir `Initializer.cs`) |

Ce qui marche : **`SIGINT` au processus du jeu**, que Wine convertit en `CTRL_C_EVENT`. Le mérite ne
revient pas à Torch, dont le code ne contient aucun gestionnaire de `Ctrl+C`.

**Piège de méthode rencontré en route** : une première mesure semblait donner `taskkill` gagnant.
L'autosave était alors à une minute pour un test sans rapport, et la sauvegarde observée était celle
du minuteur. Devant un mécanisme de sauvegarde, toujours vérifier ce que fait l'autosave avant de
s'attribuer le résultat.

## Les sauvegardes ne s'accumulent pas, c'est vérifié

Un serveur Space Engineers mal réglé se remplit tout seul de sauvegardes et sature son disque en
quelques semaines. Ce n'est pas le cas ici, et la vérification a été faite plutôt que supposée :
autosave abaissé à une minute, `PauseGameWhenEmpty` désactivé, puis comptage. **Sept sauvegardes ont
produit cinq dossiers de backup**, la valeur de `MaxBackupSaves`. La rotation fait son travail.

Deux choses à savoir sur ce mécanisme :

- **L'autosave écrase la sauvegarde courante**, il n'empile rien. Ce qui s'accumule, c'est un dossier
  horodaté dans `Backup/` par sauvegarde, et c'est ce dossier que `MaxBackupSaves` borne.
- **`PauseGameWhenEmpty` supprime presque toutes les sauvegardes** quand personne ne joue : le monde
  est gelé, donc il n'y a rien à écrire. Deux sauvegardes en deux heures et demie à vide, contre une
  par minute sous charge de test.

Compter environ 300 Ko par backup sur un monde vide. Un monde peuplé pèsera bien plus, mais cinq
backups d'un gros monde restent sans commune mesure avec les 1,9 To disponibles.

Restent deux choses que le jeu ne nettoie pas seul, sans gravité aux volumes observés : les journaux
de `Logs/` (un fichier par jour, ni compressé ni supprimé) et les minidumps, malgré
`DeleteMiniDumps` à `true` dans `Torch.cfg`.

## Limites connues

- **L'arrêt sauvegarde, mais pas à tous les coups.** L'entrypoint envoie `SIGINT` au processus du
  jeu, que Wine traduit en `CTRL_C_EVENT`. Observé : tantôt la séquence complète avec `world saved`
  et une sortie propre en 61 s, tantôt aucune sauvegarde et les 210 s de `stop_grace_period`
  épuisées. Le déterminant est probablement l'état « sale » du monde, mais **il n'a pas été isolé**,
  donc rien ne doit être promis ici. L'autosave à 3 minutes reste le filet, et c'est lui qui borne la
  perte réelle. À reprendre avec de vrais joueurs, où le monde change en permanence.
- **La tenue en charge n'est pas mesurée.** La simulation de Space Engineers est essentiellement
  mono-thread et l'hôte est un EPYC virtualisé à 2,0 GHz. Ça devrait suffire à quelques joueurs,
  mais tant que rien n'a été mesuré, ce n'est qu'une hypothèse.
- **Le pré-téléchargement des mods par SteamCMD n'est pas tranché.** Le serveur les télécharge
  lui-même, DLL corrigées à l'appui. Si cela s'avère insuffisant, le repli est de les pré-télécharger
  avec `workshop_download_item 244850`, dont le fonctionnement en login anonyme reste à vérifier.
