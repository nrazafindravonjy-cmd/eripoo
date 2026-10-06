# Eripoo — Plan de développement

Chaque phase est : implémentée → testée → vérifiée → documentée → **validée
par le porteur du projet** avant la suivante. Une phase n'est « terminée »
que selon la Definition of Done du cahier des charges (§56).

---

## Phase 0 — Architecture et fondations

### Réalisé

| Élément | État |
|---|---|
| Documents d'architecture (6 fichiers dans `docs/`) | ✅ validés (GO Phase 1 donné) |
| Projet Flutter Android (Flutter 3.47.6, minSdk 24) | ✅ créé — identifiant `mg.eripoo.eripoo` **provisoire** (D6) |
| Lints stricts | ✅ `flutter analyze` : 0 problème |
| i18n de l'interface mg/fr/en + repli français des composants Flutter pour `mg` | ✅ testé (4 tests) |
| Sauvegarde Android et transfert d'appareil désactivés | ✅ écrit — **non vérifié par un build Android** (pas de SDK Android dans l'environnement de développement) |
| CI GitHub Actions (format, analyze, test, build APK debug) | ✅ écrite — **pas encore exécutée** |
| Résolution des dépendances cibles (projet de test séparé, dont `sodium` 4.1.1+2) | ✅ compatibles |

### Revues documentaires (aucun code ajouté)

- **v2** : trois secrets distincts, cycle de vie des clés, libsodium,
  synchronisation simplifiée, localisation propre du contenu, séparation
  contenu/interface, analyse des régions, identifiant Android provisoire.
- **v3** (cette revue, `SECURITY.md` principalement) :
  - schéma cryptographique complet : génération exacte, stockage Keystore,
    formats binaires versionnés (enregistrements, médias, enveloppe de clé,
    QR), paramètres Argon2id, sel ;
  - code de récupération : 36 chiffres (116 bits + contrôle de Damm),
    affichage, lecture audio, fiche de secours, vérification, résistance
    chiffrée au brute-force, **aucun vérificateur côté serveur**, refus des
    PIN, limitation des tentatives en ligne ;
  - protocole précis du double QR hors ligne (authentification, protection,
    interposition, expiration, confirmation, interruption, ajout,
    révocation, limite de 5 appareils, perte et vol) ;
  - modèle de menace explicite et liste de ce qui n'est **pas** protégé ;
  - dépendances cryptographiques : versions, maintenance, natif, Android,
    licences, remplacements ; **licence de SQLite3MultipleCiphers vérifiée
    (MIT, compatible Play Store)** ;
  - mises en cohérence : `DATA_MODEL` (enveloppe, `security_events`,
    statut des appareils), `OFFLINE_SYNC`, `ARCHITECTURE` (risques R14–R18),
    renvois entre documents.

## Phase 1 — Design system (ACCEPTÉE le 2026-10-06)

Détail : [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).

