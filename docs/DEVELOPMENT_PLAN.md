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
| Projet Flutter Android (Flutter 3.47.6, minSdk 24) | ✅ créé — identifiant `com.eripoo.app` **définitif** (D6, 2026-10-22) |
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

## Phase 2 — Socle sécurité, données et synchronisation (EN VALIDATION, non acceptée)

Les 11 étapes dans l'ordre imposé, puis une validation réelle demandée le
2026-10-06 (CI, Android, Supabase). Légende : **auto** = test automatique
(machine de développement ou CI) ; **émulateur** = émulateur Android de la
CI (pas un téléphone) ; **Supabase local** = vraie pile Supabase (Auth,
PostgREST, Postgres) lancée par la CLI en CI — pas le projet cloud.

| # | Étape | État | Détail |
|---|---|---|---|
| 1 | Stockage local | ✅ auto + émulateur | Drift, base dans le stockage privé ; ouverte au démarrage (11–27 ms sur émulateur) |
| 2 | Chiffrement local | ✅ auto + émulateur | SQLite3MultipleCiphers 2.5.0, ChaCha20-Poly1305, clé brute `raw:` ; fichier sans en-tête SQLite ni texte clair ; mauvaise clé refusée ; fichiers temporaires en mémoire |
| 3 | Gestion des clés | ✅ auto + émulateur | Keystore Android (clé RSA-OAEP enveloppant une clé AES-GCM, **corrigé** : voir échecs), `resetOnError: false` ; clés perdues → écran simple ; effacement complet testé |
| 4 | Verrou applicatif | ✅ auto + émulateur (PIN) | PIN, mauvais PIN, reverrouillage au retour, redémarrage verrouillé : vérifiés sur Android 8 et 14. **Biométrie : non testée** (émulateur sans empreinte) |
| 5 | Modèle de données local | ✅ auto | **schéma v1 non figé** |
| 6 | Authentification | 🟡 | inscription / connexion e-mail via la bibliothèque Supabase **vérifiées sur Supabase local** (tests de contrat) ; notre `SupabaseAuthRepository` lui-même n'y est pas encore exécuté ; Google et téléphone non faits |
| 7 | Supabase de développement | 🟡 | pile **locale** versionnée (`supabase/config.toml`) et testée en CI ; **projet cloud de développement non créé** (compte du porteur nécessaire) ; variantes d'app dev/prod non créées |
| 8 | Modèle serveur minimal | ✅ auto + Supabase local | 2 migrations (schéma + liaison session/appareil) ; RLS ; **60 assertions SQL** vertes sur PostgreSQL 16 et sur Supabase local ; aucun schéma de production |
| 9 | Synchronisation | ✅ auto + Supabase local + émulateur | contrat RPC identique sur faux serveur et Supabase local ; 5 000 éléments (CI) ; 1 000 sur émulateur. Déclencheurs automatiques **non faits** |
| 10 | Migration invité → compte | ✅ auto | provisoire : le 2ᵉ appareil passe par le code de récupération (SECURITY §6.0), le double QR arrive en Phase 5 |
| 11 | Reprise, interruption, réseau, conflits | ✅ 14/14 scénarios | OFFLINE_SYNC §13.1 (révocation et 5 000 éléments complétés) |

### Validation Phase 2 (2026-10-06)

