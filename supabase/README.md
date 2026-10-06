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

`config.toml` n'est pas encore versionné : il sera généré par
`supabase init` lors de la création du projet de développement, puis
complété (liaison manuelle d'identités, fournisseurs) et versionné.
