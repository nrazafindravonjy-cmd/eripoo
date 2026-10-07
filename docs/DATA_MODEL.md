# Eripoo — Modèle de données

Deux modèles distincts, reliés par le protocole de sync
([OFFLINE_SYNC.md](OFFLINE_SYNC.md)) :

- **Local (Drift/SQLite)** : modèle relationnel complet et typé, en clair
  dans une base chiffrée au repos. C'est là que vit la logique.
- **Serveur (Supabase/Postgres)** : pour les données privées, **un stockage
  d'enveloppes chiffrées** sans structure métier lisible ; pour le contenu
  public, l'authentification, les consentements et les analytics, des tables
  classiques.

⚠️ Cette séparation découle du choix du chiffrement de bout en bout
([SECURITY §4](SECURITY.md#4-schéma-cryptographique-de-bout-en-bout)). Si ce choix était
refusé, le modèle serveur deviendrait un miroir typé du modèle local (avec
RLS par table) — changement lourd une fois des données en production.

---

## 0. État d'implémentation (Phases 2 à 4)

Implémenté dans `lib/data/local/tables.dart` (schéma **v3**, **non figé**
avant les premières données réelles) : `user_profiles`, `facts`,
`projects`, `project_sections`, `project_revisions`,
`step_progress_entries` (+ `deferred_until` en v2), `answers` (v2),
`mission_instances` (v2), `conflict_copies`, `sync_meta_entries`,
`local_key_values`. Migration v1 → v2 testée sur une base chiffrée
(`test/data/phase3_data_test.dart`). Les autres tables du §3 (hypothèses,
expériences, observations, interviews, médias, finances, badges…) arrivent
avec leurs fonctionnalités (Phases 4 à 7).

Ajouté en v3 (Phase 4) : `hypotheses`, `experiments`,
`experiment_hypotheses` (identifiant déterministe par paire), `results`
(`metric_yes` / `metric_total` au lieu de `metrics_json`), `evidences`
(`body`, `media_id`, `number_value`, `amount_mga`), `conclusions` (avec
`outcome`), `decisions` (ajout seul, avec `new_hypothesis_id`),
`observations` (photos rattachées comme preuves), `interviews`
(pseudonyme et notes écrites, **ni audio ni transcription** : avis
juridique P6), `media_items` (`content_hash` BLAKE2b-256 ; pas de chemin
stocké, il se déduit de l'identifiant). Migration v2 → v3 testée sur une
base chiffrée.

Écarts avec le §3.2 (Phase 3) : `answers` porte aussi `quest_id` ; types de
réponse implémentés `text`, `choice`, `multi_choice`, `number`, `money`,
`unknown` (`audio` en Phase 4/9) ; `mission_instances` porte
`submitted_at` et `abandoned_at`, pas encore `due_at` ni `experiment_id`
(Phase 4). Les réglages d'affichage (langue, thème, animations réduites)
sont dans `local_key_values` (local seulement, non synchronisés) en
attendant `local_profile`.

**Identifiants déterministes (UUID v5)** pour les éléments qui existent au
plus une fois par clé : profil (`profile`), fait (`fact:<clé>`), section
(`section:<projet>:<section>`), progression (`step:<étape>`), réponse
(`answer:<étape>/<bloc>`), mission (`mission:<modèle>`). Deux appareils
qui créent la même chose hors ligne produisent le même identifiant : la
synchronisation traite alors un conflit sur un seul élément au lieu de
créer un doublon. Les autres éléments utilisent des UUID v7.

## 1. Conventions communes

### 1.1 Colonnes de toute entité synchronisable (local)

| Colonne | Type | Rôle |
|---|---|---|
| `id` | TEXT (UUID v7) | Généré sur l'appareil ; identique local/serveur. |
| `project_id` | TEXT nullable | Rattachement projet (index), quand pertinent. |
| `created_at` | INTEGER (ms UTC) | Création locale (affichage). |
| `updated_at` | INTEGER (ms UTC) | Dernière modification locale (affichage uniquement, jamais utilisée pour ordonner). |
| `deleted_at` | INTEGER nullable | Suppression logique (corbeille). |

L'état de synchronisation (version de base, modification en attente,
erreurs) n'est **pas** dans les tables métier : il est centralisé dans
`sync_meta` (§3.7, détail dans [OFFLINE_SYNC §3](OFFLINE_SYNC.md#3-tables)).
Le propriétaire n'est pas stocké par ligne : une base locale appartient à un
seul utilisateur (invité puis compte).

Montants : `INTEGER` en ariary. Dates métier : `INTEGER` ms UTC. Énumérations :
`TEXT` contrôlé par le code (Drift `textEnum`). Texte libre : `TEXT`.

### 1.2 Identifiants de contenu

Les références au contenu (`quest_id`, `step_id`, `mission_template_id`,
`badge_id`, `tool_id`) sont des **chaînes stables** du pack (`q03.s02`), pas
des clés étrangères SQL : le contenu peut changer de version sans casser les
données utilisateur.

## 2. Modèle serveur (PostgreSQL / Supabase)

Schéma `public` sauf mention. Toutes les tables ont RLS **activée** ; absence
de politique = aucun accès.

### 2.1 Comptes et confidentialité

```sql
profiles (
  id                uuid primary key references auth.users on delete cascade,
  created_at        timestamptz not null default now(),
  preferred_locale  text not null check (preferred_locale in ('fr','mg','en')),
  jurisdiction_code text not null default 'MG',
  age_bracket       text check (age_bracket in ('under_min','minor','adult')),
  parental_consent_status text check (parental_consent_status in
                    ('not_required','pending','granted','refused'))
)
-- RLS : select/update où id = auth.uid(). Pas de date de naissance côté
-- serveur (elle reste chiffrée dans le profil synchronisé).

user_keys (                        -- UMK enveloppée par la clé de récupération
  user_id        uuid references auth.users on delete cascade,
  wrap_id        uuid not null,
  umk_version    smallint not null,
  wrap_format    smallint not null,  -- 1 = Argon2id + XChaCha20-Poly1305 (SECURITY §4.8)
  kdf_salt       bytea not null,
  kdf_params     jsonb not null,     -- opslimit, memlimit
  wrapped_umk    bytea not null,     -- 0x01 || nonce || chiffré || tag (SECURITY §4.8)
  created_at     timestamptz not null default now(),
  primary key (user_id, wrap_id)
)
-- RLS : aucune lecture directe ; lecture via RPC get_recovery_wrap (limitée
-- et notifiée, SECURITY §5.6). Création / remplacement via RPC exigeant une
-- réauthentification récente. Aucun vérificateur, hachage ou indice du code
-- de récupération n'est stocké.

security_events (                  -- métadonnées seulement, pour limites et alertes
  owner_id uuid references auth.users on delete cascade,
  kind text check (kind in ('recovery_wrap_fetched','recovery_wrap_replaced',
                            'device_added','device_revoked')),
  at timestamptz not null default now()
)                                  -- rétention 90 jours

consents (
  id            uuid primary key,
  user_id       uuid references auth.users on delete cascade,
  consent_type  text not null,   -- 'privacy_policy','analytics','ai_processing','parental'
  policy_version text not null,
  granted       boolean not null,
  recorded_at   timestamptz not null default now()
)                                 -- append-only ; RLS propriétaire

devices (owner_id, id, label, status ('pending','active','revoked'), created_at,
         last_seen_at, app_version, revoked_at)
                                  -- détail : OFFLINE_SYNC §3.2 ; libellé choisi par
                                  -- l'utilisateur, pas de modèle d'appareil ;
                                  -- 5 appareils actifs max (SECURITY §6.8)

jurisdiction_policies (           -- valeurs à fournir par validation juridique
  code text primary key, min_age int, parental_consent_under int,
  legal_validated boolean not null default false, source text, updated_at timestamptz
)                                 -- lecture publique, écriture admin

deletion_requests (user_id, requested_at, completed_at)   -- trace minimale
```

### 2.2 Données privées synchronisées (chiffrées)

Tables `sync_heads` (compteur de versions par utilisateur) et
`sync_records` (une enveloppe chiffrée par élément, clé primaire
`(owner_id, id)`, `version`, `change_id`, `device_id`, `deleted`,
`umk_version`, `payload`, `payload_size`) : définition SQL complète dans
[OFFLINE_SYNC §3.2](OFFLINE_SYNC.md#32-serveur-postgres).

- Le **type d'entité, la version de schéma, le projet, les dates métier et
  tout le contenu sont dans l'enveloppe chiffrée**. Métadonnées visibles
  par le serveur : id aléatoires, propriétaire, version, `change_id`,
  appareil, suppression, taille arrondie, date serveur.
- RLS : `select` si `owner_id = auth.uid()`. **Aucune** écriture directe :
  uniquement via `sync_push` (`security definer`, vérifie `auth.uid()` et
  l'appareil), lecture via `sync_pull`.

### 2.3 Médias

Bucket Storage **privé** `user-media`, chemin `{owner_id}/{media_id}`,
contenu chiffré côté client. Politiques `storage.objects` :
`(storage.foldername(name))[1] = auth.uid()::text` pour select/insert/delete.
Les métadonnées du média (type, taille, hash) sont dans une entité `media`
chiffrée de `sync_records`.

**Implémenté en Phase 5** (migration `20261008000001_devices_media.sql`) :
chemin limité à `{owner_id}/{uuid}`, fichiers de 10 Mo + 43 octets
d'enveloppe au plus, type `application/octet-stream`, **aucune politique
de mise à jour** (un fichier n'est écrit qu'une fois), et les politiques
refusent aussi la session d'un appareil retiré (fonction
`eripoo_policy.media_allowed`, seul schéma accessible aux politiques).
Les fichiers sont rechiffrés pour l'identifiant du compte avant l'envoi
(SECURITY §4.7). Quota par utilisateur : **non appliqué** (point ouvert).
La colonne `devices.session_id` n'est plus lisible directement ; la liste
des appareils passe par `list_devices`.

### 2.4 Contenu (public en lecture, édition réservée)

```sql
content_releases (
  id uuid primary key, pack_id text, version int, status text
    check (status in ('draft','published','retired')),
  min_app_version text, sha256 text, signature bytea, storage_path text,
  published_at timestamptz, published_by uuid
)
-- lecture : status = 'published' pour tous (anon compris).
-- Les fichiers de packs sont dans le bucket `content` (lecture publique).
```

Quand le back-office existera (après Phase 6), ses tables d'édition
(`content_items`, `content_translations`, `regulatory_sources`, …) seront
ajoutées dans un schéma `authoring`, accessible seulement aux rôles
éditoriaux.

### 2.5 Administration et audit

```sql
staff_roles (user_id uuid, role text check (role in
  ('content_editor','translator','content_publisher','analyst','ops')),
  granted_by uuid, granted_at timestamptz, primary key (user_id, role))

audit_log (id bigserial, actor uuid, action text, target text, at timestamptz)
```

Aucun rôle n'a de politique sur `sync_records`, `user_keys`, `consents`,
`profiles` (hors soi-même) ni sur le bucket `user-media`. Voir
[SECURITY §8](SECURITY.md#8-pourquoi-un-administrateur-ne-peut-pas-déchiffrer).

### 2.6 Analytics

```sql
analytics_events (            -- pas de user_id, pas d'adresse IP
  id bigserial, event text not null, props jsonb not null,
  app_version text, locale text, day date not null, cohort_week date
)                              -- insertion uniquement via Edge Function ; rétention 90 j

analytics_daily (day date, event text, dims jsonb, count int)  -- agrégats conservés
```

## 3. Modèle local (Drift / SQLite)

Toutes les tables ci-dessous ont les colonnes communes du §1.1 sauf mention
« (local seulement) ».

### 3.1 Profil et réglages

| Table | Colonnes principales |
|---|---|
| `local_profile` (local seulement, 1 ligne) | `local_owner_id`, `account_user_id?`, `ui_locale`, `content_fallback_locales`, `onboarding_done_at`, `reduced_motion`, `media_wifi_only` |
| `user_profile` (synchronisé) | `display_name`, `birth_year?`, `age_bracket`, `jurisdiction_code`, `avatar_media_id?` |
| `facts` | `key` (`diag.idea_stage`…), `value_json`, `source` (`diagnostic`, `rule`, `user`) |
| `consents_local` | miroir local des consentements (rejoués vers `consents`) |

### 3.2 Parcours et progression

| Table | Colonnes principales |
|---|---|
| `step_progress` | `quest_id`, `step_id`, `status`, `started_at`, `completed_at`, `deferred_until?`, `content_version` |
| `answers` | `step_id`, `block_id`, `answer_type` (`text`,`choice`,`number`,`money`,`audio`,`unknown`,`skipped`), `value_json`, `audio_media_id?`, `help_used` (niveau d'aide) |
| `mission_instances` | `mission_template_id`, `status`, `accepted_at`, `due_at?`, `completed_at?`, `reflection`, `experiment_id?` |
| `badges_earned` | `badge_id`, `earned_at`, `trigger_entity_id?` |
| `tool_unlocks` | `tool_id`, `unlocked_at` |

### 3.3 Projet

| Table | Colonnes principales |
|---|---|
| `projects` | `title`, `maturity_stage`, `is_active`, `archived_at?` |
| `project_sections` | `project_id`, `section_key`, `fields_json` (schéma par section, défini dans le contenu), `status` (`empty`,`draft`,`reviewed`) |
| `project_revisions` (append-only) | `project_id`, `section_key`, `field_key`, `previous_value`, `new_value`, `source_step_id?`, `reason?` |
| `customer_segments` | `project_id`, `label`, `description`, `situation` |
| `observations` | `title`, `description`, `category`, `observed_at`, `context`, `people_involved`, `supposed_problem`, `photo_media_id?`, `audio_media_id?`, `transcription?`, `transcription_status` |
| `interviews` | `project_id`, `interviewee_alias` (pseudonyme recommandé), `segment_id?`, `held_at`, `quick_notes`, `structured_answers_json`, `audio_media_id?`, `transcription?`, `conclusion`, `audio_consent_recorded` |
| `competitors` | `project_id`, `name`, `offer`, `price_mga?`, `strengths`, `weaknesses` |
| `finance_items` | `project_id`, `kind` (`fixed_cost`,`variable_cost`,`investment`,`revenue`,`funding`), `label`, `amount_mga`, `period` |
| `price_scenarios` | `project_id`, `unit_cost_mga`, `price_mga`, `expected_volume`, `notes` |
| `documents` | `project_id`, `doc_type` (`business_plan`,`pitch`,`formalization_checklist`…), `generated_from_version`, `file_media_id?` |

### 3.4 Hypothèses, expériences, preuves

| Table | Colonnes principales |
|---|---|
| `hypotheses` | `project_id`, `statement`, `category` (`problem`,`customer`,`solution`,`price`,`channel`,`other`), `importance` (1–3), `confidence_before` (1–5), `status`, `parent_hypothesis_id?`, `source_step_id?` |
| `experiments` | `project_id`, `method`, `plan`, `success_criterion`, `criterion_locked_at?`, `sample_target?`, `starts_at?`, `ends_at?`, `status`, `mission_instance_id?` |
| `experiment_hypotheses` | `experiment_id`, `hypothesis_id` (une expérience peut tester plusieurs hypothèses) |
| `results` | `experiment_id`, `summary`, `metrics_json` (`{"yes":7,"total":10}`), `recorded_at` |
| `evidences` | `project_id`, `subject_type` (`experiment`,`mission_instance`,`observation`,`interview`,`project_section`,`result`), `subject_id`, `kind` (`note`,`photo`,`audio`,`document`,`link`,`sale`,`number`), `text?`, `media_id?`, `amount_mga?` |
| `conclusions` | `hypothesis_id`, `experiment_id?`, `statement`, `confidence_after` (1–5) |
| `decisions` (append-only) | `hypothesis_id`, `experiment_id?`, `decision` (`continue`,`modify`,`test_more`,`abandon`,`go_back`), `rationale`, `decided_at` |

Contraintes vérifiées par le service de domaine (pas seulement en SQL, car
la sync peut amener des états intermédiaires) : critère verrouillé avant
`running` ; résultat + preuve avant `validated`/`invalidated`.

### 3.5 Médias

| Table | Colonnes principales |
|---|---|
| `media` | `kind` (`photo`,`audio`,`file`), `mime`, `size_bytes` (≤ 10 Mo proposé), `sha256`, `duration_ms?`, `local_path` (local seulement), `upload_status` (`pending`,`uploading`,`uploaded`,`failed`), `remote_path?` |

Les fichiers sont stockés dans le répertoire privé de l'application,
chiffrés avec la sous-clé médias de l'UMK
([SECURITY §4.7](SECURITY.md#47-médias--format-v1)).

### 3.6 Contenu (local seulement)

| Table | Rôle |
|---|---|
| `content_packs` | `pack_id`, `version`, `sha256`, `signature_verified_at`, `installed_at`, `is_active` |
| `content_nodes` | `pack_id`, `node_id`, `node_type`, `parent_id`, `order`, `json` — index par type et parent |
| `content_assets` | audio/images de contenu téléchargés à la demande, avec taille et dernier accès (éviction LRU) |

### 3.7 Synchronisation (local seulement)

| Table | Colonnes |
|---|---|
| `sync_meta` (local seulement) | `entity_type`, `entity_id`, `base_version?`, `change_id?`, `pushed_change_id?`, `last_error?`, `attempts`, `next_attempt_at?` |
| `sync_state` (local seulement) | clé/valeur : `cursor`, `device_id`, `last_push_at`, `last_pull_at`, `device_revoked` |
| `conflict_copies` (**synchronisée**, append-only) | `entity_type`, `entity_id`, `payload_json`, `from_device_id`, `resolved_at?`, `resolution?` |

L'envoi des fichiers médias est suivi par la table **locale**
`media_uploads` (schéma v4, jamais synchronisée : savoir qu'un fichier est
à envoyer dépend du téléphone), et non par des colonnes `upload_*` de
`media`, qui seraient synchronisées. `sync_meta.purge_requested`
(schéma v5) marque une suppression définitive en attente de confirmation
du serveur (OFFLINE_SYNC §7). Détail du protocole : [OFFLINE_SYNC.md](OFFLINE_SYNC.md).

## 4. Évolution des schémas

- **Local** : migrations Drift numérotées, schémas exportés
  (`drift_dev schema dump`) et testés (`schema generate` + tests de migration
  pour chaque version publiée).
- **Payloads** : `schema_version` dans chaque enveloppe (dans la partie
  chiffrée) ; le client sait lire
  N et N-1 et réécrit au format courant lors de la prochaine modification. Un
  client plus ancien qui reçoit un `schema_version` inconnu conserve le
  payload brut sans l'écraser et demande une mise à jour.
- **Serveur** : migrations SQL dans `supabase/migrations/`, testées par pgTAP
  en CI.
