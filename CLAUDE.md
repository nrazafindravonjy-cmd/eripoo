# Eripoo — consignes pour Claude Code

Application Android Flutter d'accompagnement de projets entrepreneuriaux pour
Madagascar (« Mihary ho an'ny ho avy. »), offline-first, en français et en
anglais (malagasy abandonné le 2026-10-23 par décision du porteur ; seul
le slogan reste en malagasy), chiffrée de bout en bout. Les dix phases du cahier des
charges sont livrées ; ce qui reste à faire est dans
[docs/NEXT_STEPS.md](docs/NEXT_STEPS.md). Documentation de référence :
`docs/` (ARCHITECTURE, SECURITY, DATA_MODEL, OFFLINE_SYNC, PRODUCT_ARCHITECTURE,
DESIGN_SYSTEM, DEVELOPMENT_PLAN, END_CHECKLIST, RELEASE_CHECKLIST).

Le porteur du projet écrit en français : rapports et réponses en français.

## Règles non négociables

- Aucune cryptographie maison (libsodium via `sodium`, sqlite3mc, Keystore).
- Aucune donnée de projet privée en clair côté serveur ; aucun accès
  administrateur au contenu privé ; aucune donnée de projet privée envoyée à
  un modèle d'IA externe.
- Aucun secret dans Git, aucun secret de production dans l'application
  (seules l'URL Supabase et la clé publique `anon`, via `env/*.json` non
  versionnés et `--dart-define-from-file`).
- Aucun contenu utilisateur dans les journaux (`AppLogger` expurgé, jamais
  `print`).
- Supabase : migrations versionnées dans `supabase/migrations/` (jamais de
  modification manuelle), RLS et RPC testées (`supabase/tests/sql/`),
  configuration séparée par environnement. **Ne pas créer l'environnement de
  production** sans décision explicite du porteur.
- Ne jamais inventer de réglementation : toute information juridique ou
  administrative est sourcée et datée, sinon marquée **NON VÉRIFIÉ**.
- Ne jamais déclarer fait ce qui ne l'est pas ; pas de faux silencieux
  (mock présenté comme réel). Pas de sur-ingénierie.
- Données de test fictives uniquement (domaines example.com/.org/.invalid,
  aucun numéro de téléphone malgache réel).
- Pas d'enregistrement audio des personnes interviewées (avis juridique en
  attente).
- Ne pas démarrer sans décision du porteur : production Supabase, analytics
  de production, SMS, connexion Google/téléphone, fournisseur d'IA,
  publication Play.

## Conventions de code

- Flutter 3.47.6, Riverpod 3, go_router, Drift (sqlite3mc), Supabase.
- `lib/core` et `lib/**/domain` restent en Dart pur (pas de Flutter).
- Aucun texte en dur dans l'interface (`Text('...')` interdit) : tout passe
  par les ARB. Ajouter des chaînes : `python3 tool/add_l10n.py strings.json`
  puis `flutter gen-l10n`.
- Les exceptions ne portent pas de texte (types seulement).
- Couleurs uniquement depuis les tokens du design system.
- Imports triés (`dart fix --apply --code=directives_ordering`).
- Ces règles sont vérifiées par `test/architecture/source_rules_test.dart`.
- Contenu pédagogique en YAML dans `content/`, compilé par
  `dart run tool/content_build.dart` (pack versionné dans `assets/content/`).

## Avant chaque commit

```sh
flutter pub get && dart run build_runner build   # une fois par session
tool/check.sh                                     # format, analyse, contenu, tests
```

Tests SQL (PostgreSQL 16 local, schéma auth simulé) :
`PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres supabase/tests/run_local.sh --stub`
(sinon Supabase local complet : `supabase start` puis `supabase/tests/run_local.sh`).

Tests de widgets : IO réelle dans `tester.runAsync`, pas de `pumpAndSettle`
pendant qu'un minuteur tourne.

## CI (minutes GitHub Actions limitées)

Chaque PR lance format, analyse, tests, tests SQL et contrat Supabase. Les
jobs Android (build, vérification de l'APK release, émulateurs) ne tournent
qu'à la demande (Actions → CI → Run workflow) : les lancer avant une release
ou après un changement Android. Un changement limité à `docs/` ou aux `.md`
ne lance rien.