| Élément | État |
|---|---|
| Tokens (couleurs clair/sombre, typographie, espacements, rayons, mise en page, mouvement) | ✅ contraste WCAG AA testé sur chaque paire |
| Thème Material complet construit depuis les tokens | ✅ |
| Composants : boutons, cartes, champs, progression, suite d'étapes, badges, dialogues, feuilles, états chargement/erreur/message/hors ligne, aide anti-blocage | ✅ |
| Mise en page adaptative (barre / rail selon la largeur), colonne de lecture | ✅ y compris tablette en paysage (Android 16) |
| go_router (5 onglets) + Riverpod + réglages (thème, langue, animations réduites) | ✅ — réglages **en mémoire seulement** jusqu'à la Phase 2 |
| Logger expurgé (aucune valeur texte libre possible), gestion des erreurs non capturées | ✅ testé avec données sentinelles |
| `EripooFormatter` mg/fr/en (ariary, dates, durées) | ✅ — noms malagasy à relire |
| Chaînes d'interface mg/fr/en | ✅ — malagasy **à relire** (statut suivi) |
| Inventaire des chaînes Material visibles | ✅ DESIGN_SYSTEM §5 |
| Tests : 92 (unitaires, widgets, matrice 12 variantes × 2 tailles de texte, accessibilité, architecture, traductions) | ✅ tous verts |
| Test sur appareil de référence | ❌ non fait (pas d'appareil, D11) |
| Build Android | ❌ jamais exécuté : pas de SDK Android ici, et la CI ne tourne que sur pull request ou `main` |

## Phase 2 — Socle sécurité, données et synchronisation (EN COURS, implémentation terminée, non acceptée)

Les 11 étapes dans l'ordre imposé. « Testé » veut dire testé
automatiquement **sur la machine de développement** (aucun téléphone,
aucun vrai projet Supabase).

| # | Étape | État | Détail |
|---|---|---|---|
| 1 | Stockage local | ✅ testé | Drift, base dans le stockage privé de l'app ; ouverte au démarrage |
| 2 | Chiffrement local | ✅ testé | SQLite3MultipleCiphers 2.5.0, ChaCha20-Poly1305, clé brute `raw:` ; fichier sans en-tête SQLite ni texte clair ; mauvaise clé refusée ; fichiers temporaires en mémoire (SECURITY §4.5) |
| 3 | Gestion des clés | ✅ testé | libsodium ; UMK et DBK aléatoires dans le Keystore (`resetOnError: false`) ; enveloppes v1 ; code de récupération 36 chiffres (Damm) + Argon2id ; clés perdues → écran simple, aucune recréation silencieuse |
| 4 | Verrou applicatif | ✅ testé | facultatif, PIN (Argon2id, vérificateur seulement) + biométrie + délai ; attentes croissantes, pas d'effacement ; PIN oublié → authentification du téléphone. Le PIN ne protège ni ne dérive aucune clé (D4) |
| 5 | Modèle de données local | ✅ testé | profil, faits, projets, sections, historique, progression, copies de conflit, `sync_meta` ; marquage atomique ; identifiants déterministes. **Schéma v1 non figé** |
| 6 | Authentification | 🟡 code + tests unitaires | e-mail / mot de passe via Supabase ; session dans le Keystore. **Jamais exécutée contre un serveur.** Google et téléphone : non faits |
| 7 | Supabase de développement | 🟡 partiel | `env/example.json` (valeurs factices), `env/*.json` ignorés par Git, test d'absence de secrets. **Projet cloud de développement non créé** ; `supabase/config.toml` non généré ; variantes d'app dev/prod non créées |
| 8 | Modèle serveur minimal | 🟡 testé partiellement | 1 migration : appareils, enregistrements chiffrés, têtes de sync, enveloppe de récupération ; RLS ; fonctions RPC. 46 assertions SQL vertes sur PostgreSQL 16 avec `auth` simulé ; **pas sur la pile Supabase** (Docker indisponible) ; aucun schéma de production |
| 9 | Synchronisation | ✅ testé (faux serveur) | pull puis push, idempotente, 3 familles de conflits, aucune horloge utilisée. Déclencheurs (réseau, WorkManager) **non faits** |
| 10 | Migration invité → compte | ✅ testé (faux serveur) | nouveau compte (code affiché une fois), compte existant (code demandé), refus d'un autre compte |
| 11 | Tests de reprise, interruption, réseau, conflits | ✅ 12 scénarios sur 14, 2 partiels | OFFLINE_SYNC §13.1 |

Tests : **229 automatiques, tous verts** + 46 assertions SQL.

**Non fait ou NON VÉRIFIÉ en Phase 2** (à ne pas considérer comme livré) :

- build Android (jamais exécuté) et donc : Keystore réel, biométrie réelle,
  `FlutterFragmentActivity`, binaires natifs sqlite3mc et libsodium dans
  l'APK ;
- tout appel à un vrai Supabase (authentification, RPC, RLS sur la pile
  Supabase, format `amr` de la réauthentification) ;
- mesures sur appareil : Argon2id (3 × 64 Mio), ouverture de la base,
  sync de 5 000 éléments ;
- connexion Google et téléphone ; transfert double QR (Phase 5) ;
  suppression de compte (Edge Function) ;
- déclencheurs de sync, effacement local après révocation, purge de la
  corbeille après 30 jours, écran des copies de conflit, resynchronisation
  complète des enregistrements illisibles ;
- les services ouverts au démarrage ne sont encore utilisés par aucun
  écran ; les réglages (thème, langue) restent en mémoire ;
- mentions de licences natives dans l'app ; vérification minisign de
  libsodium en CI ;
- toutes les chaînes malagasy ajoutées sont « à relire ».

**Conditions d'acceptation de la Phase 2** (restent ouvertes) : build
Android réel, tests et mesures sur appareils A et B (P7), projet Supabase
de développement + tests sur la pile Supabase (P4), avis juridique mineurs
avant l'onboarding des mineurs (P6), relecture malagasy (P9).

## Phases suivantes

Ordre du cahier des charges conservé, avec deux ajustements déjà présentés :
socle de sync (`sync_meta`, enveloppes) et format de contenu (signature,
règles) posés en Phase 2.

| Phase | Contenu | Critères de sortie |
|---|---|---|
| **1 — Design system** | tokens clair/sombre, composants (boutons, cartes, champs, progression, badges, navigation adaptative, modales, états loading/error/offline, bloc d'aide anti-blocage), `AdaptiveScaffold`, go_router (shell 5 onglets, sans faux contenu), Riverpod, logger expurgé, `EripooFormatter` (mg/fr/en), inventaire des chaînes Material visibles | tests de widget clair/sombre × 2 tailles × 3 langues, `meetsGuideline`, aucune couleur ni chaîne littérale hors tokens/ARB (CI), test sur appareil de référence |
| **2 — Onboarding + diagnostic + socle données** | Drift chiffré (sqlite3mc), `sync_meta`, `CryptoService` libsodium avec vecteurs de test, UMK/DBK + Keystore, format de contenu + `ContentLocalizer` + règles + validateur + signature, pack `diagnostic`, choix de langue (mg présélectionné), profil invité, projet, Supabase (migrations, RLS, `user_keys` via RPC, `devices`, `security_events`, `profiles`, `consents`), comptes e-mail/Google/téléphone, code de récupération et fiche de secours, migration invité → compte, mentions de licences natives, vérification minisign de libsodium en CI | onboarding + diagnostic hors ligne ; migration sans perte ; mesures Argon2id et ouverture de base sur appareil de référence ; tests pgTAP RLS ; tests d'intégration |
| **3 — Ma quête** | planificateur, exécuteur d'étapes générique, missions, progression, anti-blocage, premières quêtes relues | parcours de bout en bout hors ligne |
| **4 — Projet** | sections, historique, observations, interviews, hypothèses → décisions, preuves, médias chiffrés | machine d'états testée exhaustivement |
| **5 — Offline + sync** | RPC, moteur, conflits, corbeille, médias, WorkManager, **transfert double QR**, révocation | 14 scénarios d'OFFLINE_SYNC §13 + scénarios de transfert (§6.7 de SECURITY) |
| **6 — Outils** | déblocage progressif | — |
| **7 — Finance, business model, documents** | calculateurs, canvas, dossier, export PDF | calculs testés aux limites |
| **8 — Formalisation Madagascar** | contenu réglementaire sourcé et daté | 100 % des informations sourcées |
| **9 — Voix + IA limitée** | transcription optionnelle, proxy IA, consentements | rien n'est envoyé sans consentement |
| **10 — Production** | **rotation de l'UMK**, localisation Material/Cupertino `mg`, budgets de performance, revue cryptographique externe, audit sécurité, accessibilité, validation juridique, back-office | checklist de release complète |

## Décisions

### Recommandées de façon définitive (sous réserve de votre validation)

| # | Décision |
|---|---|
| V1 | Stack Flutter / Riverpod / go_router / Drift / Supabase |
| V2 | Offline-first, base locale source de vérité |
| V3 | Chiffrement de bout en bout : le personnel (administrateurs Supabase et Eripoo) ne peut pas déchiffrer |
| V4 | Trois secrets distincts ; clé de données jamais dérivée du mot de passe |
| V5 | libsodium (via `sodium`) pour toute la cryptographie applicative ; Android Keystore via `flutter_secure_storage` ; SQLite3MultipleCiphers pour la base (licence MIT vérifiée) |
| V6 | Code de récupération à **haute entropie** (36 chiffres, 116 bits) ; **pas de PIN** ; aucun vérificateur côté serveur |
| V7 | Argon2id (3 passes, 64 Mio, sel de 16 octets par enveloppe) — valeurs à confirmer par mesure, planchers 2 passes / 32 Mio |
| V8 | Transfert entre appareils par double QR hors ligne ; limite de 5 appareils actifs |
| V9 | Synchronisation interne simplifiée (v2) |
| V10 | Contenu, missions, règles et traductions séparés de l'interface ; packs signés |
| V11 | Malagasy langue native ; localisation propre du contenu |

### Encore ouvertes

| # | Décision | Recommandation | Bloque |
|---|---|---|---|
| ~~D2~~ | **Décidée le 2026-10-06 : récupération sans séquestre** (voir Portes) | — | — |
| ~~D4~~ | **Décidée le 2026-10-06 : verrou facultatif**, chiffrement toujours actif (voir Portes) | — | — |
| **D5** | Contenu en YAML dans le dépôt jusqu'à la Phase 6 | oui | Phase 3 |
| **D6** | Identifiant Android définitif (domaine possédé) | à fixer avant la création de l'app dans la Play Console | publication |
| **D7** | Analytics opt-in, sans identifiant, auto-hébergés | oui | Phase 2 (onboarding) |
| **D8** | Rapports de crash maison | oui au départ | — |
| **D9** | Région Supabase | après mesures depuis Madagascar et avis juridique (ARCHITECTURE §14) | création du projet Supabase de production (un projet de développement peut être créé avant) |
| **D10** | Fournisseur SMS (OTP) | après test de délivrabilité et de coût | connexion par téléphone |
| **D11** | Appareils de référence | voir P7 : au minimum catégories A et B, idéalement A à E | acceptation de la Phase 2 |
| **D12** | Analyse juridique (mineurs, loi 2014-038, transferts hors de Madagascar) | volet mineurs avant la Phase 2 | Phase 2 (onboarding des mineurs) |
| **D13** | Relecteurs natifs malagasy | dès la Phase 1 | — (améliore la Phase 1) |
| **D14** | Langue de rédaction du contenu | co-rédaction mg + fr par des auteurs natifs | Phase 3 |
| **D15** | Plafond de 10 Mo par média | oui | Phase 4 |
| **D17** | Rotation de l'UMK avant le lancement public | oui (Phase 10) | lancement public |

## Portes

### Phase 1 — ACCEPTÉE (2026-10-06)

### Phase 2 — GO donné le 2026-10-06, en cours

Décisions du porteur (2026-10-06) :

- **D2 — récupération sans séquestre : ACCEPTÉE.** Récupération uniquement
  par le code conservé par l'utilisateur et par le double QR ; aucune copie
  de la clé de données déchiffrable par Eripoo ; aucun mécanisme de
  récupération par le support. Risque accepté explicitement : si
  l'utilisateur perd tous ses appareils **et** son code, Eripoo ne peut ni
  récupérer ni déchiffrer son projet. L'UX doit le dire **simplement, sans
  ton anxiogène ni technique** : le code est essentiel et Eripoo ne peut pas
  le remplacer.
- **D4 — verrou Eripoo facultatif.** Deux couches distinctes : (1)
  chiffrement des données **toujours actif**, indépendant du verrou ; (2)
  verrou d'accès à l'application, désactivable, par PIN local et biométrie
  quand elle est disponible, avec délai configurable. Le verrou ne remplace
  jamais le chiffrement ; **le PIN n'est ni une clé maîtresse ni une source
  de dérivation de la clé de données** (SECURITY §4.4).
- **Supabase — trois environnements séparés : ACCEPTÉ** (local,
  staging/développement cloud, production) avec les contraintes de P4.
- **Région de production : non choisie** (P5 reste ouvert).

Ordre de travail imposé : stockage local → chiffrement local → gestion des
clés → verrou → modèle de données local → authentification → environnement
Supabase de développement → modèle serveur minimal → synchronisation →
migration invité → compte → tests de reprise, interruption, réseau et
conflits.

Hors périmètre de la Phase 2 : contenu pédagogique définitif, moteur
adaptatif complet, onboarding final, analytics de production, SMS de
production, région de production, données réelles.

**Restent explicitement OUVERTS** (le démarrage de la Phase 2 ne les résout
pas) :

- [ ] avis juridique mineurs 14–17 (P6)
- [ ] transferts de données hors de Madagascar (P6)
- [ ] région de production (P5)
- [ ] tests sur appareils A et B (P7)
- [ ] relecture native du malagasy (P9)
- [ ] validation réelle du build Android
- [ ] mesures de performance d'Argon2id (et ouverture de la base chiffrée) sur appareil
- [ ] validation finale de SQLite3MultipleCiphers dans notre distribution (build Android réel + mentions de licences validées)

## Pré-requis Phase 2

### Invariants (non négociables, inchangés)

Aucune décision de cette liste ne peut remettre en cause :

- aucune cryptographie maison ;
- aucune donnée de projet privée en clair côté serveur ;
- aucun accès administrateur au contenu privé ;
- aucune donnée de projet envoyée à un modèle d'IA (les fonctions IA de la
  Phase 9 restent soumises à un consentement explicite par usage et ne
  font pas partie de la Phase 2) ;
- aucune clé secrète dans Git ;
- aucun secret de production dans l'application ;
- aucun contenu utilisateur dans les journaux.

### Niveaux de blocage

| Niveau | Signification |
|---|---|
| 🔴 | bloque le **démarrage** de la Phase 2 |
| 🟠 | ne bloque pas le démarrage, mais bloque une partie de la Phase 2 ou son **acceptation** |
| 🟡 | bloque la **production** (publication, vrais utilisateurs), pas la Phase 2 |
| 🟢 | levé |

### Récapitulatif

| # | Point | Niveau | Statut | Valide |
|---|---|---|---|---|
| P1 | D2 — risque de perte de clé, modèle de récupération | 🟢 | **décidé : sans séquestre (2026-10-06)** | porteur du projet |
| P2 | D4 — verrou applicatif et base locale chiffrée | 🟢 | **décidé : chiffrement toujours actif, verrou facultatif (2026-10-06)** | porteur du projet |
| P3 | Licence de SQLite3MultipleCiphers | 🟢 (technique) / 🟡 (mentions validées) | **vérifiée : MIT sur l'étiquette v2.5.0** | Claude (fait) ; juriste pour la liste des mentions |
| P4 | Environnements Supabase (local / dev-staging / production) et projet de développement | 🟢 stratégie · 🟠 projet cloud | stratégie validée (2026-10-06) ; projet cloud à créer | porteur du projet (propriétaire du compte Supabase) |
| P5 | D9 — région Supabase de production | 🟡 | ouvert | porteur + juriste |
| P6 | D12 — cadre juridique (mineurs 14–17, transferts, loi 2014-038) | 🟠 | ouvert | juriste qualifié en droit malgache (+ protection des données UE si hébergement UE) |
| P7 | D11 — appareils Android de référence | 🟠 | **aucun appareil disponible — tout NON VÉRIFIÉ** | porteur (achat) ; mesures par l'équipe |
| P8 | Paramètres de production à ne pas figer prématurément | 🟢 pour démarrer · 🟡 pour la production | liste établie | porteur + équipe technique |
| P9 | D13 — relecture native du malagasy | 🟠 | **aucune chaîne relue** (hors nom et slogan) | relecteur(s) malagasy natif(s) |
| P10 | Palette et design system sur appareils réels | 🟡 | **NON VÉRIFIÉ** | porteur + utilisateurs cibles |

---

### P1 — D2 : risque de perte de clé et modèle de récupération 🔴

| | |
|---|---|
| **Décision** | Accepter l'option A ([SECURITY §9](SECURITY.md#9-décision-d1d2--niveau-de-garantie)) : récupération uniquement par le code de récupération (36 chiffres) ou par transfert double QR depuis un appareil autorisé ; **pas de séquestre** chez Eripoo. Conséquence assumée : si l'utilisateur perd tous ses appareils **et** son code, la copie en ligne de son projet est illisible pour tout le monde. |
| **Pourquoi** | C'est la contrepartie directe de la garantie « aucun administrateur ne peut lire les projets ». Le choix détermine ce qui est construit en Phase 2 (création du code, fiche de secours, saisie, vérification). |
| **Conséquence technique** | Option A : table `user_keys` avec une seule enveloppe (code) ; aucun service de séquestre ; écrans de création, sauvegarde, confirmation et rappel du code. L'architecture cryptographique n'est **pas** modifiée. |
| **Preuve de validation** | (1) Accord écrit du porteur (réponse explicite « D2 = A accepté »). (2) Pendant la Phase 2, test d'utilisabilité avec au moins 5 personnes du public cible : sauvegarde du code sur la fiche, puis ressaisie quelques jours plus tard ; résultat consigné. Ce test valide l'UX, pas la décision. |
| **Valideur** | Porteur du projet. |
| **Si la décision change plus tard** | Passer à B (séquestre à double contrôle) : **ajout sans migration** (une enveloppe supplémentaire de la même clé), mais la promesse de confidentialité affichée doit changer et être annoncée. Passer à C (pas de chiffrement de bout en bout) : **refonte majeure** (modèle serveur, sync, sécurité) — à exclure. |

### P2 — D4 : verrou applicatif et base locale chiffrée 🔴

| | |
|---|---|
| **Décision** | (a) Confirmer le chiffrement de la base locale (SQLite3MultipleCiphers, clé aléatoire protégée par le Keystore) — déjà recommandé. (b) Choisir pour le verrou Eripoo (PIN ou biométrie) : **optionnel**, proposé à l'onboarding et fortement suggéré si le téléphone n'a pas de verrouillage d'écran (recommandation) — ou obligatoire. |
| **Pourquoi** | Téléphones souvent partagés en famille ; sans verrouillage d'écran ni verrou Eripoo, quiconque ouvre l'app voit le projet ([SECURITY §2.2](SECURITY.md#22-ce-que-larchitecture-ne-peut-pas-protéger)). Un verrou obligatoire protège mieux mais ajoute une étape pour un public peu familier du numérique. |
| **Conséquence technique** | (a) Format de la base fixé dès la Phase 2. (b) Optionnel : clés du Keystore créées sans exigence d'authentification ; à l'activation du verrou, elles sont **ré-enveloppées** par une clé liée à l'authentification (`setUserAuthenticationRequired`). Obligatoire : liaison dès le premier lancement. Ajout de la dépendance `local_auth` (justification à documenter). Aucune modification de l'architecture cryptographique. |
| **Preuve de validation** | Accord écrit du porteur sur (a) et (b). Puis, en Phase 2 : test automatisé d'activation/désactivation du verrou sans perte de données ; mesure du temps d'ouverture de la base chiffrée sur l'appareil A (P7) — **NON VÉRIFIÉ** tant que l'appareil n'existe pas. |
| **Valideur** | Porteur du projet (choix UX) ; équipe technique (mesures). |
| **Si la décision change plus tard** | Optionnel → obligatoire : migration locale (ré-enveloppe des clés) + changement d'UX, coût modéré. Abandon du chiffrement de la base après des données réelles : migration de toutes les bases locales et perte de protection — déconseillé. |

### P3 — Licence de SQLite3MultipleCiphers 🟢 / 🟡

| | |
|---|---|
| **Décision** | Utiliser SQLite3MultipleCiphers pour chiffrer la base locale. |
| **Pourquoi** | Distribution gratuite sur le Play Store : la licence doit le permettre et ses obligations (mentions) doivent être respectées. |
| **Conséquence technique** | Écran « Licences » de l'app avec les mentions des bibliothèques natives (enregistrées via `LicenseRegistry`, Phase 2). |
| **Preuve de validation** | **Fait le 2026-10-06** : fichiers `LICENSE` (« MIT License ») et `LICENSE.spdx` (`PackageLicenseDeclared: MIT`) lus sur l'**étiquette v2.5.0** du dépôt amont, version livrée par `sqlite3` depuis la 3.5.1 (journal des modifications vérifié) ; composants inclus permissifs, dont SHA-2 sous licence BSD (mention de copyright à reproduire). Reste : la liste finale des mentions (libsodium ISC, `sodium` BSD-3, sqlite3mc MIT + BSD SHA-2, SQLite domaine public, `flutter_secure_storage` BSD-3…) est à faire valider avec P6. |
| **Valideur** | Vérification technique : faite. Liste des mentions : juriste (P6). |
| **Si la décision change plus tard** | Si une future version changeait de licence : rester sur la dernière version MIT ou passer à SQLCipher (même mécanisme `source: sqlcipher`), au prix d'un re-chiffrement des bases locales. |

### P4 — Environnements Supabase et projet de développement 🔴 / 🟠

| | |
|---|---|
| **Décision** | Valider la séparation en trois environnements ci-dessous, et créer le projet Supabase **de développement** (compte et organisation du porteur). |
| **Pourquoi** | La Phase 2 crée les premières tables, règles d'accès (RLS) et fonctions. Elles doivent être testées sans jamais toucher de vraies données ni exposer de secret. |
| **Conséquence technique** | Migrations SQL versionnées dans `supabase/migrations/`, appliquées à l'identique dans les trois environnements ; **aucun schéma de production créé en Phase 2** ; configuration de l'app par fichiers `env/*.json` non versionnés (seul `env/example.json` avec des valeurs factices sera versionné) ; deux variantes d'app distinctes (`dev` et production, identifiants différents) pour qu'une build de développement ne parle jamais à la production. |
| **Preuve de validation** | Stratégie : accord écrit du porteur. Local : `supabase start` + migrations + tests pgTAP verts (en CI au minimum). Dev : projet créé, migrations appliquées par la CI, tests d'intégration verts, **analyse de secrets du dépôt** (recherche de jetons/clés) sans résultat. |
| **Valideur** | Porteur du projet (création du projet, propriété du compte, facturation) ; équipe technique (tests). |
| **Si la décision change plus tard** | Faible : les migrations rejouent le schéma partout. Le coût n'apparaît que si des secrets ont fuité (rotation) ou si dev et prod ont été mélangés — d'où la séparation dès maintenant. |

**Les trois environnements :**

| | Local | Développement / staging | Production |
|---|---|---|---|
| Où | Supabase CLI sur le poste du développeur et en CI | projet cloud `eripoo-dev` (un `eripoo-staging` pourra s'ajouter avant la production) | projet cloud `eripoo-prod` — **pas créé avant P5 et P6** |
| Données | synthétiques uniquement (données de démonstration) | comptes de test et données synthétiques ; **effaçables à tout moment** | vrais utilisateurs |
| Schéma | migrations rejouées depuis zéro | mêmes migrations, appliquées par la CI | mêmes migrations, appliquées par le pipeline de release après revue ; aucune modification manuelle |
| Clés | clés locales générées par la CLI (non sensibles, jamais versionnées) | clé `anon` dans `env/dev.json` local non versionné ; clé `service_role` uniquement dans les secrets Supabase / GitHub | clé `anon` injectée au build par la CI depuis un environnement GitHub protégé ; `service_role` uniquement dans les secrets des Edge Functions ; MFA, 2 personnes max |
| Authentification | e-mail (boîte de test locale) | e-mail, Google (client OAuth de test), téléphone (numéros de test, sans SMS réels) | fournisseurs réels (après D10) |
| Clé de signature du contenu | clé de développement | clé de développement | clé de production conservée hors ligne |
| Région | — | sans importance (aucune donnée réelle) ; idéalement une région candidate, pour mesurer la latence | décision D9 (P5) |

⚠️ **Constat sur l'environnement de développement de Claude** : le client
Docker est installé mais le démon ne tourne pas, ce qui empêche
`supabase start` ici à ce jour. Options, par ordre de préférence : exécuter
les tests Supabase (RLS, pgTAP) **en CI GitHub** où Docker est disponible ;
tenter de démarrer Docker dans la session ; à défaut, tests SQL partiels sur
PostgreSQL 16 avec un schéma `auth` simulé, **signalés comme partiels**.

### P5 — D9 : région Supabase de production 🟡

| | |
|---|---|
| **Décision** | Choisir la région du projet de production parmi les candidates d'[ARCHITECTURE §14](ARCHITECTURE.md#14-région-dhébergement-supabase) (présélection pour mesures : Paris, Francfort ; Mumbai en témoin). |
| **Pourquoi** | Une région ne peut pas être changée simplement après création ; elle détermine le cadre juridique de l'hébergement et la latence. |
| **Conséquence technique** | Aucune pour la Phase 2 (le projet de développement n'engage rien). Pour la production : URL du projet, coûts, base légale du transfert hors de Madagascar. |
| **Preuve de validation** | Rapport de mesures depuis Madagascar (≥ 100 mesures par région, 3 opérateurs mobiles + Wi-Fi, Antananarivo + une ville de province, médiane et 95ᵉ centile) ; avis juridique sur le transfert (P6) ; comparaison tarifaire. |
| **Valideur** | Porteur du projet, sur avis du juriste. |
| **Si la décision change plus tard** | Élevé après lancement : nouveau projet, migration des comptes et des données chiffrées, interruption de service. |

### P6 — D12 : cadre juridique 🟠

| | |
|---|---|
| **Décision** | Faire établir par un juriste les règles applicables, notamment : application de la loi n° 2014-038 et formalités auprès de la CMIL ; **mineurs de 14 à 17 ans** (âge à partir duquel un mineur peut consentir seul, forme et vérification du consentement parental) ; **transferts de données hors de Madagascar** (base légale selon la région, P5) ; données de tiers (personnes interviewées, enregistrements audio) ; politique de confidentialité et conditions d'utilisation ; durées de conservation ; notification de violation ; mentions de licences (P3) ; responsabilité liée aux informations réglementaires du contenu. |
| **Pourquoi** | Eripoo vise un public dès 14 ans et héberge des données hors de Madagascar. Le cahier des charges interdit de supposer une réglementation sans source fiable. |
| **Conséquence technique** | Valeurs de la table `jurisdiction_policies` (âge minimum, seuil de consentement parental) et `legal_validated = true` ; flux de consentement parental (conçu après l'avis) ; textes juridiques en mg/fr/en ; durées de rétention. **Aucune valeur juridique n'est codée en dur** : la Phase 2 peut construire le mécanisme configurable avant l'avis. |
| **Preuve de validation** | Note juridique écrite et datée, référencée dans la documentation ; valeurs saisies dans `jurisdiction_policies` avec leur source ; textes relus par le juriste. |
| **Valideur** | Juriste qualifié en droit malgache (et en protection des données UE si hébergement UE). |
| **Ce qui reste bloqué sans avis** | Acceptation du flux d'âge et de consentement parental de la Phase 2 ; **toute mise entre les mains de vrais mineurs** ; la production. Le socle technique de la Phase 2 peut avancer. |
| **Si la décision change plus tard** | Modéré tant que les règles restent des données (table, textes). Élevé si l'avis impose une localisation des données à Madagascar (aucune région Supabase n'y existe : changement d'hébergeur). |

### P7 — D11 : appareils Android de référence 🟠 — NON VÉRIFIÉ

| | |
|---|---|
| **Décision** | Acquérir (ou emprunter) des appareils physiques, au minimum des catégories **A et B**, idéalement A à E, achetés localement si possible. |
| **Pourquoi** | Les performances (Argon2id, ouverture de la base chiffrée, démarrage, défilement), l'affichage et l'accessibilité ne peuvent pas être validés sur émulateur ou en tests automatisés seuls. |
| **Conséquence technique** | Paramètres Argon2id et `kdf_iter` de la base fixés d'après les mesures (P8) ; budgets de performance mesurés ; ajustements éventuels du design. |
| **Preuve de validation** | Fiche de mesures par appareil (`docs/DEVICE_TESTS.md`, créée en Phase 2) : modèle, version d'Android, RAM, résultats chiffrés et date. |
| **Valideur** | Porteur (acquisition) ; équipe technique (mesures). |
| **Si la décision change plus tard** | Tester tard expose à revoir des paramètres déjà en production (Argon2id : seulement pour les nouvelles enveloppes ; base : re-chiffrement) et à découvrir des problèmes d'affichage après lancement. |

| Cat. | Profil | Pourquoi | Tests prévus | Statut |
|---|---|---|---|---|
| **A** | Ancien entrée de gamme : Android 7.0–8.1 (API 24–27), **1 Go de RAM**, processeur 32 bits (armeabi-v7a, sans accélération AES), écran ~5" 720×1280 (≈ 360 × 640 dp), 8–16 Go de stockage presque plein | plancher technique (minSdk 24), cas le plus contraint | démarrage à froid, ouverture de la base chiffrée, Argon2id 64 Mio (et plancher 32 Mio), mémoire, défilement, blocages (ANR) | **NON VÉRIFIÉ** |
| **B** | Récent bas de gamme : Android 13–15 (édition Go si possible), 2–3 Go, arm64, écran ~6,5" HD+ (≈ 360–393 dp de large) | profil probable de nombreux nouveaux utilisateurs (à confirmer avec des données du marché malgache, non étudiées) | mêmes mesures ; luminosité en extérieur | **NON VÉRIFIÉ** |
| **C** | Milieu de gamme récent : Android 15–16, 4–6 Go, arm64, ≈ 393–412 dp, écran OLED | Android récent, thème sombre sur OLED, lecteur d'écran | TalkBack, police à 200 %, thème sombre, pages mémoire de 16 Ko | **NON VÉRIFIÉ** |
| **D** | Tablette 8–10", Android 13+, ≥ 600 dp | navigation latérale, colonne de lecture | portrait et paysage | **NON VÉRIFIÉ** |
| **E** | Grand écran sous **Android 16** (tablette ou pliable) | vérifier que le verrouillage portrait est bien ignoré et que tout s'adapte | rotation, redimensionnement, multi-fenêtre | **NON VÉRIFIÉ** |

Complément (pas un substitut) : émulateurs API 24 et API 36 dans la CI pour
les tests d'intégration.

### P8 — Paramètres de production à ne pas figer prématurément 🟢 / 🟡

| | |
|---|---|
| **Décision** | Reconnaître que les valeurs ci-dessous sont **provisoires** en Phase 2 et fixer, pour chacune, le moment où elle sera figée. Toutes les données de développement sont jetables. |
| **Pourquoi** | Figer trop tôt (sans mesures, sans avis juridique) crée des migrations coûteuses ; figer trop tard (après les premières données réelles) aussi. |
| **Conséquence technique** | Les valeurs vivent dans des constantes de configuration documentées ou des tables serveur, jamais dispersées dans le code ; les formats chiffrés portent un numéro de version dès la v1. |
| **Preuve de validation** | Avant la production : chaque ligne du tableau marquée « figée » avec sa valeur, sa justification (mesure, avis) et sa date. |
| **Valideur** | Porteur + équipe technique (+ juriste pour les durées de conservation et l'âge). |
| **Si la décision change plus tard** | Voir la colonne « modifiable après données réelles ». |

| Paramètre | Valeur actuelle (proposée) | Où il vit | Modifiable après données réelles ? | À figer |
|---|---|---|---|---|
| Identifiant Android (D6) | `mg.eripoo.eripoo` (provisoire) | Gradle | **non** après création dans la Play Console | avant création Play |
| Région Supabase (D9) | — | projet | très coûteux | avant production (P5) |
| Formats chiffrés v1 (enveloppes, données associées, enveloppe de clé, QR) | SECURITY §4 | dans chaque donnée | oui par nouvelle version (lecture N et N-1), coûteux | avant les premières données réelles |
| Argon2id | 3 passes, 64 Mio | stocké avec chaque enveloppe | oui pour les nouvelles enveloppes | après mesures P7 |
| Base locale : schéma de chiffrement | ChaCha20-Poly1305, clé brute (pas de dérivation) | appareil | oui, par re-chiffrement de la base | avant production |
| Limite d'appareils actifs | 5 | serveur | oui | avant production |
| Limites de téléchargement de l'enveloppe | 5/heure, 20/jour | serveur | oui | avant production |
| Taille maximale d'un média (D15) | 10 Mo | app + serveur | oui (à la hausse) | Phase 4 |
| Lots de synchronisation | 50 éléments / 256 Ko ; lecture par 200 | app + serveur | oui | après mesures réseau |
| Durées de conservation | corbeille 30 j, analytics 90 j, événements de sécurité 90 j | serveur / app | oui | avec P6 |
| Âge minimum, seuil de consentement parental | **aucune valeur** | `jurisdiction_policies` | oui (données) | P6 |
| Clé de signature du contenu | clé de développement | hors ligne / CI | rotation possible, nécessite une mise à jour de l'app | avant production |
| Fournisseur SMS (D10) | — | Supabase Auth | oui | avant d'activer le téléphone |
| Palette et tailles de texte | DESIGN_SYSTEM §2 | tokens | oui | après P10 |

### P9 — D13 : relecture native du malagasy 🟠

| | |
|---|---|
| **Décision** | Désigner au moins un relecteur malagasy natif (idéalement deux, dont une personne proche du public cible) pour l'interface, les formats (mois, jours, durées), puis le contenu ; choisir le vocabulaire de référence (glossaire : « quête », « hypothèse », « preuve »…). |
| **Pourquoi** | Le malagasy est la langue native du produit ; des traductions non relues nuisent à la compréhension, surtout pour un public peu scolarisé. |
| **Conséquence technique** | Aucune sur l'architecture ; mises à jour des fichiers ARB et de `lib/l10n/mg_review_status.json`. |
| **Preuve de validation** | Statut `reviewed` (= validé) pour chaque clé dans `mg_review_status.json`, avec nom du relecteur et date consignés ; test automatique existant qui oblige à suivre chaque clé. |
| **Valideur** | Relecteur(s) natif(s) ; arbitrage terminologique par le porteur. |
| **Ce qui reste bloqué sans relecture** | Tests avec de vrais utilisateurs en malagasy ; acceptation des écrans d'onboarding de la Phase 2. |
| **Si la décision change plus tard** | Faible techniquement (textes séparés du code) ; élevé pour l'expérience si des utilisateurs ont appris un vocabulaire qui change. |

**Statut actuel des textes (aucun n'est considéré comme définitif) :**

| Statut | Signification | Textes concernés |
|---|---|---|
| **Validé** | fourni ou confirmé par le porteur | `appTitle` (« Eripoo »), `slogan` (« Mihary ho an'ny ho avy. ») |
| **Proposition — à relire par un locuteur natif** | rédigé par Claude, sans relecture native | les 27 autres chaînes malagasy (navigation, états, aide, progression, badges, boutons) ; noms des mois et jours et l'unité « ora » de `EripooFormatter` |
| **Proposition — à valider par le porteur** | rédigé par Claude en français et en anglais | toutes les chaînes fr et en hors nom et slogan (ton, tutoiement, vocabulaire) |

Dans `mg_review_status.json`, `reviewed` correspond à « validé » et
`needs_review` à « proposition à relire ».

### P10 — Palette et design system sur appareils réels 🟡 — NON VÉRIFIÉ

| | |
|---|---|
| **Décision** | Valider (ou ajuster) la palette, les tailles de texte et les composants après essai sur appareils réels et avec des utilisateurs cibles. |
| **Pourquoi** | Les contrastes sont calculés et testés, mais les écrans bon marché (angles de vue, luminosité faible), l'usage en plein soleil et la perception réelle ne sont pas vérifiables en test automatisé. |
| **Conséquence technique** | Ajustement éventuel des tokens uniquement ; les tests de contraste et la matrice d'accessibilité empêchent toute régression. |
| **Preuve de validation** | Séance d'essai documentée sur les appareils A, B et D (intérieur, extérieur en plein jour, luminosité minimale, thème sombre, TalkBack, police à 200 %) + retours d'au moins 5 utilisateurs cibles ; captures jointes. |
| **Valideur** | Porteur du projet (et designer si disponible). |
| **Si la décision change plus tard** | Faible : changer un token met à jour toute l'app ; les tests vérifient automatiquement le contraste. |

### Autres décisions ouvertes à prendre pendant la Phase 2

- **D7** — analytics opt-in sans identifiant : nécessaire pour l'écran de
  consentement de l'onboarding.
- **D10** — fournisseur SMS : sans lui, la Phase 2 livre l'e-mail et Google ;
  la connexion par téléphone reste désactivée.
- **D6** — identifiant Android : seulement avant la création dans la Play
  Console.

### Ordre recommandé pour lever les blocages

1. ✅ **P3** — licence vérifiée (fait).
2. **P1 et P2** — décisions du porteur (D2, D4) : rapides, sans dépendance.
3. **P4** — accord sur les trois environnements, puis création du projet
   Supabase de développement par le porteur ; tests Supabase en CI.
4. **P6** — engager le juriste **dès maintenant** (délai le plus long),
   d'abord sur les mineurs 14–17 et les transferts.
5. **P7** — acquérir les appareils A et B (délai d'achat), puis C, D, E.
6. **P9** — recruter le ou les relecteurs malagasy ; relire les 27 chaînes
   existantes et le glossaire avant d'écrire l'onboarding.
7. D7 et D10 pendant la Phase 2.
8. **P5** — mesures de latence depuis Madagascar, puis choix de la région
   (avant la production).
9. **P8 et P10** — figer les paramètres et valider le design avant la
   production.

### Condition de GO Phase 2

- [x] P1 — D2 accepté par écrit (2026-10-06)
- [x] P2 — D4 décidé par écrit : verrou facultatif (2026-10-06)
- [x] P3 — licence vérifiée
- [x] P4 — stratégie des trois environnements validée (2026-10-06) ;
      projet cloud de développement à créer par le porteur
- [x] GO explicite du porteur (2026-10-06)

Points qui **ne bloquent pas le démarrage** mais bloquent l'acceptation de
la Phase 2 : P6 (volet mineurs), P7 (mesures A et B), P9 (onboarding
malagasy).
