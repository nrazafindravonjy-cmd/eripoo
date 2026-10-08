# Eripoo — Offline-first et synchronisation

Objectif : tout le parcours, le projet, les missions, la progression, les
observations, les interviews, les hypothèses, les expériences, les documents
et les réglages fonctionnent sans réseau ; la synchronisation est
automatique, idempotente et **ne perd jamais de données silencieusement**.

Statut : conception v2 ; **socle implémenté en Phase 2** (moteur, RPC,
conflits, migration invité → compte), testé contre un faux serveur et en
SQL sur PostgreSQL local. **Jamais exécuté contre un vrai projet
Supabase.** Couverture des scénarios : §13.1.

## 0. Ce qui a changé depuis la v1 (simplification)

Le besoin réel d'Eripoo : **un utilisateur, un à trois appareils, rarement
utilisés en même temps, quelques milliers d'enregistrements.** Les
modifications concurrentes du même élément sur deux appareils seront rares.
La v1 était dimensionnée pour plus. Supprimé :

| v1 | v2 | Pourquoi |
|---|---|---|
| Horloges logiques hybrides par champ, fusion automatique à 3 voies par champ | **aucune horloge** ; conflit au niveau de l'enregistrement, l'autre version est conservée comme copie | la fusion par champ apporte peu pour des conflits rares, et coûte en complexité et en bugs possibles |
| Table d'outbox + table serveur d'opérations appliquées | **un indicateur « modifié » par enregistrement** (`change_id`) dans une table `sync_meta` ; idempotence via le dernier `change_id` stocké sur l'enregistrement serveur | moins de tables, même garantie |
| Séquence globale + verrou consultatif | **compteur par utilisateur** (`sync_heads`) verrouillé par ligne | plus simple à comprendre et à tester |
| Chiffrement des médias par segments | chiffrement en une opération, taille plafonnée | pas de format de flux maison |
| Transfert de clé relayé par le serveur | double QR hors ligne | le serveur ne voit rien |

Compromis assumé : si deux appareils modifient **des champs différents** du
même élément hors ligne, il n'y a pas de fusion automatique ; une version est
retenue et l'autre est conservée en copie, consultable.

---

## 1. Principes

1. **Drift est la source de vérité de l'interface.** Le réseau ne bloque
   jamais une action.
2. **Chaque écriture marque l'élément « à envoyer » dans la même
   transaction** (repositories uniquement).
3. **Le serveur ne lit pas et ne fusionne pas** (contenu chiffré) : il
   compare des versions et ordonne les écritures. La résolution est faite par
   l'appareil, de manière déterministe.
4. **Idempotence** : renvoyer la même modification produit le même état.
5. **Aucune perte silencieuse** : toute version écartée devient une copie de
   conflit, elle-même synchronisée.

## 2. Identifiants et versions

| Nom | Généré par | Forme | Rôle |
|---|---|---|---|
| `id` | appareil, à la création | UUID v7 | identité de l'élément, identique partout |
| `owner_id` | Supabase Auth | UUID | propriétaire (RLS) |
| `device_id` | appareil, au premier lancement | UUID v4 | appareil d'origine, révocation |
| `change_id` | appareil, **à chaque écriture locale** | UUID v4 | identifie une modification ; clé d'idempotence |
| `version` | serveur | entier, **compteur par utilisateur**, strictement croissant et sans trou | ordre des écritures ; curseur de lecture |
| `base_version` | appareil | entier ou null | dernière `version` serveur connue de l'élément ; null = jamais envoyé |

Aucune horloge d'appareil n'intervient dans l'ordre ou la résolution
(les téléphones ont souvent une date fausse). `updated_at` ne sert qu'à
l'affichage.

## 3. Tables

### 3.1 Locales (Drift, base chiffrée)

