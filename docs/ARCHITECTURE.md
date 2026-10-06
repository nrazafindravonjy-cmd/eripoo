# Eripoo — Architecture technique

Statut : **proposition Phase 0, à valider.** Les décisions marquées ⚠️ sont
difficiles à changer plus tard et attendent une validation explicite
(liste consolidée dans [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md#décisions-à-valider)).

Documents liés :
[PRODUCT_ARCHITECTURE](PRODUCT_ARCHITECTURE.md) ·
[DATA_MODEL](DATA_MODEL.md) ·
[OFFLINE_SYNC](OFFLINE_SYNC.md) ·
[SECURITY](SECURITY.md) ·
[DEVELOPMENT_PLAN](DEVELOPMENT_PLAN.md)

---

## 1. Vue d'ensemble

```
┌──────────────────────────── Appareil Android ────────────────────────────┐
│                                                                          │
│  Présentation (widgets, écrans)  ── lit/écoute ──►  Contrôleurs Riverpod │
│                                                        │                 │
│                                       Domaine (services purs, règles)    │
│                                                        │                 │
│  Moteur de contenu ◄── packs JSON ──┐     Repositories (interfaces)      │
│  (règles, parcours)                 │                  │                 │
│                                     │      Drift / SQLite chiffré  ◄── source de vérité locale
│                                     │                  │                 │
│                                     │      Outbox ─► Moteur de sync ─► Codec E2EE
│                                     │                                    │
└─────────────────────────────────────┼────────────────────┼───────────────┘
                                      │ HTTPS              │ HTTPS (RPC)
┌─────────────────────────────── Supabase ────────────────────────────────┐
│  Storage `content` (packs publiés)   Postgres: sync_records (chiffrés),  │
│  Storage `user-media` (chiffré)      user_keys, profiles, consents,      │
│  Auth (email, Google, téléphone)     contenu (auteur), analytics agrégés │
│  Edge Functions (suppression de compte, ingestion analytics, proxy IA)   │
└──────────────────────────────────────────────────────────────────────────┘
```

Principes structurants :

1. **La base locale est la source de vérité de l'application.** L'UI ne lit
   jamais le réseau directement ; elle observe Drift. Le réseau ne sert qu'à
   synchroniser, authentifier, télécharger du contenu et appeler quelques
   services optionnels (transcription, IA).
2. **Les données privées sont chiffrées de bout en bout avant de quitter
   l'appareil** ⚠️ (voir [SECURITY.md](SECURITY.md#4-chiffrement-de-bout-en-bout)).
   Le serveur stocke des blobs opaques ; il ne peut ni lire ni fusionner le
   contenu des projets. Conséquence directe : la résolution de conflits est
   faite côté client.
3. **Le parcours est piloté par du contenu**, pas par du code d'écran : des
   packs de contenu versionnés décrivent quêtes, étapes, missions, règles et
   traductions ; un moteur déterministe en Dart les interprète.
4. **Pas d'IA au cœur.** Les règles de progression, de déblocage et
   d'adaptation sont déterministes et testées unitairement. L'IA est une
   couche optionnelle, remplaçable, soumise à consentement.

## 2. Stack retenue

Stack recommandée par le cahier des charges, conservée : **Flutter / Dart,
Riverpod, go_router, Drift (SQLite), Supabase.** Aucune raison objective de
la remplacer pour les contraintes d'Eripoo (Android d'entrée de gamme,
offline, petite équipe).

| Élément | Version vérifiée (résolution pub, 2026-10-06) |
|---|---|
| Flutter | 3.47.6 stable (Dart 3.13.5) |
| Android minSdk | 24 (Android 7.0) — minimum imposé par Flutter 3.47 |

Les versions de paquets sont listées en [§12](#12-dépendances).

## 3. Couches et règles de dépendance

| Couche | Contenu | Peut dépendre de |
|---|---|---|
| `presentation` | widgets, écrans, contrôleurs Riverpod (`Notifier`), mapping état → UI | domain |
| `domain` | entités, value objects, services purs (machine d'états d'hypothèse, calculs financiers, planificateur de parcours), interfaces de repository | rien (Dart pur) |
| `data` | implémentations de repository (Drift), DAO, mappers | domain, core |
| `sync` | outbox, push/pull, fusion, codec chiffré | data, security, core |
| `content` | modèles de contenu, chargeur de packs, évaluateur de règles | core |
| `security` | gestion de clés, chiffrement, stockage sécurisé | core |
| `services` (externes) | Supabase, transcription, IA, notifications | core |
| `core` | erreurs, `Result`, logger expurgé, horloge HLC, UUID, config | — |

Règles :

- **Aucune logique métier dans les widgets.** Un widget affiche un état et
  émet des intentions vers un contrôleur.
- **Le domaine est du Dart pur** (aucun import Flutter, Drift ou Supabase) :
  testable sans émulateur, rapide en CI.
- **Toute écriture métier passe par un repository** qui, dans la même
  transaction Drift, écrit la ligne, met à jour les horloges et ajoute
  l'opération à l'outbox. Il est impossible de modifier une donnée
  synchronisable sans produire l'opération de sync correspondante.
- Les règles de dépendance seront vérifiées en CI par un script simple
  (`tool/check_layers.dart`, Phase 1) qui interdit par exemple
  `import 'package:flutter/...'` dans `domain/`.

Pas de « use case » d'une ligne pour chaque action : un service de domaine
regroupe les opérations d'un agrégat (ex. `HypothesisService`). C'est la
« clean architecture pragmatique » demandée.

## 4. Architecture Flutter

### 4.1 État : Riverpod 3

- `flutter_riverpod` **sans** générateur de code au départ : Drift impose déjà
  `build_runner` ; éviter un second générateur limite les temps de build et
  la complexité. Réévaluable.
- Providers d'infrastructure (base, client Supabase, horloge, gestionnaire de
  clés) déclarés dans `lib/app/di/` et surchargeables en test
  (`ProviderScope(overrides: ...)`).
- Les contrôleurs d'écran exposent des états immuables (classes `sealed` Dart
  3 : `Loading / Data / Error / Offline`), pas de `setState` métier.
