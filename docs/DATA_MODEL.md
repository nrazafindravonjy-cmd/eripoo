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
([SECURITY §4](SECURITY.md#4-chiffrement-de-bout-en-bout)). Si ce choix était
refusé, le modèle serveur deviendrait un miroir typé du modèle local (avec
RLS par table) — changement lourd une fois des données en production.

---

## 1. Conventions communes

### 1.1 Colonnes de toute entité synchronisable (local)

| Colonne | Type | Rôle |
|---|---|---|
| `id` | TEXT (UUID v7) | Généré sur l'appareil ; identique local/serveur. |
| `owner_id` | TEXT | `local:<uuid>` pour un invité, puis `auth.uid()` après inscription. |
| `project_id` | TEXT nullable | Rattachement projet (index). |
| `created_at` | INTEGER (ms UTC) | Création locale. |
| `updated_at` | INTEGER (ms UTC) | Dernière modification locale (affichage). |
| `deleted_at` | INTEGER nullable | Suppression logique (tombstone). |
| `version` | INTEGER | Incrément local à chaque écriture. |
| `field_clocks` | TEXT (JSON) | HLC par champ modifiable : `{"statement": "1739...:0003:dev7"}`. |
| `synced_clocks` | TEXT (JSON) nullable | Horloges au dernier état confirmé par le serveur (base de la fusion). |
| `server_version` | INTEGER nullable | Dernière `server_version` connue. |
| `sync_status` | INTEGER (enum) | `pending`, `synced`, `conflict`, `local_only`. |

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

user_keys (
  user_id        uuid references auth.users on delete cascade,
  key_version    int not null,
  wrapped_dek    bytea not null,     -- DEK chiffrée par la clé de récupération
  wrap_algorithm text not null,      -- ex. 'argon2id+aes-256-gcm'
  kdf_params     jsonb not null,     -- sel, coûts
  created_at     timestamptz not null default now(),
  primary key (user_id, key_version)
)
-- RLS : select/insert pour user_id = auth.uid(). Aucun update/delete client.

consents (
  id            uuid primary key,
  user_id       uuid references auth.users on delete cascade,
  consent_type  text not null,   -- 'privacy_policy','analytics','ai_processing','parental'
  policy_version text not null,
  granted       boolean not null,
  recorded_at   timestamptz not null default now()
)                                 -- append-only ; RLS propriétaire

devices (
  id uuid primary key, user_id uuid references auth.users on delete cascade,
  created_at timestamptz, last_seen_at timestamptz, app_version text
)                                 -- révocation et diagnostic sync ; pas de modèle d'appareil

jurisdiction_policies (           -- valeurs à fournir par validation juridique
  code text primary key, min_age int, parental_consent_under int,
  legal_validated boolean not null default false, source text, updated_at timestamptz
)                                 -- lecture publique, écriture admin

deletion_requests (user_id, requested_at, completed_at)   -- trace minimale
```

### 2.2 Données privées synchronisées (chiffrées)

```sql
create sequence sync_server_version_seq;

sync_records (
  id               uuid primary key,          -- = id local de l'entité
  owner_id         uuid not null references auth.users on delete cascade,
  server_version   bigint not null,           -- nextval à chaque écriture
  deleted          boolean not null default false,
  key_version      int not null,
  schema_version   int not null,              -- format du payload
  payload          bytea,                     -- nonce || ciphertext || tag ; null si purgé
  payload_size     int not null,
  device_id        uuid,
  server_updated_at timestamptz not null default now()
);
create index on sync_records (owner_id, server_version);

sync_applied_ops (
  owner_id uuid, op_id uuid, result jsonb, applied_at timestamptz,
  primary key (owner_id, op_id)
)                                -- idempotence ; purge après 30 jours
```

- Le **type d'entité, le projet, les dates métier et tout le contenu sont
  dans le payload chiffré**. Métadonnées visibles par le serveur : id,
  propriétaire, versions, taille, suppression, date serveur.
- RLS : `select` si `owner_id = auth.uid()`. **Aucun** `insert/update/delete`
  direct : écritures via `sync_push` (`security definer`, vérifie
  `auth.uid()`), lecture via `sync_pull`.

### 2.3 Médias

Bucket Storage **privé** `user-media`, chemin `{owner_id}/{media_id}`,
contenu chiffré côté client. Politiques `storage.objects` :
`(storage.foldername(name))[1] = auth.uid()::text` pour select/insert/delete.
Les métadonnées du média (type, taille, hash) sont dans une entité `media`
chiffrée de `sync_records`.

### 2.4 Contenu (public en lecture, édition réservée)

```sql
content_releases (
  id uuid primary key, pack_id text, version int, status text
    check (status in ('draft','published','retired')),
  min_app_version text, sha256 text, storage_path text,
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
[SECURITY §5](SECURITY.md#5-isolation-des-administrateurs).

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
| `media` | `kind` (`photo`,`audio`,`file`), `mime`, `size_bytes`, `sha256`, `duration_ms?`, `local_path` (local seulement), `file_key_wrapped` (clé de fichier chiffrée par la DEK), `upload_status` (`pending`,`uploading`,`uploaded`,`failed`), `remote_path?` |

Les fichiers sont stockés dans le répertoire privé de l'application, chiffrés
avec une clé par fichier.

### 3.6 Contenu (local seulement)

| Table | Rôle |
|---|---|
| `content_packs` | `pack_id`, `version`, `sha256`, `installed_at`, `is_active` |
| `content_nodes` | `pack_id`, `node_id`, `node_type`, `parent_id`, `order`, `json` — index par type et parent |
| `content_assets` | audio/images de contenu téléchargés à la demande, avec taille et dernier accès (éviction LRU) |

### 3.7 Synchronisation (local seulement)

| Table | Colonnes |
|---|---|
| `outbox` | `op_id` (UUID), `entity_type`, `entity_id`, `op` (`upsert`,`delete`), `enqueued_at`, `attempts`, `next_attempt_at`, `last_error_code?`, `in_flight` |
| `sync_state` | `cursor_server_version`, `last_pull_at`, `last_push_at`, `last_error_code?` |
| `sync_conflicts` | `entity_type`, `entity_id`, `losing_payload_json`, `field_keys`, `detected_at`, `resolved_at?`, `resolution` |
| `media_upload_queue` | `media_id`, `attempts`, `next_attempt_at`, `bytes_sent` |

## 4. Évolution des schémas

- **Local** : migrations Drift numérotées, schémas exportés
  (`drift_dev schema dump`) et testés (`schema generate` + tests de migration
  pour chaque version publiée).
- **Payloads** : `schema_version` dans chaque enveloppe ; le client sait lire
  N et N-1 et réécrit au format courant lors de la prochaine modification. Un
  client plus ancien qui reçoit un `schema_version` inconnu conserve le
  payload brut sans l'écraser et demande une mise à jour.
- **Serveur** : migrations SQL dans `supabase/migrations/`, testées par pgTAP
  en CI.