Les tables métier ([DATA_MODEL §3](DATA_MODEL.md#3-modèle-local-drift--sqlite))
ne portent que `id`, `created_at`, `updated_at`, `deleted_at`. L'état de
sync est centralisé :

```
sync_meta (                         -- une ligne par élément synchronisable
  entity_type     TEXT,             -- 'hypothesis', 'observation', ...
  entity_id       TEXT,             -- = id de l'élément
  base_version    INTEGER NULL,
  change_id       TEXT NULL,        -- non null = modification à envoyer
  pushed_change_id TEXT NULL,       -- dernier change_id envoyé (détection d'écho)
  last_error      TEXT NULL,        -- code d'erreur, jamais de contenu
  attempts        INTEGER DEFAULT 0,
  next_attempt_at INTEGER NULL,
  PRIMARY KEY (entity_type, entity_id)
)  -- index partiel sur change_id IS NOT NULL

sync_state (key TEXT PRIMARY KEY, value TEXT)
  -- 'cursor' (dernière version reçue), 'device_id', 'last_push_at',
  -- 'last_pull_at', 'device_revoked'

conflict_copies (                   -- entité synchronisée, append-only
  id, entity_type, entity_id, payload_json, from_device_id,
  created_at, resolved_at NULL, resolution NULL)

media (..., upload_status, upload_attempts, remote_path)   -- fichiers
```

### 3.2 Serveur (Postgres)

```sql
sync_heads (
  owner_id     uuid primary key references auth.users on delete cascade,
  last_version bigint not null default 0
);

sync_records (
  owner_id     uuid not null references auth.users on delete cascade,
  id           uuid not null,
  version      bigint not null,      -- valeur de sync_heads au moment de l'écriture
  change_id    uuid not null,        -- dernière modification appliquée
  device_id    uuid not null,
  deleted      boolean not null default false,
  umk_version  smallint not null,
  payload      bytea,                -- enveloppe chiffrée ; null après purge
  payload_size int not null,         -- taille remplie (arrondie)
  updated_at   timestamptz not null default now(),
  primary key (owner_id, id)
);
create index on sync_records (owner_id, version);

devices (
  owner_id uuid references auth.users on delete cascade,
  id uuid, label text, status text check (status in ('pending','active','revoked')),
  created_at timestamptz, last_seen_at timestamptz,
  app_version text, revoked_at timestamptz,
  primary key (owner_id, id)
);
```

RLS : lecture de ses propres lignes uniquement ; **aucune écriture directe**
sur `sync_records` / `sync_heads` : uniquement par les deux RPC ci-dessous.
Clé primaire `(owner_id, id)` : les données de deux comptes ne peuvent
jamais se toucher.

## 4. Opérations

Une seule opération d'écriture : **`put`** (création, modification,
suppression logique, restauration et purge sont toutes des `put` d'une
enveloppe).

```
sync_push(device_id, puts[])   -- ≤ 50 éléments ou ≤ 256 Ko
  put = { id, change_id, base_version | null, deleted, umk_version,
          payload | null, payload_size }
  → results[] = { id, status: applied | conflict | rejected,
                  version, current? }

sync_pull(device_id, since_version, limit = 200)
  → { records[], head_version }
```

### 4.1 `sync_push` côté serveur (une transaction)

1. Vérifier que `device_id` appartient à `auth.uid()` et n'est pas révoqué ;
   sinon `device_revoked` pour tout le lot.
2. `select … from sync_heads where owner_id = auth.uid() for update`
   (création à la volée) : **verrou qui sérialise les écritures d'un même
   utilisateur**.
3. Pour chaque `put`, dans l'ordre reçu :
   - ligne existante avec `change_id` identique ⇒ `applied` avec sa
     `version` actuelle (**rejeu idempotent**) ;
   - ligne existante et `version ≠ base_version`, ou ligne existante alors
     que `base_version` est null ⇒ `conflict` + `current` (enveloppe
     chiffrée actuelle) ;
   - sinon : `last_version += 1`, upsert avec `version = last_version` ⇒
     `applied`.
4. Validation : taille maximale, `umk_version` connue, quotas, débit.

Pourquoi le compteur par utilisateur : chaque écriture d'un utilisateur
prend la valeur suivante **pendant qu'elle tient le verrou**, et le verrou
n'est relâché qu'à la validation de la transaction. Un lecteur ne peut donc
jamais voir la version N+1 sans la version N : le curseur `since_version`
ne saute aucune écriture.

### 4.2 Côté client, après la réponse

- `applied` : **seulement si** `sync_meta.change_id` est toujours égal au
  `change_id` envoyé (l'utilisateur a pu modifier l'élément pendant
  l'envoi), mettre `change_id = null` ; dans tous les cas
  `base_version = version`.
- `conflict` : résolution (§6).
- `rejected` : `last_error` renseigné, élément conservé localement, visible
  dans « Problèmes de synchronisation ».

### 4.3 `sync_pull` côté client

Pour chaque page, **dans une seule transaction Drift** : déchiffrer,
appliquer chaque enregistrement (§6), puis avancer `cursor`. Une
interruption ne fait jamais avancer le curseur sans les données.

Pour chaque enregistrement reçu :

- `version ≤ base_version` locale ⇒ ignorer (déjà connu) ;
- l'élément local n'a pas de modification en attente ⇒ remplacer ;
- l'élément local a une modification en attente :
  - si `record.change_id == pushed_change_id` ⇒ c'est l'écho de notre propre
    envoi (cas d'une coupure après application serveur) ⇒ simple mise à
    jour de `base_version` ;
  - sinon ⇒ conflit (§6).

## 5. Ordre des opérations

- **Cycle** (implémenté, `lib/sync/engine/sync_engine.dart`) : (1) **pull**
  jusqu'à `head_version`, (2) push des éléments modifiés, (3) si le push a
  rencontré des conflits, nouveau pull puis push de leur résolution, (4)
  envoi des médias (Phase 4), (5) mise à jour de l'indicateur d'état. Un
  seul cycle à la fois. *Changement par rapport à la v2 (push d'abord)* :
  tirer d'abord permet de reconnaître l'écho d'un envoi dont la réponse a
  été perdue **avant** qu'un nouvel envoi n'écrase `pushed_change_id` ;
  sinon une modification faite entre-temps aurait produit une copie de
  conflit inutile (défaut trouvé en écrivant les tests).
- **Enregistrement illisible** (autre clé, données altérées) ou **format
  plus récent** que l'app : non appliqué, laissé intact sur le serveur,
  signalé dans les journaux techniques (sans contenu). Limite actuelle : le
  curseur avance au-delà ; ces enregistrements seront relus par une
  resynchronisation complète après mise à jour de l'app ou récupération de
  la clé (à implémenter en Phase 5).
- **Ordre d'envoi** : par rang de type (projet → sections → hypothèses →
  expériences → résultats → preuves → décisions → …) puis date de
  modification, pour que les parents précèdent généralement les enfants.
- **Ordre d'application** : strictement par `version` croissante.
- **Références entre éléments** : pas de contrainte de clé étrangère SQL
  entre tables synchronisées (un enfant peut arriver avant son parent depuis
  un autre appareil). Le domaine tolère un orphelin temporaire (masqué
  jusqu'à l'arrivée du parent) ; une vérification d'orphelins persistants
  tourne après chaque sync complète.

## 6. Détection et résolution des conflits

**Détection** : uniquement par versions — `base_version` ≠ `version`
serveur au push, ou modification locale en attente face à une version reçue
au pull. Jamais par date.

**Résolution**, selon la famille de l'élément (déclarée par type) :

| Famille | Types | Règle |
|---|---|---|
| **Éditables** | projet, sections, hypothèses en brouillon, expériences avant démarrage, observations, interviews, concurrents, montants (`finance_item`), prix et ventes prévues (`finance_plan`), profil, réponses | **la version de l'appareil qui résout est conservée** et repart avec `base_version = version distante` ; **la version distante est enregistrée dans `conflict_copies`** (synchronisée) |
| **Append-only** | historique du projet, décisions, preuves, résultats, conclusions, badges, consentements, copies de conflit | jamais modifiés ⇒ pas de conflit possible (identifiants uniques) |
| **Progression** | progression d'étape, missions | fusion par état le plus avancé (`locked < available < in_progress < completed`), dates de début = min, de fin = max ; si un texte libre (ex. réflexion de mission) diffère, la version distante va aussi en copie de conflit |
| **Déblocage** (Phase 6) | outils débloqués | jamais reverrouillé : date de déblocage = la plus ancienne, « vu » = le plus ancien des deux, suppression ignorée ; pas de copie de conflit (aucun texte) |
| **Verrouillés** | critère de réussite d'une expérience démarrée, hypothèse testée | immuables par règle de domaine ; toute divergence ⇒ copie de conflit, jamais d'écrasement |

Pourquoi « l'appareil qui résout gagne » : c'est déterministe, sans
horloge, et l'utilisateur voit toujours sa dernière saisie sur l'appareil
qu'il tient ; l'autre version n'est jamais perdue. Les deux appareils
convergent : le second reçoit la version retenue **et** la copie.

**Interface** : badge discret « une autre version existe » sur l'élément ;
écran « Versions » avec « Garder celle-ci » / « Copier ce passage ».
Résoudre marque la copie `resolved_at` (elle reste consultable dans
l'historique).

## 7. Suppression, corbeille, restauration

- **Supprimer** = `put` avec `deleted_at` renseigné et **contenu
  conservé** dans l'enveloppe : l'élément passe dans la corbeille sur tous
  les appareils.
- **Restaurer** (corbeille, 30 jours) = `put` avec `deleted_at = null`.
- **Purger** (après 30 jours, ou « Vider la corbeille ») = `put` avec
  `deleted = true` et `payload = null` ; la ligne serveur (quelques octets)
  reste comme pierre tombale pour les appareils hors ligne.
- **Suppression d'un projet** : chaque élément du projet reçoit sa propre
  suppression logique (même corbeille, restauration groupée).
- **Suppression concurrente d'une modification** : la suppression
  l'emporte, mais **le contenu conservé dans la corbeille est la version
  modifiée** ; l'utilisateur est informé (« supprimé sur un autre appareil —
  tes dernières modifications sont dans la corbeille »).
- **Restauration concurrente d'une purge** : la version locale complète
  gagne (règle des éditables) ⇒ l'élément revit, rien n'est perdu.
- **Aucune suppression physique locale** d'un élément tant que sa purge n'a
  pas été confirmée par le serveur.

## 8. Reprise après interruption

| Interruption | Pourquoi c'est sûr |
|---|---|
| Coupure réseau pendant un push, réponse non reçue | `change_id` toujours non null ⇒ renvoi ; le serveur reconnaît le `change_id` ⇒ `applied` sans doublon |
| Coupure après application serveur, puis nouvelle modification locale avant renvoi | le pull renvoie notre propre version ; `pushed_change_id` la reconnaît comme écho ⇒ pas de faux conflit |
| Coupure pendant un pull | page appliquée et curseur avancés dans la même transaction, ou rien |
| Fermeture de l'app / batterie vide pendant la sync | aucun état « en cours » à réparer : au redémarrage, les éléments marqués sont renvoyés |
| Crash pendant une résolution de conflit | transaction Drift annulée ⇒ la résolution est refaite au cycle suivant |
| Coupure pendant l'envoi d'un média | le fichier est renvoyé en entier (≤ 10 Mo) au même chemin, en écrasement |

**Réessais** (corrigé en Phase 2) : une coupure réseau concerne toute la
requête, jamais un élément : le lot reste « à envoyer » et repart au cycle
suivant. Le rythme des réessais (backoff exponentiel avec gigue : 5 s,
15 s, 1 min, 5 min, 15 min, plafond 1 h) appartient au **déclencheur** de
synchronisation (pas encore implémenté), pas aux éléments. Seuls les
éléments **refusés** par le serveur reçoivent un délai propre (1 h).
Un cycle n'est « complet » que s'il est allé au bout **et** qu'il ne reste
rien à envoyer (`SyncReport.pendingLeft == 0`) : seul état où l'app peut
afficher « sauvegardé ». Défaut trouvé par le test des 5 000 éléments en
CI : avec un délai par élément, un lot coupé était ignoré par les cycles
suivants, qui se déclaraient complets avec 50 modifications en attente.

| Classe d'erreur | Traitement |
|---|---|
| Transitoire (pas de réseau, timeout, 5xx, 429) | réessai |
| Authentification (401) | rafraîchir la session ; sinon sync suspendue et invitation à se reconnecter, données locales intactes |
| Appareil révoqué | effacement local des données et des clés (SECURITY §6.8) |
| Permanente (400, taille, quota) | élément conservé localement, signalé, rapport d'erreur sans contenu |
| `schema_version` inconnu (app trop ancienne) | enveloppe conservée telle quelle, non écrasée ; invitation à mettre à jour |

**Déclencheurs** : démarrage, retour au premier plan, changement de
connectivité (signal seulement, confirmé par une requête légère), 5 s après
une écriture, toutes les 5 min au premier plan, WorkManager en arrière-plan
(réseau disponible).

### 8.1 Rotation de la clé de données (Phase 10)

Voir SECURITY §4.10. Côté synchronisation : `sync_pull` renvoie la
version de clé du compte ; si elle dépasse celle du téléphone, le cycle
s'arrête **avant** d'appliquer quoi que ce soit (`DataKeyOutdated`) et
l'état devient « nouvelle clé nécessaire » (rien n'est effacé, rien n'est
envoyé). Sur le téléphone qui a fait la rotation, chaque cycle complet
enchaîne un passage de rechiffrement (curseur propre,
`sync.rekey_cursor`) : les enregistrements encore sous l'ancienne version
sont scellés à nouveau et renvoyés sur leur version de base ; la base
locale suit (même contenu, pas de conflit). Pendant la transition, un
enregistrement est ouvert avec la clé courante, sinon avec la précédente.

## 9. Médias

Stockés localement chiffrés dès la capture (fonctionne hors ligne). L'entité
`media` se synchronise comme les autres ; le fichier part ensuite vers
`user-media/{uid}/{media_id}`, par défaut **en Wi-Fi uniquement**
(réglable). Sur un autre appareil, il est téléchargé à l'ouverture. Taille
plafonnée (10 Mo proposé) et quota par utilisateur.

## 10. Invité, compte et appareils

- **Invité → compte** : tout est déjà écrit localement et marqué « à
  envoyer » ; à l'inscription, l'UMK existante est enveloppée par la RK
  (SECURITY §4.8 et §5), `sync_heads` est créé, puis push normal. **Rien n'est
  supprimé localement.**
- **Connexion à un compte qui contient déjà un projet** ⚠️ : les deux jeux de
  données sont conservés côte à côte (deux projets) ; l'utilisateur choisit
  le projet actif. Jamais de fusion automatique.
- **Nouvel appareil** : déverrouillage (double QR, SECURITY §6, ou code de récupération, SECURITY §5), puis pull complet ; rien
  n'est déchiffré avant. **État Phase 2** : seul le code de récupération
  est implémenté et testé ; le double QR arrive en Phase 5 et deviendra le
  chemin normal, le code restant le secours (SECURITY §6.0).
- **Appareil révoqué** : implémenté (SECURITY §6.8) — effacement local
  complet, session refusée partout, testé de bout en bout.
- **Déconnexion** : si des éléments ne sont pas envoyés, avertissement
  explicite ; ensuite effacement des données locales (téléphones partagés).

## 11. Contenu pédagogique

Séparé de la sync utilisateur : manifeste distant, téléchargement des packs
modifiés, vérification de signature (SECURITY §15), installation atomique,
ancienne version conservée en cas d'échec.

## 12. Pourquoi une synchronisation interne plutôt qu'une solution spécialisée

Solutions examinées : PowerSync, ElectricSQL et équivalents (réplication
Postgres ↔ SQLite).

| Critère | Solution spécialisée | Interne (ce document) |
|---|---|---|
| Ce qu'elle apporte | réplication de **tables relationnelles lisibles par le serveur**, règles de partage côté serveur, sous-ensembles par utilisateur | stockage d'enveloppes opaques |
| Compatibilité avec le chiffrement de bout en bout | le serveur ne peut plus lire les colonnes : il ne resterait qu'**une** table de blobs à répliquer ; l'essentiel de la valeur disparaît | conçue pour |
| Résolution de conflits | en général côté serveur ou en « dernier écrit gagne » sur colonnes en clair — impossible ici | côté client, adaptée aux familles d'Eripoo |
| Infrastructure | un service supplémentaire (hébergé ou auto-hébergé) qui voit passer les données et métadonnées, avec coût et exploitation | 2 RPC SQL + 3 tables dans le Postgres existant |
| Dépendance | format et cycle de vie d'un tiers | protocole portable vers n'importe quel Postgres |
| Volume réel d'Eripoo | conçues pour des données partagées et volumineuses | 1 utilisateur, 1–3 appareils, quelques milliers d'éléments |
| Risque principal | intégration, coûts, pérennité | **les bugs sont les nôtres** → protocole minimal + tests de faute (§13) |

Conclusion : avec le chiffrement de bout en bout, une solution spécialisée
ajouterait un service sans apporter son atout principal. **Si le
chiffrement de bout en bout était abandonné (option C), PowerSync
redeviendrait le premier choix à réévaluer.**

## 13. Plan de tests

Faux serveur en mémoire implémentant la même interface que le client RPC
(doublure de test documentée), avec injection de fautes ; mêmes scénarios
contre Supabase local en CI ; fonctions de résolution testées unitairement.

| # | Scénario | Attendu |
|---|---|---|
| 1 | Hors ligne plusieurs jours, 500 écritures | tout fonctionne ; tout est marqué « à envoyer » |
| 2 | Retour en ligne | tout est envoyé, curseur à jour, état « sauvegardé » |
| 3 | Conflit sur un éditable (2 appareils) | version locale gardée, version distante en copie, convergence des 2 appareils |
| 4 | Suppression locale vs modification distante | corbeille contenant la version modifiée, aucune perte |
| 5 | Coupure pendant un push (avant / après application serveur) | aucun doublon, aucun faux conflit |
| 6 | Coupure pendant un pull | curseur jamais en avance sur les données |
| 7 | Fermeture de l'app pendant la sync | reprise propre |
| 8 | Lot rejoué deux fois | état identique |
| 9 | Date de l'appareil fausse (± 2 ans) | aucun effet (pas d'horloge utilisée) |
| 10 | Invité → compte avec 3 mois de données | tout envoyé, rien supprimé |
| 11 | Enfant reçu avant son parent | orphelin masqué puis rattaché |
| 12 | `schema_version` futur reçu | enveloppe conservée, non écrasée |
| 13 | Appareil révoqué qui se reconnecte | refus, effacement local |
| 14 | 5 000 éléments sur appareil 1 Go | sync sans gel de l'interface (isolat) |

### 13.1 Couverture en Phase 2 (`test/sync/sync_engine_test.dart`, `test/features/account/`)

| # | État |
|---|---|
| 1–2 | ✅ testé (faux serveur) |
| 3 | ✅ testé (la version de l'appareil qui résout est gardée, l'autre devient une copie de conflit synchronisée) |
| 4 | ✅ testé |
| 5 | ✅ testé, y compris réponse perdue rejouée telle quelle |
| 6 | ✅ testé |
| 7 | ✅ testé (moteur recréé à chaque point d'arrêt) |
| 8 | ✅ testé (idempotence par `change_id`) |
| 9 | ✅ testé |
| 10 | ✅ testé (invité → compte, puis 2ᵉ téléphone avec le code) — sur petit volume, pas 3 mois de données |
| 11 | ✅ testé : section reçue avant son projet, conservée sans être affichée, rattachée à l'arrivée du projet |
| 12 | ✅ testé : enregistrement laissé intact ; resynchronisation après mise à jour faite en Phase 5 (§13.4) |
| 13 | ✅ testé (validation Phase 2) : synchronisation refusée, **effacement local réel** (base, WAL, clés, identifiant, session, verrou), redémarrage vide avec nouvel identifiant, ancienne session refusée partout et incapable de se rafraîchir (vérifié sur Supabase local), retour au compte seulement avec le code — `test/sync/revocation_test.dart`, contrat RPC, SQL `15_sessions_test.sql`. **Pas fait** : écran « Mes appareils », message à l'utilisateur après effacement, déclencheur automatique |
| 14 | ✅ testé avec **5 000 éléments** (`test/sync/volume_test.dart`, base chiffrée réelle sur fichier, coupure à l'envoi, réponse perdue, coupure à la réception) ; mesures §13.2. **Non vérifié** : 5 000 éléments sur téléphone 1 Go et absence de gel d'interface sur appareil (le moteur tourne sur l'isolat principal par petites étapes ; la base est sur un isolat séparé) |

Côté serveur : **60 assertions SQL** (appareils, sessions, sync,
confidentialité, récupération) passent sur PostgreSQL 16 avec `auth`
simulé **et sur la pile Supabase locale** (CI). Correction : les rapports
précédents annonçaient 46 assertions, c'était une erreur de comptage
(il y en avait 52 avant l'ajout des 8 assertions de sessions).

### 13.4 Couverture en Phase 5

| # | État |
|---|---|
| 1–3, 5–9, 11, 13 | inchangés (✅ testés), voir §13.1 ; 13 : écran « Mes appareils » et retrait ajoutés (widget) |
| 4 | ✅ et **corbeille complète** (§7) : supprimer, remettre, supprimer pour de bon (pierre tombale sans contenu), purge après 30 jours, restauration concurrente gagnante — `test/features/trash/` |
| 10 | ✅ + second téléphone par **double QR** (SECURITY §6.10) ou par le code, par l'interface — `test/features/account/` |
| 12 | ✅ **complet** : après mise à jour, retrait et application des enregistrements écartés (`sync.replay_from`) — `test/sync/sync_engine_test.dart` « 12b » |
| 14 | ✅ inchangé ; fichiers ≥ 1 Mo désormais chiffrés hors du fil de l'interface (gel mesuré sous 0,1 s sur émulateur, DEVICE_TESTS §2quater) |

Ajouts de la Phase 5 :

- **Déclencheurs et réessais** (§8) : `lib/sync/sync_scheduler.dart`,
  testés en temps simulé (`test/sync/sync_scheduler_test.dart`) ; défaut
  corrigé : le cycle de 5 min contournait l'attente après échec.
  Arrière-plan : WorkManager (`lib/app/sync/background_sync.dart`),
  compilé mais **jamais exécuté sur appareil** (NON VÉRIFIÉ). Un cycle en
  arrière-plan et un au premier plan peuvent se croiser : sans danger
  (idempotence par `change_id`, page et curseur dans une transaction).
- **Médias** (§9) : envoi après les métadonnées, en Wi-Fi seulement sauf
  réglage, rechiffrés pour le compte ; réception à la demande avec
  vérification de l'empreinte ; file locale `media_uploads` (schéma v4) ;
  envoi sans écrasement (un même identifiant n'est jamais réécrit : la
  ligne « renvoyé en écrasement » de §8 ne s'applique plus, le renvoi
  d'un fichier déjà présent est simplement accepté).
- **Valeurs effacées à distance** : défaut corrigé — un `null` reçu d'un
  autre appareil n'était pas appliqué (restauration de la corbeille,
  champ vidé).
- **Copies de conflit** : écran « Versions à vérifier » (§6).

### 13.2 Mesures — 5 000 éléments (machine de CI GitHub, pas un téléphone)

| Mesure | Valeur |
|---|---|
| Écriture locale (une transaction par élément, base chiffrée) | 12,7 s (2,54 ms/élément) ; 15,9 s sur la machine de développement |
| Taille de la base après écriture (après *checkpoint*) | 1 528 Kio ; 1 356 Kio chez le receveur |
| Envoi, avec 1 coupure avant le serveur et 1 réponse perdue | 14,2 s, 3 cycles, **100 lots de 50, aucun lot renvoyé** |
| Réception sur un 2ᵉ appareil, coupée après 10 pages | 6,3 s au total, reprise sans perte |
| Doublons / pertes | aucun : 5 000 enregistrements, version de tête = 5 000, contenus identiques |
| Mémoire du processus de test | +49 Mio pendant le test ; pic 256 Mio (processus de test entier) |

Le chiffrement des 5 000 enveloppes ne prend que ~1,4 s : l'essentiel du
temps est l'aller-retour vers la base (isolat séparé).

### 13.3 Trois serveurs de test et leurs différences

| Aspect | PostgreSQL 16 + `auth` simulé (`run_local.sh --stub`) | Faux serveur Dart (`test/helpers/fake_sync_server.dart`) | Supabase local réel (CI) |
|---|---|---|---|
| Ce qui est testé | les fonctions SQL et la RLS, directement | le client (moteur, conflits, fautes réseau) | tout : Auth (GoTrue), PostgREST, rôles, SQL, et le client réel par HTTP |
| Authentification | tables `auth.users` et `auth.sessions` minimales ; jetons simulés en posant les *claims* à la main (`sub`, `amr`, `session_id`) | chaînes `owner` / `session` sans jeton | vrais comptes (inscription e-mail + mot de passe), vrais JWT |
| Transport | SQL | appels Dart sur objets en mémoire, **sans JSON** | HTTP + JSON ; octets en base64 |
| Base64 | — | — | **retours à la ligne tous les 76 caractères** (PostgreSQL) — bug client trouvé ainsi et corrigé |
| Sans session | `not_authenticated` | `NotAuthenticated` | refus PostgREST `42501` (le rôle anonyme n'a pas le droit d'exécuter) → `NotAuthenticated` |
| Entrée invalide | erreurs SQL | `RemoteRejected` | codes `22023` / `23514` → `RemoteRejected` |
| Réauthentification récente (`amr`) | testée, y compris « trop ancienne » | non modélisée (toujours acceptée) | format réel vérifié juste après connexion ; le cas « plus de 10 min » n'est testé qu'en SQL simulé |
| Limite de récupération de l'enveloppe | réelle (5/h, 20/jour, par l'heure du serveur) | compteur simple sans horloge (5) | réelle |
| Révocation d'une session | ligne `auth.sessions` supprimée | ensemble de sessions révoquées | session réellement supprimée : son rafraîchissement **échoue** (vérifié) |
| Concurrence, verrous | réels | aucun (mono-fil) | réels |
| Pas couvert | Auth, PostgREST, JSON | SQL réel, JSON | Google, téléphone, e-mails réels, région, latence réseau Madagascar |

Règle : un comportement du faux serveur n'est considéré comme fidèle que
s'il est couvert par la suite de contrat (`test/contract/`) passée sur
Supabase. Le projet Supabase **de développement en ligne** n'est pas encore
créé (compte du porteur nécessaire) : la même suite y sera lancée avec
`ERIPOO_TEST_SUPABASE_ALLOW_REMOTE=dev`.