- Les flux Drift (`watch()`) alimentent des `StreamProvider` : l'UI se met à
  jour automatiquement après une écriture locale ou une synchro.

### 4.2 Navigation : go_router

- `StatefulShellRoute` avec 5 branches : Accueil, Ma quête, Projet, Outils,
  Profil (état de chaque onglet conservé).
- Redirections pilotées par l'état local (onboarding fait ? diagnostic fait ?)
  — **jamais** par l'état réseau ou l'authentification : un invité a accès à
  tout le parcours.
- Écrans de parcours ouverts par identifiant de contenu
  (`/quest/:questId/step/:stepId`), ce qui rend les notifications et reprises
  robustes.

### 4.3 Thème et design tokens

Phase 1. Tokens (couleur, typo, espacement, rayon, durée d'animation) définis
une fois, exposés via `ThemeExtension`, déclinés clair/sombre. Les widgets
n'utilisent jamais de couleur littérale ; une règle de revue + un test
`grep` en CI l'imposent.

### 4.4 Internationalisation de l'interface

- `gen-l10n` (ARB) pour toutes les chaînes d'interface : `lib/l10n/app_fr.arb`
  (modèle), `app_mg.arb`, `app_en.arb`. **En place dès la Phase 0.**
- **Constat vérifié :** Flutter ne fournit pas de localisations
  Material/Cupertino pour le malagasy, et `intl` 0.20.3 n'a pas de symboles
  de date/nombre `mg`. Solution en place : délégués de repli qui servent les
  chaînes du framework en français quand la langue est `mg`
  (`lib/l10n/mg_fallback_localizations.dart`). Les dates et montants seront
  formatés par un `EripooFormatter` maison (Phase 1) avec noms de mois
  malagasy **à faire valider par un locuteur natif**.
- Le contenu pédagogique n'est pas dans les ARB : il vient des packs de
  contenu (voir [PRODUCT_ARCHITECTURE §6](PRODUCT_ARCHITECTURE.md#6-contenu-multilingue-fr--mg--en)).

## 5. Offline-first (résumé)

Détail complet : [OFFLINE_SYNC.md](OFFLINE_SYNC.md).

- Toutes les entités utilisateur vivent dans Drift avec `id` UUID v7,
  `created_at`, `updated_at`, `deleted_at`, `version`, horloges HLC par champ
  et `sync_status`.
- Chaque écriture ajoute une opération idempotente à l'outbox locale.
- Le moteur de sync pousse l'outbox puis tire les changements serveur par
  curseur monotone ; déclenché au démarrage, au retour au premier plan, au
  retour du réseau, après une écriture (avec anti-rebond) et périodiquement.
- Le serveur ne voit que des enveloppes chiffrées ; la fusion à trois voies
  par champ est faite côté client ; aucune perte silencieuse (copie de
  conflit conservée et visible).
- Le contenu pédagogique est embarqué (pack de base dans l'APK) puis mis à
  jour par téléchargement delta quand le réseau le permet.

## 6. Synchronisation avec Supabase (résumé)

- Une table générique `sync_records` (blob chiffré + métadonnées minimales)
  au lieu d'une table par entité : le serveur n'a pas besoin de comprendre le
  contenu, et l'ajout d'une entité ne demande aucune migration serveur.
- Écritures uniquement via RPC `sync_push` (compare-and-swap sur
  `server_version`, idempotence par `op_id`, verrou consultatif par
  utilisateur pour garantir un curseur sans trou).
- Lecture via RPC `sync_pull(since, limit)`.
- Médias (photos, audio) chiffrés côté client puis envoyés dans le bucket
  privé `user-media/{uid}/…`.

⚠️ **Choix d'un moteur de sync maison plutôt que PowerSync / ElectricSQL.**
Ces outils sont excellents pour synchroniser des tables relationnelles
lisibles par le serveur ; avec le chiffrement de bout en bout, leurs
« sync rules » côté serveur deviennent inutiles, et ils ajoutent un
service tiers qui verrait passer les données (même chiffrées) et un coût
d'hébergement. Le protocole décrit ici est volontairement petit (2 RPC,
1 table). Si le chiffrement de bout en bout était abandonné, PowerSync
redeviendrait une option sérieuse à réévaluer.

## 7. Authentification (résumé)

Détail : [SECURITY.md §3](SECURITY.md#3-authentification).

- Invité **100 % local** (aucun compte Supabase anonyme) : diagnostic et
  début de parcours sans réseau ni compte.
- Création de compte : e-mail/mot de passe, Google (`signInWithIdToken` via
  le SDK Google natif), téléphone (OTP SMS). Facebook prévu dans
  l'énumération des fournisseurs, désactivé.
- Liaison de plusieurs méthodes au même compte via l'API de liaison
  d'identités de Supabase (`linkIdentity` / `linkIdentityWithIdToken`,
  présentes dans `supabase_flutter` 2.18.0 / `gotrue` 2.27.2 — vérifié).
- Migration invité → compte : réattribution locale du propriétaire puis
  envoi de toutes les lignes par l'outbox ; rien n'est supprimé localement.

## 8. Architecture tablette / téléphone

- Portrait uniquement (verrouillé au démarrage via `SystemChrome`).
- Classes de largeur (Material) : **compacte** < 600 dp (téléphone),
  **moyenne** 600–839 dp (tablette 7–10" en portrait), **étendue** ≥ 840 dp
  (rare en portrait, traitée comme moyenne avec largeur max).
- Un seul arbre de widgets ; les écrans reçoivent la classe de largeur via un
  `LayoutBuilder` central (`AdaptiveScaffold` maison, Phase 1) :
  - compacte : `NavigationBar` en bas, une colonne ;
  - moyenne : `NavigationRail` à gauche, contenu centré avec largeur de
    lecture max (~640 dp), maître/détail pour Projet et Outils (liste à
    gauche, détail à droite).
- Typographie et zones tactiles basées sur des tokens ; respect de
  `textScaler` (taille de police système) jusqu'à 200 % testée.
- Tests de widget exécutés sur au moins deux tailles (360×640 et 800×1280).

## 9. Optimisation pour anciens appareils Android

Cible de référence proposée ⚠️ : Android 7–10, 1–2 Go de RAM, CPU 32 bits
(armeabi-v7a), stockage 16 Go presque plein, réseau 2G/3G intermittent.

| Domaine | Mesures |
|---|---|
| Binaire | App Bundle (le Play Store ne livre que l'ABI de l'appareil) + APK `--split-per-abi` pour distribution hors Play ; `--obfuscate --split-debug-info` ; arbre d'icônes élagué ; pas de polices embarquées lourdes (une famille variable, sous-ensemble latin) ; pas de Lottie/Rive. |
| Démarrage | Initialisation paresseuse (Supabase, contenu distant, crypto) ; ouverture de la base sur un isolat d'arrière-plan (`drift_flutter`) ; premier écran rendu depuis le cache local sans attendre le réseau. |
| Mémoire | Listes paresseuses (`ListView.builder`), images décodées à la taille d'affichage (`cacheWidth`), pas de cache d'images non borné, audio lu en streaming depuis le fichier. |
| Base locale | Index sur les clés étrangères et `sync_status` ; requêtes paginées ; WAL ; pas de JSON géant dans une seule ligne. |
| Médias | Photos redimensionnées (~1280 px, JPEG/WebP qualité ~70) avant stockage ; audio mono bas débit (AAC ~32 kbit/s) ; chiffrement par blocs en isolat. |
| Réseau | Lots de sync bornés (taille et nombre) ; compression gzip des réponses ; contenu en deltas ; aucune requête au démarrage si le cache est frais ; envoi des médias seulement en Wi-Fi par défaut (réglable). |
| Animations | Animations implicites courtes ; désactivées si `MediaQuery.disableAnimations` ou si l'appareil est détecté lent (option « animations réduites »). |
| Rendu | Valider le moteur de rendu (Impeller / Skia) sur les appareils de référence ; pas d'hypothèse a priori. |

Budget à faire respecter en CI/QA (Phase 10, mesuré sur appareil réel) :
démarrage à froid < 3 s, APK par ABI < 25 Mo, RAM < 200 Mo en usage normal.
Ces seuils sont des objectifs proposés, pas des mesures.

## 10. Stratégie de tests

| Niveau | Cible | Outils |
|---|---|---|
| Unitaires (domaine) | règles de progression, évaluateur de règles, planificateur de parcours, machine d'états hypothèse/expérience, calculs financiers (entiers MGA), HLC, fusion de conflits, codec chiffré, règles d'accès client | `flutter_test`/`test`, `mocktail` pour les frontières |
| Base locale | DAO, migrations Drift (tests de migration générés par `drift_dev schema`), transaction écriture + outbox | Drift en mémoire (`NativeDatabase.memory()`) |
| Sync | scénarios offline, retour online, conflit, suppression locale, coupure réseau pendant push, fermeture de l'app pendant sync (reprise), rejeu idempotent | **serveur de sync en mémoire** implémentant la même interface que le client Supabase (faux de test, documenté comme tel) + tests contre Supabase local |
| Serveur | politiques RLS, RPC `sync_push`/`sync_pull`, refus d'accès admin aux données privées | Supabase CLI local + pgTAP (`supabase test db`) |
| Widgets | composants critiques du design system, états loading/error/offline, accessibilité (`meetsGuideline`), clair/sombre, 2 tailles d'écran, 3 langues | `flutter_test` |
| Intégration | onboarding, création de compte, création projet, parcours, offline/reconnexion/sync | `integration_test` sur émulateur API 24 et API récente en CI |
| Contenu | schéma des packs, références croisées, traductions manquantes, règles de lisibilité (questions par étape, longueur), sources présentes pour l'information réglementaire | outil CLI Dart `tool/content_validate.dart` en CI |
| Appareil lent | démarrage, défilement, mémoire | profilage manuel sur appareil de référence + `flutter drive --profile` |

Les tests de sync réutilisent un **bus de faute injectable** (coupure après N
octets, timeout, réponse dupliquée, crash simulé entre deux étapes) pour
couvrir les cas 1 à 6 du §51 du cahier des charges.

## 11. Arborescence du projet

État actuel (Phase 0) en **gras** ; le reste est la cible.

```
eripoo/
├── **.github/workflows/ci.yml**        format, analyze, test, build APK debug
├── **analysis_options.yaml**           lints stricts
├── **l10n.yaml**
├── **pubspec.yaml**
├── **android/**                        projet Android (backup désactivé)
├── **docs/**                           ce dossier
├── content/                            sources du contenu pédagogique (Phase 3)
│   ├── schema/                         JSON Schema des packs
│   ├── packs/core/                     quêtes, étapes, missions, badges, outils (YAML)
│   └── madagascar/                     informations réglementaires sourcées
├── supabase/                           (Phase 2/5)
│   ├── config.toml
│   ├── migrations/                     SQL versionné (tables, RLS, RPC)
│   ├── functions/                      Edge Functions (delete-account, ingest-analytics, ai-proxy)
│   └── tests/                          pgTAP (RLS, RPC)
├── tool/                               scripts Dart (validation contenu, couches, compilation packs)
├── lib/
│   ├── **main.dart**
│   ├── bootstrap.dart                  init ordonnée (logger, base, clés, providers)
│   ├── app/
│   │   ├── **app.dart**                MaterialApp, thème, l10n
│   │   ├── router/                     go_router, shell 5 onglets, redirections
│   │   └── di/                         providers d'infrastructure
│   ├── core/
│   │   ├── config/                     environnement (URL Supabase, clé anon) via --dart-define
│   │   ├── errors/                     Failure, Result
│   │   ├── logging/                    logger expurgé
│   │   ├── time/                       Clock, HLC
│   │   └── ids/                        UUID v7
│   ├── **l10n/**                       ARB fr/mg/en + replis mg
│   ├── design_system/                  tokens, thème, composants (Phase 1)
│   ├── data/
│   │   ├── local/                      AppDatabase Drift, tables, DAO, migrations
│   │   └── remote/                     client Supabase, DTO de sync
│   ├── sync/                           outbox, engine, pull, push, merge/, codec/
│   ├── security/                       key_manager, crypto, secure_storage
│   ├── content/                        modèles, loader, rules/ (évaluateur), planner/
│   ├── services/                       transcription, ai, notifications, connectivity
│   └── features/
│       ├── onboarding/   diagnostic/   auth/
│       ├── home/         quest/        project/
│       ├── evidence/     (hypothèses, expériences, résultats, preuves, décisions)
│       ├── observations/ interviews/   missions/
│       ├── tools/        finance/      business_model/
│       ├── formalization/              documents/
│       └── profile/      settings/
│           └── <feature>/{domain,data,presentation}/
├── **test/**                           miroir de lib/
└── integration_test/
```

## 12. Dépendances

Résolution vérifiée ensemble dans un projet de test le 2026-10-06 (Flutter
3.47.6). **Installées en Phase 0 : uniquement `flutter_localizations` et
`intl`** (seules utilisées). Les autres seront ajoutées dans la phase qui les
utilise.

| Paquet | Version | Phase | Justification |
|---|---|---|---|
| `flutter_localizations` (SDK) | — | 0 ✅ | Localisations du framework, requis par gen-l10n. |
| `intl` | 0.20.3 | 0 ✅ | Messages ARB, pluriels, formatage (avec repli pour `mg`). |
| `flutter_riverpod` | 3.4.3 | 1 | Imposé par la stack ; injection testable, flux réactifs. |
| `go_router` | 18.0.2 | 1 | Imposé ; navigation déclarative, shell à onglets, liens profonds. |
| `drift` + `drift_dev` (dev) | 2.35.1 | 2 | Base relationnelle typée, migrations testables, requêtes réactives. |
| `drift_flutter` | 0.3.1 | 2 | Ouverture de la base sur un isolat d'arrière-plan, chemins Android. |
| `sqlite3` (transitif, 3.5.2) | — | 2 | Chiffrement de la base via l'option de hook `source: sqlite3mc` (SQLite3MultipleCiphers) ⚠️. **Ne pas** ajouter `sqlcipher_flutter_libs` / `sqlite3_flutter_libs` : ils sont en fin de vie (`+eol`) depuis sqlite3 3.x. |
| `build_runner` (dev) | 2.16.1 | 2 | Génération Drift. |
| `uuid` | 4.6.0 | 2 | UUID v7 (ordonnés dans le temps → index B-tree efficaces). |
| `flutter_secure_storage` | 11.2.0 | 2 | Clés locales (clé de base, clé de chiffrement appareil) dans Android Keystore. |
| `cryptography` + `cryptography_flutter` | 2.9.0 / 2.3.4 | 2 | AES-GCM, HKDF, Argon2id disponibles (vérifié) ; accélération native Android pour AES. |
| `supabase_flutter` | 2.18.0 | 2 | Imposé ; Auth (dont liaison d'identités), RPC, Storage. |
| `connectivity_plus` | 7.3.2 | 5 | Signal de changement de réseau pour déclencher la sync (jamais utilisé comme preuve de connexion). |
| `mocktail` (dev) | 1.0.5 | 1 | Doublures de test sans génération de code. |
| `integration_test` (SDK, dev) | — | 2 | Tests d'intégration sur émulateur. |

Prévues plus tard, à justifier au moment de l'ajout : `google_sign_in`
(Google natif), `record` (audio), `image_picker` + compression d'image,
`flutter_local_notifications` (rappels locaux, sans FCM), `workmanager`
(sync en arrière-plan), génération PDF. Écartés : `freezed`,
`riverpod_generator` (génération de code supplémentaire non nécessaire),
`shared_preferences` pour les données métier (interdit par le cahier des
charges ; éventuellement pour un drapeau d'UI), SDK d'analytics tiers
(voir [SECURITY §7](SECURITY.md#7-analytics-anonymisés)).

## 13. Principaux risques techniques

| # | Risque | Impact | Mitigation |
|---|---|---|---|
| R1 | **Perte de la clé de chiffrement** (appareil perdu + code de récupération perdu) ⇒ copie cloud illisible | Élevé, irréversible pour l'utilisateur | Code de récupération imprimable/QR, rappel à la création de compte, transfert appareil→appareil par QR, données locales intactes tant que l'appareil vit. Décision produit explicite à prendre (voir SECURITY §4.5). |
| R2 | Malagasy absent de Flutter et `intl` | UI partiellement en français pour les utilisateurs `mg` (sélecteurs de date…) | Délégués de repli (fait), formateur maison, traduction des chaînes framework par un locuteur natif. |
| R3 | Reconnaissance vocale du malagasy peu disponible / peu fiable | Transcription inutilisable en `mg` | Audio toujours conservé ; transcription optionnelle et signalée ; ne jamais bloquer une étape sur la transcription. Évaluer les fournisseurs en Phase 9. |
| R4 | Coût / délivrabilité des SMS OTP vers Madagascar | Connexion téléphone non fiable ou chère | Fournisseur SMS à choisir et tester avant production ; e-mail et Google comme alternatives ; limitation de débit. |
| R5 | Bugs de sync (perte, doublon, conflits mal fusionnés) | Perte de confiance majeure | Protocole minimal, idempotence, tests de faute systématiques, journal de conflits visible, aucune suppression physique côté client avant confirmation serveur. |
| R6 | Performances sur appareils 1 Go / 32 bits (SQLite chiffré, crypto, Flutter) | Lenteurs, abandons | Appareils de référence physiques dès la Phase 1, budgets mesurés, crypto en isolat, SQLite3MultipleCiphers (sans OpenSSL). |
| R7 | Information réglementaire malagasy obsolète ou fausse | Préjudice pour l'utilisateur | Aucune donnée réglementaire sans source, date de vérification et date de revue ; publication bloquée sinon. |
| R8 | Conformité mineurs / protection des données non validée juridiquement | Blocage de lancement | Politiques configurables par juridiction ; validation juridique obligatoire avant production (pas d'hypothèse dans le code). |
| R9 | Dépendance à Supabase (pause des projets gratuits, coûts Storage audio, région) | Indisponibilité / coûts | Plan payant en production, quotas médias par utilisateur, compression audio, protocole de sync portable (Postgres standard). |
| R10 | Évolution du contenu incompatible avec la progression existante | Progression cassée après mise à jour | Identifiants de contenu stables, packs versionnés, migrations de progression, tests de compatibilité de packs. |
| R11 | Écart entre « offline » et « appareil partagé » (téléphone familial) | Lecture du projet par un tiers | Base chiffrée + verrou applicatif optionnel (PIN/biométrie) ⚠️. |