Pull request de validation :
[nrazafindravonjy-cmd/eripoo#1](https://github.com/nrazafindravonjy-cmd/eripoo/pull/1),
CI **entièrement verte aux runs 12 et 14** (le run 14 porte le code final), 6 jobs :

| Job | Contenu | Résultat |
|---|---|---|
| Format, analyse, tests | `dart format`, `flutter analyze`, 253 tests (dont 5 000 éléments, révocation, fuite de données, contrat RPC sur faux serveur) | ✅ |
| PostgreSQL + `auth` simulé | 60 assertions SQL | ✅ |
| Supabase local | mêmes 60 assertions + 13 tests de contrat RPC par HTTP avec de vrais comptes (fictifs) | ✅ |
| Build Android | APK debug produit (182 764 352 octets, artefact `eripoo-debug-apk`) ; APK release x86_64 produit (23,1 Mo) dans les jobs émulateur | ✅ |
| Émulateur Android 8.0, « 1 Go » (1,5 Go réels) | démarrage à froid, effacement des données, 5 tests d'intégration | ✅ 5/5 |
| Émulateur Android 14, 2 Go | idem | ✅ 5/5 |

Mesures : [DEVICE_TESTS.md](DEVICE_TESTS.md) (Android),
[OFFLINE_SYNC §13.2](OFFLINE_SYNC.md) (5 000 éléments),
[SECURITY §4.8](SECURITY.md) (Argon2id : décision provisoire et règle de
choix sur A/B).

**Échecs trouvés pendant la validation, tous corrigés** :

| # | Trouvé par | Défaut | Correction |
|---|---|---|---|
| 1 | contrat RPC sur Supabase local | PostgreSQL renvoie le base64 avec un saut de ligne tous les 76 caractères ; le client les refusait : **aucune enveloppe de plus de 57 octets ne pouvait être relue depuis le vrai serveur** (invisible avec le faux serveur) | décodage tolérant + test |
| 2 | test 5 000 éléments en CI (échec seulement sur machine rapide) | après une coupure réseau, chaque élément du lot recevait un délai de 15 s ; les cycles suivants l'ignoraient et se déclaraient **« complets » avec 50 modifications en attente** | une coupure laisse le lot en attente ; « complet » exige `pendingLeft == 0` ; test déterministe |
| 3 | émulateur Android 8 | le stockage sécurisé était configuré en mode biométrique : **plantage au premier lancement sur Android 7–8** (minSdk 24) et demande d'authentification au démarrage sur Android 9+ verrouillé | configuration par défaut (RSA-OAEP + AES-GCM) ; règle d'architecture |
| 4 | analyse de la révocation | une session d'un appareil révoqué pouvait enregistrer un nouvel identifiant et continuer à synchroniser | session liée à l'appareil, supprimée à la révocation, refusée partout (migration `20261007000001`) |
| 5 | règle « données de test fictives » | une adresse `@example.mg` (domaine potentiellement réel) dans un test | `@example.com` |
| 6 | relecture | mes rapports annonçaient 46 assertions SQL ; il y en avait 52 (60 aujourd'hui) | documents corrigés |
| 7–9 | CI | disque insuffisant pour l'émulateur ; mémoire saturée (Gradle 8 Go + émulateur) ; test du verrou n'attendant pas la vérification du PIN en arrière-plan ; mesure du gel sur l'isolat principal lue à 0 | job émulateur corrigé ; test corrigé ; mesure corrigée (run 14 : gel de 146–184 ms si Argon2id tournait sur l'interface, ≤ 4 ms en arrière-plan) |

**Non vérifié** (ne pas considérer comme livré) :

- **téléphones réels A et B** : aucune mesure ; l'émulateur « 1 Go » avait
  1,5 Go ; aucun processeur ARM (A : 32 bits) testé ; Keystore matériel,
  biométrie réelle ;
- **projet Supabase de développement en ligne** : non créé ; latence depuis
  Madagascar non mesurée ;
- notre dépôt d'authentification exécuté contre Supabase ; Google, téléphone ;
- absence de gel d'interface avec 5 000 éléments sur appareil ;
- intégrité de l'archive libsodium compilée au build par le paquet
  `sodium` (constaté dans le journal du build, vérification non faite) ;
- mentions de licences natives dans l'app.

**Restent volontairement ouverts** (inchangés par la validation ; liste complète de fin de projet : [END_CHECKLIST.md](END_CHECKLIST.md)) :

- [ ] avis juridique mineurs 14–17 (P6)
- [ ] transferts de données hors de Madagascar (P6)
- [ ] région Supabase de production (P5)
- [ ] relecture native du malagasy (P9)
- [ ] appareils de référence A et B, puis appareils supplémentaires C–E (P7)
- [ ] validation finale de la licence de SQLite3MultipleCiphers dans le contexte complet de distribution (mentions dans l'app, juriste)
- [ ] suppression de compte (Edge Function)
- [x] transfert multi-appareil par double QR — fait en Phase 5 (appareils réels non vérifiés)
- [x] synchronisation automatique (déclencheurs, WorkManager) — faite en Phase 5 (WorkManager non vérifié sur appareil)
- [x] corbeille : purge après 30 jours — faite en Phase 5
- [x] écran de résolution des copies de conflit — fait en Phase 5

**Conditions d'acceptation de la Phase 2** : mesures sur appareils A et B
(et choix définitif d'Argon2id), projet Supabase de développement créé et
suite de contrat passée dessus, relecture malagasy, avis juridique mineurs
avant l'onboarding des mineurs.

## Phase 3 — Ma quête (LIVRÉE POUR REVUE, non acceptée)

GO donné le 2026-10-06 (« GO PHASE 3. ON REVIENDRA SUR LE TEST A LA
FIN ») : les tests réels de la Phase 2 (appareils A/B, projet Supabase de
développement) sont **reportés à la fin**, ils ne sont pas faits.

| Élément | État | Détail |
|---|---|---|
| Format de contenu | ✅ auto | `lib/content/` (Dart pur) : pack, quêtes, étapes, 7 types de blocs, missions ; lecteur JSON strict (clé inconnue = erreur) ; textes `LocalizedText` mg/fr/en avec statut de relecture ; repli mg→fr→en, fr→mg→en, en→fr→mg |
| Langage de règles | ✅ auto | `all`, `any`, `not`, faits (`eq`, `ne`, `in`, `gte`, `lte`, `exists`), étape, quête, mission, compteurs (sur statuts, jamais sur du texte), `days_since` ; aucune évaluation de code |
| Validateur de contenu | ✅ auto + CI | références, valeurs de faits, ≤ 5 questions d'affilée, synthèse en fin d'étape de réflexion, sorties issues de questions, **jamais de fait tiré d'un texte libre**, avance rapide sans sauter de livrable, texte français obligatoire |
| Compilation du contenu | ✅ CI | YAML dans `content/` (D5) → `assets/content/base_pack.json` par `tool/content_build.dart` ; étape CI `--check` : pack valide et à jour |
| Planificateur | ✅ auto | statuts `locked`/`available`/`in_progress`/`deferred`/`postponed`/`fast_tracked`/`completed`, raison du verrou, prochaine action recommandée, avance rapide (seule la sortie est demandée), étapes passées qui réapparaissent ; **le parcours s'ouvre après le diagnostic** (qui crée le projet) |
| Données (schéma v2) | ✅ auto | `answers`, `mission_instances`, `step_progress.deferred_until` ; migration v1 → v2 testée sur base chiffrée ; synchronisées comme les autres entités (enveloppes chiffrées) |
| Exécuteur d'étape + anti-blocage | ✅ auto | un bloc par écran ; « Je ne sais pas » (fait `unknown`), « Je ne comprends pas » (reformulation 1 puis 2), exemple, indices progressifs, « bloqué » après 2 aides ; « Passer pour l'instant » / « Revenir plus tard » (sauf dans le diagnostic) |
| Missions | ✅ auto | proposée → acceptée → remise → accomplie, abandon confirmé, reprise ; complétion par règle de contenu facultative |
| Écrans | ✅ auto | bienvenue (langue, mg présélectionné), Accueil (prochaine action, missions en cours), Ma quête (liste, détail), étape générique, mission ; autres onglets : « Pas encore disponible » |
| Contenu | 🟡 brouillon | diagnostic (8 écrans), 3 quêtes (problème, clients, solution), 2 missions de terrain ; **aucun texte relu par une personne** (voir D14) |
| Parcours de bout en bout hors ligne | ✅ auto + émulateur | test de widget avec les vrais écrans et le vrai contenu : bienvenue → diagnostic → projet nommé → quête 1 avec mission → quête 2 débloquée → redémarrage, avec interdiction de toute connexion réseau. Sur émulateurs Android 8 et 14 (base chiffrée réelle, pack lu dans l'APK) : bienvenue → diagnostic → première étape → redémarrage, **réussi sur les deux** (CI run 23, commit 7c97b55). Mesures : DEVICE_TESTS §2bis |
| Appareils A et B | ❌ NON VÉRIFIÉ | reporté à la fin (décision du porteur) |

Décisions appliquées ou précisées pendant la Phase 3 :

- **D5 appliquée** : contenu en YAML dans le dépôt ; le JSON embarqué est
  un produit de compilation vérifié en CI.
- **D14 — toujours ouverte.** Les textes ont été rédigés pour la Phase 3
  sans auteurs natifs : le français est la référence mais **n'est pas
  relu** (`needs_review`), le malagasy est un **premier jet**
  (`machine_draft`) à réécrire par des auteurs natifs, l'anglais est à
  relire. Statut par défaut posé dans `content/pack.yaml`, appliqué à chaque
  texte par l'outil de compilation, vérifié par un test ; l'app affiche une
  mention discrète sur ces écrans. Le critère « premières quêtes relues »
  du plan n'est donc **pas rempli**.
- **Profil d'entrée** : demandé directement (`diag.entry_profile`) au lieu
  d'être dérivé par règle (PRODUCT_ARCHITECTURE §2) : les faits dérivés
  n'existent pas encore ; plus simple, même résultat pour les règles.
- **Titre provisoire** : « Je ne sais pas » au nom du projet crée le projet
  avec le titre « Mon projet » (dans la langue de l'interface), modifiable
  plus tard (Phase 4).

Reporté (hors Phase 3, rien de commencé) : signature des packs (le pack
embarqué est couvert par la signature de l'APK ; obligatoire avant tout
pack téléchargé), audio et médias (Phase 4/9), rappels et notifications
locales, badges, outils, édition du projet (Phase 4), refaire le
diagnostic, migrations d'identifiants de contenu (`renamed`/`retired`).

Points ouverts de la Phase 3 :

- [ ] relecture native malagasy et relecture du français et de l'anglais du contenu (D13/D14)
- [ ] parcours sur appareils A et B (lisibilité, rythme, compréhension) — NON VÉRIFIÉ
- [ ] avis d'entrepreneurs malgaches sur les exemples et les missions — NON VÉRIFIÉ
- [ ] 16 quêtes minimum (3 écrites en Phase 3, 4 après la Phase 4)

## Phase 4 — Projet (LIVRÉE POUR REVUE, non acceptée)

GO donné le 2026-10-07 (« si les éléments en attente ne gênent pas la
phase 4 lance-la »). Analyse faite avant de commencer : les points en
attente (relecture du contenu, appareils A/B, projet Supabase cloud) ne
bloquent pas la Phase 4 ; **un seul la limite** : l'avis juridique P6 sur
les données de tiers. En conséquence, **aucun enregistrement audio des
personnes rencontrées** : les rencontres sont des notes écrites sous
pseudonyme, sans nom ni numéro de téléphone.

| Élément | État | Détail |
|---|---|---|
| Machines d'états | ✅ auto (critère de sortie) | hypothèse (7 statuts) et expérience (4 statuts) : **les 49 + 16 paires** (de, vers) testées contre une table écrite indépendamment, chaque décision × chaque statut (35 cas), chaque règle ; **300 marches aléatoires** de 25 opérations vérifiant les invariants après chaque opération |
| Règles métier | ✅ auto | critère de réussite défini avant le test et **verrouillé au démarrage** ; « confirmée » / « infirmée » exigent au moins un résultat **et** une preuve, « pas de réponse claire » un résultat ; aucune modification en place après un test (nouvelle version liée) ; journal des décisions en ajout seul |
| Décisions | ✅ auto | continuer, modifier (nouvelle version liée), tester davantage, abandonner, revenir en arrière (rouvre l'étape source de la quête) |
| Données (schéma v3) | ✅ auto | hypothèses, expériences et leurs liens, résultats, preuves, conclusions, décisions, observations, rencontres, métadonnées des médias ; synchronisées chiffrées comme le reste ; migration v2 → v3 testée sur base chiffrée |
| Photos chiffrées | ✅ auto + émulateur | chiffrées en mémoire avec la sous-clé médias (format SECURITY §4.7, libsodium), **jamais en clair sur le disque** (vérifié octet par octet), 10 Mo maximum (D15), fichiers orphelins purgés au démarrage, **effacés avec les données locales** (réinitialisation, révocation : test ajouté). Copie temporaire du sélecteur photo lue puis supprimée. Émulateurs (run 30) : photo de 300 Ko chiffrée en 39 ms, interface jamais bloquée plus de 19 ms ; **un fichier de 10 Mo bloque l'interface ≈ 0,7 s** (voir DEVICE_TESTS §2ter) |
| Écrans | ✅ auto | Projet (sections du contenu, modification avec « Avant / Maintenant »), Hypothèses (liste, formulaire avec gabarit), fiche d'une hypothèse (tests, résultats « 7 sur 10 », preuves note / photo / lien / chiffre / vente, conclusion avec confiance avant → après, décisions, versions), Carnet de terrain (observations, rencontres) |
| Lien avec la quête | ✅ auto | les règles de contenu comptent hypothèses, tests, preuves, observations et rencontres **par statut ou type, jamais par texte** ; quête 4 « Tester ta première hypothèse » |
| Contenu | 🟡 brouillon | schémas des sections et quête 4 : non relus (D14), comme en Phase 3 |
| Appareils A et B | ❌ NON VÉRIFIÉ | reporté à la fin |

Écarts avec DATA_MODEL / PRODUCT_ARCHITECTURE, décidés pendant la phase :

- « Tester davantage » mène à « à tester » (un nouveau test, avec son
  critère fixé avant, est nécessaire), ou directement à « en test » si un
  test tourne déjà. Un test annulé renvoie à « à tester » une hypothèse
  qu'il était seul à tester. Abandonner n'est possible qu'avant ou entre
  deux tests ; une hypothèse confirmée ou infirmée reste un résultat.
- Résultats : `metric_yes` / `metric_total` au lieu d'un JSON libre.
- Photos d'une observation : rattachées comme preuves (pas de colonne
  photo dédiée). Pas de colonnes audio ni transcription (Phase 9 et P6).
- Empreinte des médias : BLAKE2b-256 (`crypto_generichash` de libsodium)
  au lieu de SHA-256, que la bibliothèque n'expose pas.

Points ouverts de la Phase 4 :

- [x] chiffrer les gros fichiers hors du fil de l'interface (≈ 0,7 s de gel pour 10 Mo) — fait en Phase 5 (isolat) : gel mesuré à 84 ms (API 26) et 92 ms (API 34) sur émulateur
- [ ] avis juridique P6 (données de tiers, enregistrements) avant tout enregistrement d'une rencontre
- [ ] relecture des textes des sections et de la quête 4 (D14)
- [ ] appareils A et B — NON VÉRIFIÉ

Reporté (rien de commencé) : audio et documents comme preuves, segments
clients, concurrents, finances (Phase 7), édition et suppression des
preuves, envoi des fichiers médias au serveur (Phase 5), calcul de la
maturité et du niveau de préparation par règles.

## Phase 5 — Offline + sync (LIVRÉE POUR REVUE, non acceptée)

GO donné le 2026-10-07 (« GO PHASE 5 »). Les tests sur appareils réels A/B
et sur le projet Supabase de développement en ligne restent reportés à la
fin (le projet n'existe pas encore).

| Élément | État | Détail |
|---|---|---|
| Transfert double QR — protocole | ✅ auto (critère de sortie) | QR1/QR2, code à 6 chiffres, `tid`, clé jetable en mémoire seulement, détruite après 5 min (temps monotone), à l'annulation et **après toute tentative d'ouverture** ; chaque ligne de SECURITY §6.5 testée (QR2 photographié, faux QR1, autre compte, mauvais `tid`, mauvais code) |
| Transfert — interruptions §6.7 | ✅ auto (critère de sortie) | avant le scan, application fermée après le scan, réseau coupé en fin de transfert (clé gardée en mémoire, nouvel essai sans rescanner), appareil enregistré mais clé non stockée (refait, compté une fois), clé stockée puis arrêt brutal avant le rechiffrement des photos ; refus : clé qui n'ouvre pas les données du compte, 5 appareils, téléphone d'un autre compte, ancien téléphone non lié |
| Transfert — écrans | ✅ auto (widget, deux téléphones simulés) — ❌ caméra réelle NON VÉRIFIÉE | nouveau téléphone (QR1 + code + compte à rebours, lecture de QR2, vérification, redémarrage) ; ancien téléphone (confirmation par le verrouillage du téléphone, avertissement anti-hameçonnage, code faux refusé, QR2 affiché 2 min puis effacé). `FLAG_SECURE` sur les écrans de clé et de code (canal natif, non vérifié sur appareil). Lecture des QR en Dart pur (zxing2) : image de caméra simulée 640×480 avec bruit et pas de ligne, décodée exactement |
| Changement de clé de données | ✅ auto | **défaut trouvé** : après une récupération par code (Phase 2) ou un transfert, les photos locales restaient chiffrées avec l'ancienne sous-clé, donc illisibles. L'ancienne clé est désormais gardée le temps de rechiffrer les photos au démarrage, puis effacée |
| Serveur | ✅ SQL (17 assertions) + contrat sur Supabase local (run 34) | `list_devices` (métadonnées, jamais la session), bucket Storage privé `user-media` (`{owner}/{media_id}` seulement, 10 Mo + enveloppe, écriture unique, refus pour la session d'un appareil retiré) ; colonne `session_id` des appareils plus lisible directement |
| Synchronisation automatique | ✅ auto | démarrage, retour au premier plan, retour du réseau, 5 s après une modification, toutes les 5 min au premier plan ; réessais 5 s / 15 s / 1 min / 5 min / 15 min / 1 h ± 20 % ; jamais deux cycles à la fois. **Défaut corrigé** : le cycle périodique contournait l'attente après échec |
| WorkManager | 🟡 compilé (APK CI), ❌ exécution NON VÉRIFIÉE | tâche toutes les heures environ, réseau requis ; même cycle qu'au premier plan ; jamais lancée sur émulateur ni appareil |
| Médias | ✅ auto + contrat Supabase local | photos envoyées après leurs métadonnées, rechiffrées pour le compte (jamais le fichier local tel quel), **en Wi-Fi seulement** sauf réglage ; récupérées à la demande et vérifiées par leur empreinte ; coupures et refus gérés |
| Gros fichiers hors du fil de l'interface | ✅ auto + émulateur | ≥ 1 Mo : chiffrement et déchiffrement sur un isolat (point ouvert de la Phase 4) ; gel à 10 Mo : 84 ms (API 26), 92 ms (API 34), contre ≈ 0,7 s avant (DEVICE_TESTS §2quater) |
| Scénario 12 (version future) | ✅ auto | après mise à jour, les enregistrements écartés sont retirés et appliqués (curseur ramené au premier écarté) |
| Corbeille 30 jours | ✅ auto + widget | supprimer (avec « Annuler »), remettre, supprimer pour de bon (pierre tombale sans contenu ; ligne locale effacée après confirmation du serveur), purge automatique après 30 jours ; une restauration sur un autre téléphone l'emporte sur une suppression définitive. Photos : fichier gardé chiffré dans la corbeille, effacé avec sa copie serveur ensuite |
| Copies de conflit | ✅ auto + widget | écran « Versions à vérifier » : garder la version actuelle ou l'autre ; le choix se synchronise, la copie reste dans l'historique |
| Valeurs effacées à distance | ✅ auto | **défaut trouvé** : un champ vidé sur un téléphone (restauration, note effacée) n'était jamais vidé sur les autres (Drift ignorait les `null`) |
| Profil | ✅ widget ; ❌ connexion Supabase réelle NON VÉRIFIÉE | compte (serveur de développement seulement ; sinon message clair), code de secours montré une fois et vérifié, second téléphone par code ou par QR, état de la sauvegarde, « Mes appareils » (retrait avec mot de passe redemandé si nécessaire), corbeille |
| Appareils A et B, projet Supabase en ligne | ❌ NON VÉRIFIÉ | reportés à la fin |

Couverture des 14 scénarios : OFFLINE_SYNC §13.4.

Écarts avec SECURITY §6, décidés pendant la phase (détail : SECURITY
§6.10) : indice de compte = 8 premiers octets d'un BLAKE2b de 16 octets
(libsodium refuse 8) ; l'ancien téléphone n'annonce pas le nouveau au
serveur (pas d'enregistrement « en attente ») ; le nouveau s'enregistre
**avant** de stocker la clé, puis la vérifie sur les données du compte (un
compte encore vide n'a rien pour la vérifier : clé acceptée, risque
résiduel documenté) ; la confirmation d'identité utilise le verrouillage
du téléphone, pas encore le verrou Eripoo.

Dépendances ajoutées (licences vérifiées sur pub.dev) : `workmanager`
0.10.10 (MIT), `connectivity_plus` 7.3.2 (BSD-3), `camera` 0.12.1
(BSD-3, flutter.dev), `zxing2` 0.2.4 (BSD-3), `qr` 4.0.0 (BSD-3),
`fake_async` (tests). Pourquoi pas `mobile_scanner` : il s'appuie sur
Google ML Kit, qui envoie des métriques d'usage à Google et dépend des
services Play ; la lecture en Dart pur est plus lente mais reste sur le
téléphone. Les permissions micro et stockage partagé déclarées par le
module caméra sont retirées ; la caméra est facultative.

Points ouverts de la Phase 5 :

- [ ] lecture des QR avec une vraie caméra, `FLAG_SECURE` et WorkManager sur appareils A et B — NON VÉRIFIÉ
- [ ] connexion, transfert et médias contre le projet Supabase de développement en ligne (à créer par le porteur)
- [ ] notification « Nouvel appareil ajouté » aux autres appareils et par e-mail (SECURITY §6.8) — non faite (l'événement est enregistré côté serveur)
- [ ] déconnexion avec effacement local et suppression de compte — non faites
- [ ] quota de stockage des médias par utilisateur — non appliqué
- [ ] confirmation d'identité par le verrou Eripoo quand le téléphone n'a pas de verrouillage
- [ ] relecture native des nouveaux textes malagasy (≈ 110 chaînes, statut `needs_review`)

## Phase 6 — Outils : déverrouillage progressif (LIVRÉE POUR REVUE, non acceptée)

GO donné le 2026-10-07 (« go phase 6 s'il n'y a rien qui bloque ») : aucun
point en attente des Phases 2 à 5 ne la bloquait (ils concernent les
appareils réels, le projet Supabase en ligne et des avis extérieurs).

| Élément | État | Détail |
|---|---|---|
| Catalogue des 14 outils (§20) | ✅ auto | `content/tools.yaml`, dans l'ordre du cahier des charges : résumé, aide lisible **avant** le déblocage, règle de déblocage, indice en clair. Validateur : identifiants et genres uniques, règles vérifiées (quêtes, compteurs), indice obligatoire, sections obligatoires pour le guide d'interview |
| Déblocage progressif | ✅ auto | règles sur **ce que l'utilisateur a fait** (quêtes, observations, interviews, hypothèses, expériences terminées, hypothèses validées, concurrents), jamais sur le simple fait d'avoir lu (§21). Évalué à chaque changement des données lues par les règles, où que soit l'utilisateur |
| Déblocage définitif et synchronisé | ✅ auto (deux téléphones simulés) | table `tool_unlocks` (schéma v6) ; identifiant UUID v5 du nom de l'outil, donc un seul enregistrement si deux téléphones débloquent hors ligne ; fusion : date la plus ancienne, jamais reverrouillé, sans copie de conflit. Défaire le travail (mettre une observation à la corbeille) ne reverrouille pas |
| Outils utilisables (5) | ✅ widget | journal d'observation et hypothèses / expériences (écrans de la Phase 4), **guide d'interview** (nouveau, contenu : avant, questions, à éviter, après ; « n'enregistre personne », avis juridique P6), **analyse concurrentielle** (nouvelle : direct / indirect / ce que les gens font sans acheter, offre, prix observé en ariary, forces, manques ; table `competitors` v6, synchronisée, corbeille avec « Annuler ») |
| Outils annoncés (9) | ✅ widget — **non construits, annoncés comme tels** | Business Model Canvas, calculateurs de prix / marge / seuil de rentabilité, plan marketing, business plan, pitch, pitch deck → **Phase 7** ; préparation administrative → **Phase 8** (contenu réglementaire sourcé). Ils se débloquent quand même (« Débloqué : il sera là dès qu'il existera ») mais ne s'ouvrent pas : aucune imitation |
| Onglet Outils | ✅ widget | trois parties : « Tes outils », « À débloquer » (indice + aide), « Bientôt ». Pastille sur l'onglet tant qu'un outil débloqué n'a pas été vu. Le dernier écran provisoire de la Phase 1 disparaît |
| Célébration | ✅ widget | message court à l'ouverture de l'onglet (« Nouvel outil débloqué — grâce à ce que tu as fait : … »), montré **une fois** sur l'ensemble des téléphones (`seen_at` synchronisé) ; **désactivable** dans Profil > Préférences ; sans classement ni série |
| Badges (§21) | ⏸️ non faits | hors du périmètre de la phase « Outils » ; à prévoir avec les règles déjà en place (même langage, même validateur) |
| Contenu | 🟡 brouillon | français et anglais à relire, malagasy en premier jet machine (`machine_draft`) ; 31 nouvelles chaînes d'interface `needs_review` |

Choix et limites :

- Les règles de déblocage sont des **propositions** à valider avec les
  auteurs du contenu (D14) ; elles se changent dans `content/tools.yaml`
  sans toucher au code, et le validateur refuse une règle incohérente.
- Un outil débloqué reste débloqué même si le contenu change plus tard.
- Pas d'analyse concurrentielle « notée » ni de score : l'outil sert à
  écrire ce qu'on a vu, pas à juger.

Points ouverts de la Phase 6 :

- [ ] relecture des règles de déblocage et des textes des outils par les auteurs (D14)
- [ ] relecture native du malagasy (contenu des outils + 31 chaînes)
- [ ] badges (§21) : à planifier
- [x] outils annoncés de la Phase 7 (finance, canvas, documents) — faits en Phase 7 ; la préparation administrative reste pour la Phase 8

## Phase 7 — Finance, business model, documents (LIVRÉE POUR REVUE, non acceptée)

GO donné le 2026-10-07 (« go next phase s'il n'y a rien de bloquant ») :
aucun point en attente ne bloquait. Le contenu réglementaire et les
organismes de financement, qui demandent des sources, restent hors de la
phase (Phase 8) ; rien n'est inventé à leur place.

| Élément | État | Détail |
|---|---|---|
| Calculs (critère de sortie) | ✅ testés aux limites | prix depuis une marge sur le prix de vente (arrondi au-dessus : la marge n'est jamais sous l'objectif, vérifié sur des milliers de cas), marge et ajout sur le coût, seuil de rentabilité mensuel (impossible, nul, hors de portée), trésorerie sur 12 mois avec montée des ventes, besoin de financement, mois pour récupérer l'achat de départ. Entiers en ariary et points de base, **aucun nombre à virgule** ; bornes (10¹¹ Ar, 10⁶ ventes/mois, 200 montants par genre) qui interdisent tout dépassement, testées au maximum |
| Données v7 | ✅ auto (deux téléphones simulés) | `finance_items` (coût d'une unité, frais du mois, achats de départ, argent trouvé avec sa source), `finance_plans` (prix et ventes prévues, un par projet) ; synchronisés chiffrés, corbeille, conflit = une version + une copie |
| « Mes chiffres » | ✅ widget | montants par genre, prix et ventes, ce que disent les chiffres en une phrase chacun ; ce qui manque est nommé au lieu d'être deviné ; trésorerie mois par mois ; rappel : un calcul ne prédit pas la réussite (§22) |
| Calculateurs (3) | ✅ widget | prix, marge, seuil : pré-remplis avec les chiffres du projet tant que la case n'est pas touchée, libres pour essayer, résultat annoncé au lecteur d'écran ; le prix peut être gardé pour le projet et est comparé aux prix vus chez les concurrents |
| Guide de financement | ✅ contenu | genres d'argent (économies, proches, microfinance, banque, investisseurs, concours, incubateurs) et questions à poser avant d'emprunter ; **aucun organisme ni taux** (à sourcer et dater) |
| Business Model Canvas | ✅ auto + widget | construit **uniquement** depuis le travail (sections, hypothèses validées, chiffres) ; les cases construites d'abord, puis « Encore à construire » avec l'endroit où le faire ; une case se complète depuis le canvas |
| Sections amenées par les outils | ✅ widget | modèle économique, plan marketing, pitch, résumé du projet, lancement : apparaissent avec leur outil (ou dès qu'elles contiennent quelque chose), jamais en cases vides d'avance |
| Dossier (business plan) | ✅ auto + widget | 11 chapitres ; chaque phrase est le texte de l'utilisateur ou un nombre calculé ; un chapitre vide dit où le construire ; aucun bouton ne l'écrit à sa place (§15) |
| Plan marketing, pitch | ✅ widget | sections écrites avec l'aide de l'outil ; durée du pitch à voix haute estimée (≈ 130 mots par minute) |
| Pitch deck | ✅ auto + widget | une couverture puis une diapositive par idée qui a du contenu |
| Export PDF | ✅ auto + widget — ❌ partage réel NON VÉRIFIÉ | avertissement « en clair » avant tout fichier, construction sur un autre isolat avec la police embarquée, partage par le menu Android, fichier effacé ensuite, purge au démarrage (SECURITY §11.1) |
| Outils | ✅ | 13 sur 14 s'ouvrent ; la préparation administrative reste annoncée (Phase 8) |
| Contenu | 🟡 brouillon | fr/en à relire, mg en premier jet ; 100 nouvelles chaînes d'interface `needs_review` |

Écarts et choix :

- **Un seul plan de prix par projet** au lieu de la table `price_scenarios`
  (DATA_MODEL v7) : les calculateurs permettent d'essayer d'autres
  nombres sans rien enregistrer ; plusieurs scénarios n'apportaient rien
  aux calculs demandés.
- **Pas de chapitre « Marché » ni « Formalisation »** : aucune quête ne
  recueille encore de données de marché, et la formalisation est la
  Phase 8. Ils ne sont pas simulés.
- **`qr` ramené de 4.0.0 à 3.0.2** : `pdf` dépend de `barcode`, qui exige
  `qr` 3. Le QR produit est identique (tests du codec inchangés).
- **Police Roboto embarquée** (≈ 340 Ko) : sans elle, les PDF ne
  montrent pas tous les caractères (espaces fines, guillemets).
- Le niveau de préparation (§23, « éventuellement ») et l'aide à la
  recherche d'associés (§48) ne sont pas faits.

Points ouverts de la Phase 7 :

- [ ] partage réel du PDF et lisibilité des calculateurs sur A et B — NON VÉRIFIÉ
- [ ] organismes et conditions de financement sourcés et datés (avec la Phase 8)
- [ ] relecture des textes (sections amenées par les outils, guide de financement) et des 100 chaînes malagasy
- [ ] chapitre « Marché » du dossier (« Formalisation » fait en Phase 8)
- [ ] niveau de préparation (§23), associés (§48), badges (§21)

## Phase 8 — Formalisation Madagascar (LIVRÉE POUR REVUE, non acceptée)

GO donné le 2026-10-08 (« si rien ne bloque la phase 8 lance le »). Un
blocage a d'abord été signalé : le réseau de l'environnement refusait les
sites officiels malgaches. Après l'ouverture de l'accès à internet par le
porteur, l'EDBM et l'INSTAT répondent ; `impots.mg` et `cnaps.mg` ne
répondent pas, l'Assemblée nationale refuse la connexion, et la
plateforme Orinasa a cessé de répondre (DNS) pendant la collecte.

| Élément | État | Détail |
|---|---|---|
| Format « sourcé et daté » (critère de sortie : 100 % sourcé) | ✅ auto | `content/formalization.yaml` : sources officielles (éditeur, titre, version, URL https, date de lecture, empreinte sha256), chaque fait, pièce et frais renvoie à une source **et** à l'endroit dans la source ; les conseils d'Eripoo sont séparés et n'énoncent aucune règle ; date de revue (2027-01-08) ; relecture juridique « en attente ». Le build refuse une source inconnue ou jamais citée, une référence sans endroit, une adresse http, des dates incohérentes |
| Contenu | ✅ sourcé — 🟡 non relu par un juriste ; 27 nouvelles chaînes d'interface et le contenu mg en premier jet | lu le 8 octobre 2026, **EDBM uniquement** : « Création de société, Version 28 : Juillet 2026 » (pièces, frais, documents délivrés, services, horaires, adresse), la page « Création de société », les modèles officiels de statuts SARL et SARLU. Où et comment, formes de société (SARL, SARLU et responsabilité de l'associé unique), ce que l'on reçoit, l'impôt au démarrage, 13 pièces à préparer |
| Écarté volontairement | — | tout ce qui vient de sites secondaires (contradictoires : capital minimum, nombre d'exemplaires, l'un affirmant à tort que Madagascar applique l'OHADA) ; **aucun capital minimum** n'est affiché ; l'entreprise individuelle est déclarée « pas encore couverte par une source officielle vérifiée » |
| Estimation des frais | ✅ testée aux limites | barème EDBM lu dans le contenu (statuts 0,5 % min. 20 000 Ar, bail 2 % du loyer total min. 20 000 Ar, procuration 2 000 Ar, RCS 16 000 Ar, STAT 40 000 Ar, impôt synthétique selon l'activité) ; entiers, arrondi au-dessus, minimums ; le simulateur officiel et le guichet font foi |
| Outil « Préparation administrative » | ✅ widget | avertissement daté (« lues le 8 octobre 2026… pas encore relues par un juriste », « plus de trois mois » après la date de revue), informations recueillies (section du projet), sujets avec la source de chaque phrase, pièces à cocher (synchronisées), estimation gardée, liste des sources, export PDF. **Eripoo ne fait aucune démarche** et le dit |
| Dossier | ✅ auto | chapitre « Formalisation » (informations recueillies, pièces prêtes) |
| Vérification des sources | ✅ outil | `dart run tool/check_sources.dart` télécharge les documents et compare leur empreinte (réseau nécessaire, hors CI) ; dernière exécution : 3 documents identiques |
| Outils | ✅ | les 14 outils de la spécification s'ouvrent ; plus aucun n'est annoncé « Bientôt » |

Points ouverts de la Phase 8 :

- [ ] **relecture par un juriste malgache** du contenu réglementaire (fr, puis mg et en) avant publication
- [ ] entreprise individuelle : liste officielle des pièces et des frais (Orinasa « Documents par forme juridique », non lisible pendant la collecte)
- [ ] autres régions que l'Analamanga (antennes de l'EDBM, services présents) — non couvertes
- [ ] sources fiscales et sociales directes (`impots.mg`, `cnaps.mg`) — sites injoignables pendant la collecte
- [ ] relire les sources tous les trois mois (`tool/check_sources.dart`), et à chaque loi de finances
- [ ] code d'activité (NOMAC) : non repris

## Phase 9 — Voix + IA limitée (LIVRÉE POUR REVUE, non acceptée)

GO donné le 2026-10-08 (« si rien ne bloque pour la phase 9, procede »).
Une règle du porteur cadre toute la phase : **aucune donnée de projet
privée n'est envoyée à un modèle d'IA externe**. Aucun moteur de
transcription sur l'appareil n'a été retenu à ce stade (taille des modèles,
qualité en malagasy non mesurée) : la transcription n'est donc **pas**
livrée, et aucune IA n'est branchée.

| Élément | État | Détail |
|---|---|---|
| Réponse orale (§25) | ✅ widget + unitaires | aux questions ouvertes du parcours (sauf le nom du projet) : « Répondre à l'oral » ; autorisation du micro demandée au premier enregistrement ; minuteur, arrêt automatique à 3 minutes, « Arrêter et garder », « Annuler » ; écoute, « Enregistrer à nouveau », « Supprimer et écrire plutôt » (confirmation) |
| Hors ligne, chiffré | ✅ | enregistrement AAC mono 16 kHz 32 kbit/s (`record`), fichier temporaire dans le cache privé, chiffré aussitôt dans le magasin de médias (`kind = audio`, synchronisé et envoyé comme une photo), fichier en clair effacé dans tous les cas ; lecture (`just_audio`) depuis une copie temporaire effacée après écoute ; dossier temporaire vidé à chaque démarrage |
| Pas de transcription | ✅ dit à l'écran | « Fonctionne sans connexion… Elle n'est pas écrite dans ton projet (pas de transcription automatique) : tu pourras l'écrire plus tard. » La réponse orale complète l'étape mais n'est jamais recopiée dans les sections, ni dans les faits, ni dans le titre du projet ; la synthèse de l'étape affiche « Réponse orale (pas écrite dans le projet) » |
| Remplacement, suppression | ✅ | un enregistrement remplacé, une réponse orale remplacée par un texte ou par « Je ne sais pas », ou supprimée : effacé pour toujours (`TrashService.purgeMedia`, fichier, envoi en attente, suppression côté serveur) ; une réponse supprimée est reposée |
| Entretiens | — non proposé | aucune captation audio des personnes interrogées (avis juridique P6 en attente) |
| Points à revoir (§24 « détection d'incohérences ») | ✅ unitaires + widget | **règles fixes, sans IA** : prix sans coût unitaire, prix sous le coût, aucune marge avec des charges, seuil au-dessus des ventes prévues au mois 12, argent manquant pour la trésorerie, preuve du pitch sans hypothèse validée, solution sans client. Entrée « N points à revoir » sur l'écran Projet (cachée s'il n'y en a pas), chaque point expliqué avec les chiffres de l'utilisateur et un bouton « Revoir » vers l'écran concerné |
| Fournisseur d'IA remplaçable (§24) | ✅ | `AiAssistant` : un seul point de branchement, implémentation par défaut `DisabledAiAssistant` (rien n'est envoyé) ; aucune dépendance réseau d'IA dans l'application |
| Chaînes | 🟡 | 30 nouvelles chaînes, mg en premier jet (à relire) |

Points ouverts de la Phase 9 :

- [ ] essai du micro et de la lecture sur appareils réels A et B (autorisation, refus, appel entrant pendant l'enregistrement, écran éteint, place disque faible)
- [ ] transcription : choisir entre une transcription **sur l'appareil** (modèle embarqué, à mesurer en malagasy, en taille et sur appareil A) ou rien ; un service externe n'est possible que pour du texte que l'utilisateur choisit d'envoyer, après un écran de consentement explicite — décision du porteur
- [ ] fournisseur d'IA (si un jour) : décision du porteur, consentement, région, contrat, pas d'entraînement sur les données
- [ ] réponse orale lors des entretiens : seulement après l'avis juridique P6
- [ ] l'écoute d'une réponse orale enregistrée sur un autre téléphone attend que le fichier soit reçu (même règle que les photos)

## Phase 10 — Optimisation, sécurité, accessibilité, production (LIVRÉE POUR REVUE, non acceptée)

Demande du porteur le 2026-10-08 (« construis la phase 10 »). Ce qui
dépend de la production ou d'acteurs extérieurs n'est **pas** fait et ne
peut pas l'être ici : environnement de production (non créé, sur
décision), revue cryptographique externe, audit de sécurité par un tiers,
validation juridique, back-office (décision D5), publication Play.
Critère de sortie : la [checklist de release](RELEASE_CHECKLIST.md) existe
et tout ce qui peut être automatisé l'est ; la release elle-même reste
bloquée par ses points ouverts.

| Élément | État | Détail |
|---|---|---|
| **Rotation de l'UMK** (D17) | ✅ unitaires + deux appareils + widget + SQL + contrat | nouvelle clé et nouveau code, bascule atomique côté serveur (`rotate_data_key`), clé en attente si la réponse se perd, rechiffrement progressif des enregistrements (sans les interpréter) et des fichiers, ancienne clé effacée à la fin ; le serveur refuse ensuite les enveloppes et les copies de récupération d'une autre version ; les autres téléphones sont prévenus et reprennent avec le nouveau code. SECURITY §4.10 |
| Audit de sécurité automatisé | ✅ | **défaut trouvé : pas de permission `INTERNET` en release** (le serveur était injoignable depuis une APK release) — corrigé ; clair refusé (sauf debug), sauvegarde Android désactivée et testée, `POST_NOTIFICATIONS` retirée, signature release hors Git (`key.properties`), HTTPS exigé hors local, contrôle de l'APK fusionnée en CI. SECURITY §17 |
| Se déconnecter et effacer ce téléphone | ✅ unitaires + widget + SQL + contrat | le téléphone se retire lui-même (`leave_device`), fin de session, effacement local ; hors ligne, effacement quand même |
| Supprimer le compte | ✅ unitaires + widget + SQL + contrat | mot de passe redemandé, fichiers puis compte (cascade complète côté serveur), puis effacement local ; hors ligne, rien n'est effacé. Avis juridique sur la conservation : en attente |
| Message après effacement | ✅ widget | au redémarrage, l'Accueil dit pourquoi le téléphone est vide (révoqué, déconnecté, compte supprimé, réinitialisé), une fois |
| Quota de fichiers | ✅ SQL | 2 000 fichiers par compte (politique Storage) ; quota en octets NON VÉRIFIÉ sur le vrai Storage |
| Localisation Material en malagasy | ✅ test | menu des champs, boutons et libellés lus, dialogues, compteur, licences ; premier jet à relire ; dates et sélecteurs (non utilisés) en français |
| Accessibilité | ✅ auto | 13 écrans × clair/sombre × mg/fr : cibles ≥ 48 dp, cibles libellées, contraste ; texte à 200 % sans débordement (un débordement trouvé et corrigé dans Finances) ; mot de passe redemandé : champ libéré trop tôt (bug, corrigé) |
| Budgets de performance | ✅ auto (CI) | [PERFORMANCE.md](PERFORMANCE.md) : taille de l'APK, démarrage et mémoire sur émulateurs ; appareils A et B NON VÉRIFIÉS |
| Checklist de release | ✅ document | [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) |
| Chaînes | 🟡 | 33 nouvelles chaînes d'interface, mg en premier jet ; ~40 chaînes Material mg |

Points ouverts de la Phase 10 : ceux de la section 1 de la checklist de
release (avis juridique, revue cryptographique externe, audit de
sécurité, production, identifiant Android, clé Play, relecture malagasy,
appareils A et B), plus le back-office (D5) et un quota en octets.

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
| **6 — Outils** | déblocage progressif — **livrée pour revue** | 14 outils catalogués, 5 utilisables, les autres annoncés |
| **7 — Finance, business model, documents** | calculateurs, canvas, dossier, export PDF — **livrée pour revue** | calculs testés aux limites |
| **8 — Formalisation Madagascar** | contenu réglementaire sourcé et daté — **livrée pour revue** | 100 % des informations sourcées |
| **9 — Voix + IA limitée** | réponse orale chiffrée hors ligne, points à revoir par règles, IA désactivable — **livrée pour revue** (transcription non livrée : règle « aucune donnée privée vers une IA externe ») | rien n'est envoyé : aucune IA branchée |
| **10 — Production** | **rotation de l'UMK**, localisation Material `mg`, budgets de performance, accessibilité, audit automatisé, déconnexion et suppression de compte — **livrée pour revue** ; revue cryptographique externe, audit tiers, validation juridique, production et back-office **non faits** (extérieurs ou sur décision) | checklist de release complète (écrite ; release bloquée par ses points ouverts) |

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
| **D5** | Contenu en YAML dans le dépôt jusqu'à la Phase 6 | oui — **appliquée en Phases 3 à 6** ; à revoir avant la production (édition hors dépôt) | Phase 10 |
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
| ~~D17~~ | **Rotation de l'UMK : implémentée en Phase 10** (SECURITY §4.10) | — | — |

## Portes

### Phase 1 — ACCEPTÉE (2026-10-06)

### Phase 10 — demandée le 2026-10-08 (« construis la phase 10 »)

### Phase 9 — GO donné le 2026-10-08

### Phase 8 — GO donné le 2026-10-08

### Phase 7 — GO donné le 2026-10-07

### Phase 6 — GO donné le 2026-10-07

### Phase 5 — GO donné le 2026-10-07

### Phase 4 — GO donné le 2026-10-07 (sous réserve que les points en attente ne la bloquent pas)

### Phase 3 — GO donné le 2026-10-06 (tests réels reportés à la fin)

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
- [x] validation réelle du build Android — APK debug et release produits en CI (2026-10-06) ; reste : appareils réels
- [ ] mesures de performance d'Argon2id (et ouverture de la base chiffrée) sur appareil — faites sur émulateur seulement
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

**Projet de développement** : `eripoo-dev` créé par le porteur
(2026-10-22, ref `xqybntszqedpykdzcfwb`). Le workflow manuel
`.github/workflows/supabase-dev.yml` (Actions → Supabase dev → Run
workflow) applique `supabase/migrations/` (`supabase link` + `supabase db
push`), puis, au choix, construit les APK release `eripoo-dev-armeabi-v7a.apk` et `eripoo-dev-arm64-v8a.apk`
(`ERIPOO_ENV=development`, signée avec la clé de debug, artefact 14 jours)
et lance les tests de contrat RPC contre le projet. Secrets GitHub du
dépôt : `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`,
`SUPABASE_DB_PASSWORD`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`. Les tests de
contrat créent des comptes fictifs : la confirmation d'e-mail doit être
désactivée dans le projet (Authentication → Sign In / Providers → Email).
Aucune modification manuelle du schéma dans le tableau de bord.

⚠️ **Constat sur l'environnement de développement de Claude** : le client
Docker est installé mais le démon ne tourne pas, ce qui empêche
`supabase start` ici à ce jour. Options, par ordre de préférence : exécuter
les tests Supabase (RLS, pgTAP) **en CI GitHub** où Docker est disponible ;
tenter de démarrer Docker dans la session ; à défaut, tests SQL partiels sur
PostgreSQL 16 avec un schéma `auth` simulé, **signalés comme partiels**.

### P5 — D9 : région Supabase de production 🟡

**Outil de mesure (chantier C-8, 2026-10-22)** : dans l'APK de
développement seulement (`ERIPOO_ENV=development`), Profil → « Mesure de
latence (développement) » lance 100 allers-retours vers
`/auth/v1/health` du projet de développement, affiche médiane, 95ᵉ
centile, min, max, échecs et type de réseau (Wi-Fi ou données mobiles),
puis copie un rapport texte (`eripoo-latency v1`, toutes les mesures
brutes, lieu et opérateur notés par la personne). Jamais proposé en
production (testé). Le projet de développement n'étant que dans une seule
région, une série par région candidate demande un projet de test dans
chacune.

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
| Identifiant Android (D6) | `com.eripoo.app` (décidé le 2026-10-22) | Gradle | **non** après création dans la Play Console | avant création Play |
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

- **D7** — analytics opt-in sans identifiant : **décidé par le porteur le
  2026-10-22** — « analytics opt-in minimal » : désactivés par défaut, case
  à cocher (décochée) à l'accueil et réglage du Profil ; seulement des
  totaux par jour et par version pour 5 événements (ouverture, diagnostic,
  quête et mission terminés, PDF exporté), envoyés au Supabase de l'app
  (`record_usage`, appel anonyme) ; aucun identifiant, aucun contenu.
  Fait au chantier C-13.
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
