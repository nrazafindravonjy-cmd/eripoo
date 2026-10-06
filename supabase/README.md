# Supabase — Eripoo

Trois environnements séparés (décision du 2026-10-06, DEVELOPMENT_PLAN P4) :

| | Local | Développement / staging | Production |
|---|---|---|---|
| Données | fictives uniquement | comptes de test, effaçables | réelles |
| Schéma | `migrations/` rejouées | mêmes migrations, par la CI | mêmes migrations, pipeline de release — **pas encore créé** |
| Secrets | jamais versionnés | jamais versionnés | jamais versionnés ; jamais dans l'app |

- `migrations/` : schéma serveur minimal v1 (**non figé**).
- `tests/sql/` : tests SQL (RLS, appareils, synchronisation, enveloppe de
  récupération).
- `tests/run_local.sh --stub` : exécute les tests sur un PostgreSQL simple
  avec une **simulation partielle** de `auth` (`tests/local_stub/`).
- `tests/run_local.sh` : exécute les tests sur une base déjà migrée par
  Supabase (`supabase start && supabase db reset`).

- `config.toml` : configuration de la **pile locale uniquement**
  (`supabase start`) : services inutiles désactivés, inscription sans
  confirmation d'e-mail, limites de débit relevées pour les tests. Aucun
  secret (les clés locales sont les valeurs publiques par défaut de la CLI).
  Le projet de développement en ligne et la production se configurent dans
  leur propre tableau de bord, jamais avec ce fichier.
- `../test/contract/` : la même suite de tests du contrat RPC tourne sur le
  faux serveur Dart (toujours) et sur Supabase (CI, job « Supabase local ») :

```sh
supabase start && supabase db reset
eval "$(supabase status -o env | grep -E '^(API_URL|ANON_KEY)=')"
ERIPOO_TEST_SUPABASE_URL=$API_URL ERIPOO_TEST_SUPABASE_ANON_KEY=$ANON_KEY \
  flutter test --tags supabase test/contract/supabase_remote_contract_test.dart
```

Le test refuse une URL non locale sauf `ERIPOO_TEST_SUPABASE_ALLOW_REMOTE=dev`
(projet de développement uniquement, comptes fictifs aléatoires).

Différences entre les trois serveurs de test : `docs/OFFLINE_SYNC.md` §13.3.
