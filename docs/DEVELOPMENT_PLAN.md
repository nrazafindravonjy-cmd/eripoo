# Eripoo — Plan de développement

Chaque phase est : implémentée → testée → vérifiée → documentée → **validée
par le porteur du projet** avant la suivante. Une phase n'est « terminée »
que selon la Definition of Done du cahier des charges (§56).

---

## Phase 0 — Architecture et fondations (en cours de validation)

### Réalisé

| Élément | État |
|---|---|
| Documents d'architecture (6 fichiers dans `docs/`) | ✅ rédigés, à valider |
| Projet Flutter Android (`mg.eripoo.eripoo`, Flutter 3.47.6, minSdk 24) | ✅ créé |
| Lints stricts (`strict-casts`, `strict-inference`, `strict-raw-types`, `avoid_print`…) | ✅ `flutter analyze` : 0 problème |
| i18n fr/mg/en (gen-l10n, ARB, repli français des chaînes framework pour `mg`) | ✅ testé (4 tests) |
| Sauvegarde Android désactivée (`allowBackup=false` + `data_extraction_rules.xml`) | ✅ écrit — **non vérifié par un build Android** (pas de SDK Android dans l'environnement de développement) ; vérifié par la CI au premier passage |
| CI GitHub Actions (format, analyze, test, build APK debug) | ✅ écrite — **pas encore exécutée** |
| Résolution de l'ensemble des dépendances cibles (projet de test séparé) | ✅ compatibles, versions listées dans ARCHITECTURE §12 |

### Volontairement non fait en Phase 0

- Thème / design tokens, navigation go_router, Riverpod : Phase 1.
- Base Drift, Supabase, sync, chiffrement : Phases 2 et 5 (dépendent des
  décisions D1–D4 ci-dessous).
- Aucun écran produit. L'unique écran actuel affiche le nom et le slogan ;
  c'est un point d'amorçage, pas une fonctionnalité.

## Phases suivantes

L'ordre du cahier des charges est conservé, avec **deux ajustements
proposés** ⚠️ :

1. **Le socle de sync (colonnes de sync, HLC, outbox, codec chiffré) est
   construit en Phase 2**, en même temps que la base locale, et non en
   Phase 5. Raison : chaque entité créée avant aurait sinon à être migrée, et
   la migration invité → compte (Phase 2) en dépend. La Phase 5 garde le
   moteur réseau complet et les tests de faute intensifs.
2. **Le moteur de règles et le format de contenu sont posés en Phase 2**
   (le diagnostic est du contenu), puis enrichis en Phase 3.

| Phase | Contenu | Critères de sortie |
|---|---|---|
| **1 — Design system** | tokens (couleur, typo, espacement, rayon, mouvement) clair/sombre via `ThemeExtension`, composants (boutons, cartes, champs, progression, badges, navigation adaptative, modales, états loading/error/offline, bloc « aide » anti-blocage), `AdaptiveScaffold` téléphone/tablette, go_router (shell 5 onglets vides honnêtes), Riverpod, logger expurgé, formateur date/montant `mg` | tests de widget clair/sombre × 2 tailles × 3 langues, `meetsGuideline` (contraste, cibles tactiles), aucune couleur littérale hors tokens (vérif. CI), test sur appareil de référence |
| **2 — Onboarding + diagnostic + socle données** | Drift chiffré, colonnes de sync, HLC, outbox, gestion de clés (DEK locale), format de contenu + évaluateur de règles + validateur CLI, pack `diagnostic`, profil invité local, création du projet, Supabase (projet, migrations, RLS, `user_keys`, `profiles`, `consents`), comptes e-mail/Google/téléphone, code de récupération, migration invité → compte | onboarding + diagnostic complets offline ; migration testée sans perte ; tests pgTAP RLS ; tests d'intégration onboarding/compte |
| **3 — Ma quête** | planificateur, exécuteur d'étapes, missions, progression, anti-blocage, statuts `fast_tracked/deferred/postponed`, premières quêtes réelles (contenu relu) | tests unitaires planificateur et règles, parcours de bout en bout offline |
| **4 — Projet** | sections, historique, observations (photo/audio offline), interviews, hypothèses → décisions (machine d'états), preuves, médias chiffrés | machine d'états testée exhaustivement, médias offline |
| **5 — Offline + sync** | RPC `sync_push/pull`, moteur, fusion, conflits UI, médias, WorkManager, transfert QR entre appareils | les 11 scénarios d'OFFLINE_SYNC §10 passent contre faux serveur **et** Supabase local |
| **6 — Outils** | déblocage progressif, guide d'interview, analyse concurrentielle, etc. | — |
| **7 — Finance, business model, documents** | calculateurs, canvas de synthèse, dossier, export PDF | calculs testés aux limites |
| **8 — Formalisation Madagascar** | contenu réglementaire **sourcé** et daté, préparation de documents, renvoi vers les vraies démarches | 100 % des informations avec source + date de vérification |
| **9 — Voix + IA limitée** | transcription optionnelle, proxy IA, consentements par usage | désactivable, aucune donnée envoyée sans consentement |
| **10 — Production** | budgets de performance mesurés, audit sécurité, accessibilité, validation juridique, back-office web | checklist de release complète |

Le back-office web (contenu, traductions, statistiques agrégées) est
planifié après la Phase 6 ; d'ici là le contenu vit en YAML dans le dépôt
(D5).

## Décisions à valider

Classées par coût de changement ultérieur.

| # | Décision | Recommandation | Alternative | Pourquoi c'est structurant |
|---|---|---|---|---|
| **D1** | Chiffrement de bout en bout des données privées | **Oui, option A** (code de récupération), séquestre B ajoutable plus tard | C : RLS seule (ne garantit pas l'exigence « admins ne peuvent pas lire ») | Détermine le modèle serveur, la fusion côté client, l'UX de récupération ; quasi irréversible après lancement |
| **D2** | Acceptation produit du risque de perte (code de récupération perdu + appareils perdus ⇒ copie cloud illisible) | accepter, avec UX de récupération soignée et transfert QR | option B (séquestre) dès le MVP | Impacte la confiance des utilisateurs et le support |
| **D3** | Moteur de sync maison (table d'enveloppes chiffrées + 2 RPC) | **Oui** | PowerSync (pertinent surtout sans E2EE) | Protocole et schéma serveur |
| **D4** | Base locale chiffrée (SQLite3MultipleCiphers) + verrou applicatif optionnel | **Oui** pour le chiffrement ; verrou optionnel | base non chiffrée (plus rapide, moins sûr sur téléphone partagé) | Format du fichier de base ; licence sqlite3mc à vérifier |
| **D5** | Contenu rédigé en YAML dans le dépôt jusqu'à la Phase 6, back-office ensuite | **Oui** | back-office dès la Phase 3 | Rythme de production du contenu, besoin de rédacteurs non techniques |
| **D6** | Identifiant d'application Android `mg.eripoo.eripoo` | à confirmer : **définitif une fois publié sur Play** ; idéalement basé sur un domaine que vous possédez | `app.eripoo`, autre | Irréversible après publication |
| **D7** | Analytics opt-in, sans aucun identifiant, auto-hébergé dans Supabase | **Oui** | opt-out ; outil tiers (Firebase, PostHog…) | Qualité des métriques vs confidentialité (public mineur) |
| **D8** | Rapports de crash maison (sans message d'exception) | **Oui** au départ | Sentry (meilleur outillage, tiers) | Visibilité des bugs en production |
| **D9** | Région d'hébergement Supabase | à choisir (contraintes juridiques + latence depuis Madagascar à mesurer) | — | Migration de région coûteuse |
| **D10** | Fournisseur SMS pour l'OTP téléphone | à choisir après test de délivrabilité et de coût vers les opérateurs malgaches | reporter le téléphone après e-mail/Google | Coût récurrent, fiabilité de connexion |
| **D11** | Appareils de référence pour la performance | ex. Android 7–10, 1–2 Go RAM, 32 bits ; idéalement 2 vrais appareils achetés localement | émulateurs seuls | Validité des budgets de performance |
| **D12** | Analyse juridique (mineurs, données personnelles, mentions réglementaires) | avant la Phase 10, idéalement avant la Phase 2 pour le flux de consentement parental | — | Le flux d'onboarding des mineurs en dépend |
| **D13** | Relecture malagasy (contenu + chaînes framework + formats de date) | désigner un ou plusieurs relecteurs natifs | traduction machine non relue (refusée par l'architecture) | Qualité pour la cible principale |

## Prochaine phase recommandée

**Phase 1 — Design system**, qui ne dépend d'aucune des décisions D1–D4 et
peut démarrer dès validation de ce document. Les décisions D1–D4, D6 et D12
sont en revanche nécessaires **avant la Phase 2**.
