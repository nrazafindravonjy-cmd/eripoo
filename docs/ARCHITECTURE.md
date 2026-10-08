# Eripoo — Architecture technique

Statut : **revue Phase 0, v2.** Orientation validée dans ses principes ; les
décisions marquées ⚠️ attendent encore une validation explicite (liste
consolidée dans [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md#décisions)).

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
│  Présentation (écrans, rendus génériques de blocs) ◄── contrôleurs Riverpod
│                                                        │                 │
│                                       Domaine (services purs, règles)    │
│                                                        │                 │
│  Moteur de contenu ◄── packs signés ─┐    Repositories (interfaces)      │
│  (règles, parcours, textes fr/mg/en) │               │                   │
│                                      │   Drift / SQLite chiffré (sqlite3mc)  ◄ source de vérité
│                                      │               │                   │
│                                      │   sync_meta ─► Moteur de sync ─► Chiffrement libsodium (UMK)
│  Keystore Android ◄── UMK, clé de base                                   │
└──────────────────────────────────────┼───────────────────┼───────────────┘
                                       │ HTTPS             │ HTTPS (2 RPC)
┌─────────────────────────────── Supabase ────────────────────────────────┐
│  Storage `content` (packs signés)     Postgres : sync_records (chiffré), │
│  Storage `user-media` (chiffré)       sync_heads, devices, user_keys     │
│  Auth (e-mail, Google, téléphone)     (UMK enveloppée), profiles,        │
│  Edge Functions (suppression de       consents, contenu publié,          │
│  compte, ingestion analytics, proxy)  analytics anonymes                 │
└──────────────────────────────────────────────────────────────────────────┘
```

Principes structurants :

1. **La base locale est la source de vérité.** L'interface ne lit jamais le
   réseau ; elle observe Drift.
2. **Les données privées sont chiffrées de bout en bout sur l'appareil**
   avant tout envoi ; le serveur ne détient aucune clé utilisable
   ([SECURITY §4–8](SECURITY.md#4-schéma-cryptographique-de-bout-en-bout)).
3. **Le parcours est piloté par du contenu**, entièrement séparé du code
   d'interface (§6).
4. **Pas d'IA au cœur** : progression, déblocages et adaptation sont
   déterministes et testés.
5. **Le malagasy est la langue native du produit** (§5).

## 2. Stack retenue

Stack du cahier des charges conservée : **Flutter / Dart, Riverpod,
go_router, Drift (SQLite), Supabase.**

| Élément | Version vérifiée (2026-10-06) |
|---|---|
| Flutter | 3.47.6 stable (Dart 3.13.5) |
| Android minSdk | 24 (Android 7.0) — minimum imposé par Flutter 3.47 |

## 3. Couches et règles de dépendance

| Couche | Contenu | Peut dépendre de |
|---|---|---|
| `presentation` | écrans, rendus de blocs de contenu, contrôleurs Riverpod | domain, content (modèles) |
| `domain` | entités, services purs (machine d'états d'hypothèse, calculs financiers), interfaces de repository | core, content (Dart pur) |
| `data` | repositories Drift, DAO, mappers | domain, core |
| `sync` | marquage des modifications, push/pull, résolution, enveloppes | data, security, core |
| `content` | modèles de contenu, chargeur et vérification de packs, localisation du contenu, évaluateur de règles, planificateur | core |
| `security` | gestion des clés, `CryptoService` (libsodium), stockage sécurisé | core |
| `services` | Supabase, transcription, IA, notifications | core |
| `core` | erreurs, `Result`, logger expurgé, UUID, configuration | — |

- **`domain` peut lire les modèles de `content`** (Phase 3) : les statuts
  d'étape et de mission, les types de réponse et la structure d'une étape
  sont définis une seule fois, par le contenu ; les dupliquer dans le
  domaine créerait deux vérités. `content` reste du Dart pur qui ne dépend
  que de `core` (vérifié par le test d'architecture « domain and core
  layers are pure Dart »).
- **Aucune logique métier dans les widgets.**
- **Le domaine est du Dart pur**, testable sans émulateur.
- **Toute écriture métier passe par un repository** qui, dans la même
  transaction Drift, écrit l'élément et le marque « à synchroniser »
  (`sync_meta`).
- Vérification automatique des dépendances entre couches en CI
  (`tool/check_layers.dart`, Phase 1).
- Un service de domaine par agrégat (ex. `HypothesisService`), pas de
  « use case » d'une ligne par action.

## 4. Architecture Flutter

### 4.1 État : Riverpod 3

- `flutter_riverpod` sans générateur de code (Drift impose déjà
  `build_runner`). Réévaluable.
- Providers d'infrastructure dans `lib/app/di/`, surchargeables en test.
- États d'écran immuables (classes `sealed` : `Loading / Data / Error /
  Offline`).
- Flux Drift (`watch()`) → `StreamProvider` : l'interface se met à jour
  après écriture locale ou synchronisation.

### 4.2 Navigation : go_router

- `StatefulShellRoute` à 5 branches : Accueil, Ma quête, Projet, Outils,
  Profil.
- Redirections pilotées par l'état local (onboarding, diagnostic), jamais
  par le réseau ni par l'authentification : un invité accède à tout le
  parcours.
- Écrans de parcours ouverts **par identifiant de contenu**
  (`/quest/:questId/step/:stepId`) : une route générique, pas une route par
  étape.

### 4.3 Thème et design tokens

Implémenté en Phase 1 : voir [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md).

## 5. Langues : malagasy natif, fr et en

Trois couches indépendantes. **Aucune ne fait du français une limite
architecturale.**

### 5.1 Contenu Eripoo : système de localisation propre (sans `intl`)

- Tout le contenu pédagogique (quêtes, étapes, questions, aides, exemples,
  missions, badges, ressources, informations administratives) est localisé
  **dans les packs de contenu**, par un système propre à Eripoo :
  `LocalizedText { mg, fr, en, statut de relecture par langue }`.
- `ContentLocalizer` (Dart pur, dans `lib/content/`) choisit le texte selon
  la langue de l'utilisateur et une **chaîne de repli configurable**
  (proposition : `mg → fr → en`, `fr → mg → en`, `en → fr → mg`) ; il signale
  à l'interface quand un texte est affiché dans une autre langue.
- Ni `intl`, ni ARB, ni `Locale` Flutter ne sont nécessaires à ce système :
  il fonctionne de la même façon pour les trois langues.
- Le malagasy est une langue **de rédaction**, pas seulement de traduction :
  le contenu est écrit en malagasy et en français par des auteurs
  (ou relecteurs) natifs ; aucune traduction automatique n'est publiée sans
  relecture (voir [PRODUCT_ARCHITECTURE §6](PRODUCT_ARCHITECTURE.md#6-contenu-multilingue-fr--mg--en)).
- Choix de la langue : premier écran de l'onboarding, **malagasy en
  premier et présélectionné** (les téléphones sont rarement réglés en
  malagasy, la langue du système n'est donc pas un bon indicateur). Le repli
  actuel vers le français dans `lib/app/app.dart` est un comportement de
  Phase 0, remplacé en Phase 2.

### 5.2 Chaînes de l'interface (boutons, menus, messages)

- Fichiers ARB `app_mg.arb`, `app_fr.arb`, `app_en.arb` compilés par
  `gen-l10n` (en place). Le code généré utilise `intl` pour les pluriels ;
  `intl` 0.20.3 contient bien une règle de pluriel pour `mg` (vérifié). La
  pertinence des formes plurielles en malagasy sera confirmée par un
  relecteur natif.
- Ces chaînes sont peu nombreuses : l'essentiel du texte vient du contenu
  (§5.1).

### 5.3 Formats (dates, nombres, montants en ariary)

- `EripooFormatter` (Phase 1), code propre à Eripoo, pour les trois langues :
  montants en ariary entiers (« 15 000 Ar »), dates, durées. Il ne dépend pas
  des symboles `intl`, qui **n'existent pas pour `mg`** dans `intl` 0.20.3
  (vérifié). Noms de mois et de jours malagasy à faire valider par un
  locuteur natif.

### 5.4 Composants système Flutter (sélecteurs de date, infobulles, libellés d'accessibilité)

État actuel : Flutter 3.47.6 ne fournit pas de localisations
Material/Cupertino pour `mg` (vérifié) ; un délégué de repli sert ces
chaînes en français (`lib/l10n/mg_fallback_localizations.dart`).

Stratégie de localisation complète, sans changement d'architecture :

1. **Limiter l'exposition dès la Phase 1** : le design system privilégie des
   composants Eripoo dont les textes viennent de nos ARB ; l'inventaire des
   chaînes Material réellement visibles est tenu à jour.
2. **Localisations Material/Cupertino malagasy propres** : sous-classes de
   `GlobalMaterialLocalizations` et `GlobalCupertinoLocalizations` (méthode
   prévue par Flutter pour ajouter une langue non prise en charge), avec :
   - les ~80 chaînes du framework traduites par un relecteur natif, stockées
     dans `lib/l10n/framework/material_mg.arb` ; un test vérifie que chaque
     clé de la référence française existe en malagasy ;
   - des symboles et motifs de date malagasy enregistrés auprès d'`intl` via
     `initializeDateFormattingCustom` (présent dans `intl` 0.20.3, vérifié),
     nécessaires aux sélecteurs de date du framework.
3. **Bascule** : remplacer les deux délégués de repli par les nouveaux, dans
   une seule liste (`frameworkLocalizationsDelegates`). Aucun écran ne
   change.
4. Contribution en amont au projet Flutter : possibilité à étudier, non
   nécessaire.

Calendrier : étape 1 en Phase 1 ; étapes 2–3 dès qu'un relecteur natif est
disponible, **au plus tard en Phase 10** (critère de sortie de production).

## 6. Séparation du contenu et de l'interface

**Confirmation : le contenu pédagogique, les missions, les règles de
progression et les traductions sont entièrement séparés du code
d'interface.** Le parcours peut être modifié sans toucher aux écrans
Flutter.

| Vit dans les packs de contenu (données) | Vit dans le code |
|---|---|
| quêtes, étapes, ordre, prérequis | moteur de règles (opérateurs) |
| textes et traductions mg/fr/en, exemples, aides, reformulations | `ContentLocalizer` |
| missions (objectif, instructions, livrable, critère de complétion, preuves exigées) | machine d'états des missions et des hypothèses |
| règles de déblocage, d'adaptation, de maturité, de badges, de niveau de préparation | planificateur, évaluateur |
| badges, outils proposés, ressources, informations réglementaires sourcées | **rendus génériques** de chaque *type* de bloc (texte, question à choix, réponse libre, montant, audio, image, exemple, mission…) |
| schéma des champs de chaque section du projet | calculateurs financiers, export PDF |

- Les écrans de parcours sont **génériques** : une route par identifiant
  (`/step/:stepId`, `/mission/:missionId`), un rendu par type de bloc.
  Aucun écran n'est propre à une étape. Implémentation (Phase 3) : les
  blocs sont une classe scellée et l'écran d'étape fait un `switch`
  exhaustif dessus — le compilateur refuse un type de bloc sans rendu, ce
  qui remplace le registre.
- **Sans mise à jour de l'app** (nouveau pack) : ajouter, retirer ou
  réordonner des quêtes et étapes, réécrire ou traduire tout texte, créer
  des missions, changer les règles, ajouter des badges, des exemples, des
  ressources.
- **Avec mise à jour de l'app** (limite honnête) : un **nouveau type** de
  bloc, un nouvel opérateur de règle, un nouvel outil interactif (ex. un
  nouveau calculateur). Chaque pack déclare `min_app_version` et la liste
  des types de blocs qu'il utilise ; une app trop ancienne garde le pack
  précédent.
- Garde-fous en CI : le validateur de contenu vérifie les références et les
  règles ; un test interdit les chaînes littérales visibles dans
  `features/*/presentation` (tout passe par les ARB ou le contenu).

## 7. Offline-first (résumé)

Détail : [OFFLINE_SYNC.md](OFFLINE_SYNC.md).

- Toutes les données utilisateur vivent dans Drift (chiffré) ; identifiants
  UUID v7 générés sur l'appareil.
- Chaque écriture marque l'élément « à envoyer » dans la même transaction.
- Synchronisation au démarrage, au retour au premier plan, au retour du
  réseau, après écriture, périodiquement.
- Contenu pédagogique embarqué (pack de base) puis mis à jour quand le
  réseau le permet.

## 8. Synchronisation avec Supabase (résumé)

- Une table d'enveloppes chiffrées (`sync_records`), un compteur de
  versions par utilisateur (`sync_heads`), une table d'appareils.
- Deux RPC : `sync_push` (comparaison de version, idempotence par
  `change_id`) et `sync_pull` (curseur sans trou).
- Conflits rares, résolus sur l'appareil sans horloge : la version de
  l'appareil qui résout est gardée, l'autre devient une **copie de conflit
  synchronisée** ; rien n'est perdu.
- Synchronisation développée en interne : justification dans
  [OFFLINE_SYNC §12](OFFLINE_SYNC.md#12-pourquoi-une-synchronisation-interne-plutôt-quune-solution-spécialisée).

## 9. Authentification (résumé)

Détail : [SECURITY §3, §7 et §10](SECURITY.md#3-trois-secrets-distincts).
Invité 100 % local ; e-mail/mot de passe, Google, téléphone ; Facebook prévu
et désactivé ; plusieurs méthodes liées à un compte. **L'authentification
donne accès au chiffré, pas aux données** : le déchiffrement exige un
appareil autorisé ou le code de récupération.

## 10. Tablette / téléphone

- Portrait uniquement.
- Classes de largeur : **compacte** < 600 dp (téléphone), **moyenne**
  600–839 dp (tablette en portrait), **étendue** ≥ 840 dp (traitée comme
  moyenne avec largeur max).
- `AdaptiveScaffold` maison (Phase 1) : `NavigationBar` en bas sur
  téléphone ; `NavigationRail` + largeur de lecture max (~640 dp) +
  maître/détail (Projet, Outils) sur tablette.
- Taille de police système respectée jusqu'à 200 %, testée.
- Tests de widget sur 360×640 et 800×1280.

## 11. Anciens appareils Android

Cible de référence proposée ⚠️ : Android 7–10, 1–2 Go de RAM, CPU 32 bits
(armeabi-v7a), stockage presque plein, réseau 2G/3G intermittent.

| Domaine | Mesures |
|---|---|
| Binaire | App Bundle + APK par ABI hors Play ; obfuscation ; icônes élaguées ; une police variable ; pas de Lottie/Rive. |
| Démarrage | initialisations paresseuses ; base ouverte en isolat (`drift_flutter`) ; premier écran depuis le cache local. |
| Mémoire | listes paresseuses, images décodées à la taille d'affichage, médias plafonnés à 10 Mo. |
| Cryptographie | XChaCha20-Poly1305 (rapide en logiciel sur ARMv7 sans accélération AES) ; Argon2id seulement à la récupération ; opérations lourdes en isolat. |
| Base locale | index sur les références et `sync_meta` ; requêtes paginées ; WAL ; coût d'ouverture de la base chiffrée mesuré. |
| Réseau | lots bornés ; contenu en deltas ; médias en Wi-Fi par défaut ; aucune requête bloquante au démarrage. |
| Animations | courtes, désactivables, coupées si « animations réduites ». |
| Rendu | moteur de rendu validé sur appareils de référence, sans hypothèse a priori. |

Budgets proposés (mesurés en Phase 10 sur appareil réel) : démarrage à froid
< 3 s, APK par ABI < 25 Mo, RAM < 200 Mo.

## 12. Stratégie de tests

| Niveau | Cible | Outils |
|---|---|---|
| Unitaires | règles, planificateur, machine d'états hypothèse/expérience, calculs financiers (entiers MGA), résolution de conflits, enveloppes chiffrées (vecteurs de test, rejet d'un chiffré déplacé), `ContentLocalizer` (replis), règles d'accès client | `flutter_test`, `mocktail` |
| Base locale | DAO, migrations Drift, écriture + marquage `sync_meta` atomiques | Drift en mémoire |
| Sync | les 14 scénarios d'[OFFLINE_SYNC §13](OFFLINE_SYNC.md#13-plan-de-tests) | faux serveur en mémoire (doublure documentée) + Supabase local |
| Serveur | RLS, RPC, refus d'accès du personnel | Supabase CLI + pgTAP |
| Widgets | design system, états loading/error/offline, accessibilité, clair/sombre, 2 tailles, 3 langues | `flutter_test` |
| Intégration | onboarding, compte, projet, parcours, offline/reconnexion/sync, transfert QR | `integration_test` (émulateurs API 24 et récent) |
| Contenu | schéma, références, traductions manquantes, statut de relecture ; plus tard lisibilité, sources réglementaires, signature | `tool/content_build.dart --check` en CI (Phase 3) |
| Appareil lent | démarrage, défilement, mémoire | appareils de référence |

## 13. Arborescence du projet

Éléments existants en **gras** ; le reste est la cible.

```
eripoo/
├── **.github/workflows/ci.yml**
├── **analysis_options.yaml**  **l10n.yaml**  **pubspec.yaml**
├── **android/**                        backup et transfert désactivés
├── **docs/**
├── content/                            sources du contenu (YAML), schéma, packs
├── supabase/                           migrations, RLS, RPC, Edge Functions, tests pgTAP
├── tool/                               validation/compilation/signature du contenu, couches
├── lib/
│   ├── **main.dart**
│   ├── bootstrap.dart
│   ├── app/          **app.dart**, router/, di/
│   ├── core/         config/, errors/, logging/, ids/
│   ├── **l10n/**     ARB mg/fr/en, **repli framework mg**, framework/ (Material mg, plus tard)
│   ├── design_system/
│   ├── data/         local/ (Drift), remote/ (Supabase)
│   ├── sync/         meta, engine, push, pull, resolve/, envelope/
│   ├── security/     key_manager, crypto_service (libsodium), recovery, device_transfer
│   ├── content/      models/, loader/, signature/, localizer/, rules/, planner/
│   ├── services/     transcription, ai, notifications, connectivity
│   └── features/     onboarding, diagnostic, auth, home, quest, project, evidence,
│                     observations, interviews, missions, tools, finance,
│                     business_model, formalization, documents, profile, settings
│                     └── <feature>/{domain,data,presentation}/
├── **test/**
└── integration_test/
```

## 14. Région d'hébergement Supabase

**Aucune région n'est choisie dans ce document.** Elle ne peut pas être
changée simplement après la création du projet ; le choix doit reposer sur
des mesures et un avis juridique.

### 14.1 Faits établis

- Supabase propose 17 régions AWS, dont **aucune en Afrique ni au
  Moyen-Orient** d'après sa documentation telle que relayée par une recherche
  du 2026-10-06 ([page officielle](https://supabase.com/docs/guides/platform/regions)
  — à reconfirmer au moment du choix ; la page n'a pas pu être consultée
  directement depuis l'environnement de développement).
- Madagascar est relié à l'international par quatre câbles sous-marins :
  EASSy, LION, METISS (Madagascar–Maurice–La Réunion–Afrique du Sud, actif
  depuis 2021) et 2Africa (atterrissement à Mahajanga ; système reliant
  l'Afrique, l'Europe et le Moyen-Orient)
  ([Emtel — METISS](https://www.emtel.com/business/metiss),
  [Connecting Africa — 2Africa](https://connectingafrica.com/connectivity/2africa-reaches-the-shores-of-madagascar)).
  **Aucune mesure publique de latence Madagascar → régions cloud n'a été
  trouvée** : il faut mesurer.
- Madagascar a une loi sur la protection des données (n° 2014-038,
  autorité : CMIL ; décret n° 2023-1541 sur son fonctionnement). Des
  synthèses indiquent qu'elle encadre les transferts de données hors du
  pays (protection adéquate, garanties, consentement ou autorisation de la
  CMIL) ([texte publié par l'Assemblée nationale](https://www.assemblee-nationale.mg/wp-content/uploads/2020/11/Loi-n°2014-038-sur-la-protection-des-données-à-Kre-personnel.pdf),
  [synthèse DLA Piper](https://www.dlapiperdataprotection.com/index.html?t=law&c=MG)).
  **Toute région étant hors de Madagascar, cette question concerne tous
  les choix** ; son interprétation relève d'un juriste.

### 14.2 Ce qui pèse vraiment pour Eripoo

- **Le chiffrement de bout en bout réduit l'enjeu** : le serveur détient du
  chiffré, plus les identifiants de compte, les métadonnées et des analytics
  anonymes. Le transfert hors de Madagascar porte donc surtout sur ces
  éléments.
- **L'offline-first réduit la sensibilité à la latence** : la sync tourne en
  arrière-plan. La latence compte surtout pour la connexion (OTP, Google),
  la récupération par code et le premier téléchargement de contenu.
- D'où l'ordre proposé des critères : **cadre juridique ≈ disponibilité >
  coût > latence**.

### 14.3 Comparaison des candidates (à compléter par les mesures)

| Région | Latence depuis Madagascar | Protection des données | Disponibilité | Coûts |
|---|---|---|---|---|
| Paris `eu-west-3` | à mesurer ; candidate naturelle (liens européens, francophonie administrative) | cadre européen (RGPD) côté hébergeur ; documentation en français facilitant l'analyse juridique | région AWS standard ; projet Supabase mono-région | à vérifier sur la grille Supabase |
| Francfort `eu-central-1` | à mesurer | cadre européen | région AWS ancienne et très utilisée | idem |
| Irlande `eu-west-1`, Londres `eu-west-2` | à mesurer | RGPD (Irlande) ; régime britannique distinct (Londres) | standard | idem |
| Zurich `eu-central-2`, Stockholm `eu-north-1` | probablement moins favorables (à mesurer) | cadres suisse / européen | standard | idem |
| Mumbai `ap-south-1` | à mesurer (témoin côté océan Indien) | cadre indien, analyse juridique plus lourde pour un public malgache | standard | idem |

Disponibilité, commun à toutes : un projet Supabase vit dans **une seule
région** ; la tolérance aux pannes repose sur le plan choisi et les
sauvegardes (à vérifier). L'offline-first rend une panne serveur peu visible
pour l'utilisateur (seule la sync est suspendue).

### 14.4 Protocole de décision

1. Mesurer depuis Madagascar, sur les réseaux mobiles des trois principaux
   opérateurs et en Wi-Fi, à Antananarivo et dans au moins une ville de
   province, à plusieurs heures : temps d'établissement TLS et d'une petite
   requête HTTPS vers un projet Supabase de test dans chaque région candidate
   (≥ 100 mesures, médiane et 95ᵉ centile).
2. Faire valider par un juriste la base légale du transfert pour les
   candidates retenues (avec et sans mineurs).
3. Comparer la grille tarifaire Supabase et les coûts de transfert pour le
   volume prévu (audio surtout).
4. Décider (D9). Présélection proposée pour les mesures : Paris et
   Francfort, avec Mumbai comme témoin.

## 15. Identifiant de l'application Android

`mg.eripoo.eripoo` est **une valeur provisoire générée à l'initialisation**,
pas une décision.

- L'identifiant (`applicationId`) devient **définitif dès que l'application
  est créée dans la Play Console** (y compris pour un test interne) ; il ne
  peut plus être modifié ensuite.
- Avant cela, le changer est simple (Gradle + dossier de `MainActivity`).
- Convention : nom de domaine inversé d'un domaine **que vous possédez**
  (ex. `mg.eripoo.app` si `eripoo.mg` vous appartient, `com.eripoo.app` pour
  `eripoo.com`), pour éviter toute contestation et refléter l'organisation
  qui publie.
- À confirmer avant la première mise en ligne sur Play (décision D6) ;
  rien dans l'architecture n'en dépend.

## 16. Dépendances

Résolution vérifiée dans un projet de test le 2026-10-06 (Flutter 3.47.6).
**Installées : `flutter_localizations`, `intl` (Phase 0), `flutter_riverpod`, `go_router` (Phase 1).** `mocktail` n'a pas encore été nécessaire et n'est pas installé.

| Paquet | Version | Phase | Justification |
|---|---|---|---|
| `flutter_localizations` (SDK) | — | 0 ✅ | Localisations du framework, requis par gen-l10n. |
| `intl` | 0.20.3 | 0 ✅ | Messages ARB de l'interface et pluriels (règle `mg` présente). **Pas** utilisé pour le contenu ni pour formater les dates `mg`. |
| `flutter_riverpod` | 3.4.3 | 1 ✅ | Imposé ; injection testable, flux réactifs. |
| `go_router` | 18.0.2 | 1 ✅ | Imposé ; shell à onglets, routes par identifiant de contenu. |
| `mocktail` (dev) | 1.0.5 | 1 | Doublures de test sans génération de code. |
| `drift` + `drift_dev` (dev) | 2.35.1 | 2 | Base relationnelle typée, migrations testables, requêtes réactives. |
| `drift_flutter` | 0.3.1 | 2 | Base ouverte en isolat. |
| `sqlite3` (transitif) | 3.5.2 | 2 | Chiffrement de la base via l'option de hook `source: sqlite3mc` (SQLite3MultipleCiphers 2.5.0, licence MIT vérifiée — SECURITY §18.2). Ne **pas** ajouter `sqlcipher_flutter_libs` / `sqlite3_flutter_libs` (fin de vie, `+eol`). |
| `build_runner` (dev) | 2.16.1 | 2 | Génération Drift. |
| `uuid` | 4.6.0 | 2 | UUID v7 (identifiants) et v4 (`change_id`, `device_id`). |
| `sodium` | 4.1.1+2 | 2 | **libsodium 1.0.22** : AEAD XChaCha20-Poly1305, KDF, Argon2id, sceaux X25519, signatures Ed25519, aléa. Compile libsodium à la construction (hooks). Remplace `cryptography` retenu en v1. Analyse de maintenance, licence et remplacement : SECURITY §18.1. `sodium_libs` est abandonné au profit de `sodium`. |
| `flutter_secure_storage` | 11.2.0 | 2 | UMK, clé de base et session protégées par Android Keystore (option AES-GCM). |
| `supabase_flutter` | 2.18.0 | 2 | Imposé ; Auth (dont liaison d'identités), RPC, Storage. |
| `workmanager` | 0.10.10 | 5 | Synchronisation en arrière-plan (Android WorkManager), MIT. |
| `connectivity_plus` | 7.3.2 | 5 | Signal de retour du réseau et Wi-Fi / données mobiles (envoi des photos), BSD-3. |
| `camera` | 0.12.1 | 5 | Images de la caméra pour lire les QR du transfert (flutter.dev, BSD-3) ; micro jamais demandé. |
| `zxing2` | 0.2.4 | 5 | Lecture des QR en Dart pur, sur l'appareil (BSD-3) ; préféré à `mobile_scanner` (Google ML Kit). |
| `qr` | 3.0.2 | 5 → 7 | Génération des QR (BSD-3). Ramené de 4.0.0 à 3.0.2 en Phase 7 : `pdf` dépend de `barcode`, qui exige `qr` 3 ; le QR produit est le même (tests du codec inchangés). |
| `pdf` | 3.13.1 | 7 | Génération du dossier et du pitch deck en PDF, en Dart pur, sur l'appareil (Apache 2.0, DavBfr). |
| `share_plus` | 13.3.1 | 7 | Menu de partage Android pour le PDF (BSD-3, Flutter Community) ; aucune permission ajoutée. |
| `connectivity_plus` | 7.3.2 | 5 | Signal de changement de réseau (jamais une preuve de connexion). |
| `integration_test` (SDK, dev) | — | 2 | Tests d'intégration. |

Police embarquée (Phase 7) : Roboto Regular et Bold (Apache 2.0, copiées
du SDK Flutter, `assets/fonts/`, licence enregistrée dans l'application)
pour que le PDF affiche tous les caractères du malagasy, du français et de
l'anglais.

Prévus plus tard, à justifier à l'ajout : `google_sign_in`, `record`,
`image_picker` + compression, lecture/génération de QR (transfert entre
appareils), `flutter_local_notifications`,
éventuellement `local_auth` (verrou applicatif). Écartés : `cryptography`
(remplacé par libsodium), `freezed`, `riverpod_generator`,
`shared_preferences` pour les données métier, SDK d'analytics tiers.

## 17. Principaux risques techniques

| # | Risque | Impact | Mitigation |
|---|---|---|---|
| R1 | Perte de l'UMK (tous les appareils + code de récupération perdus) | copie en ligne illisible, définitivement | transfert QR, code vérifié à la création, rappels, second appareil encouragé ; option séquestre B ajoutable sans migration |
| R2 | Composants Flutter non localisés en malagasy | chaînes système en français pour les utilisateurs `mg` | repli isolé (fait), localisations Material `mg` propres (§5.4) |
| R3 | Reconnaissance vocale du malagasy peu disponible | transcription inutilisable en `mg` | audio toujours conservé ; transcription optionnelle ; jamais bloquante |
| R4 | Coût / délivrabilité des SMS OTP | connexion téléphone peu fiable | fournisseur testé avant production ; e-mail et Google ; liaison de 2 méthodes encouragée |
| R5 | Bugs de synchronisation | perte de confiance | protocole minimal (v2), idempotence, 14 scénarios de faute, copies de conflit, aucune suppression physique avant confirmation |
| R6 | Performances sur appareils 1 Go / 32 bits | lenteurs | appareils de référence dès la Phase 1, XChaCha20, isolats, budgets mesurés |
| R7 | Information réglementaire obsolète ou fausse | préjudice | source + date de vérification + date de revue obligatoires |
| R8 | Conformité juridique non validée (mineurs, données, transferts hors de Madagascar) | blocage du lancement | règles configurables ; avis juridique avant Phase 2 (consentement parental) et avant production |
| R9 | Dépendance à Supabase (coûts Storage, région unique) | indisponibilité / coûts | plan payant, quotas médias, protocole portable vers tout Postgres |
| R10 | Contenu incompatible avec la progression existante | progression cassée | identifiants stables, packs versionnés, migrations de progression |
| R11 | Téléphone partagé | lecture du projet par un tiers | base chiffrée, verrou applicatif optionnel |
| R12 | Binding Dart `sodium` maintenu par une seule personne | correctifs lents | interface `CryptoService` étroite ; libsodium lui-même est la référence ; alternative documentée : Tink via canal natif Android |
| R13 | Argon2id gourmand en mémoire sur 1 Go | échec de récupération | paramètres mesurés sur appareil de référence ; les 116 bits d'aléa du code de récupération suffisent même avec des paramètres modestes (planchers : 2 passes, 32 Mio) |
| R14 | Licence de SQLite3MultipleCiphers | — | **vérifiée : MIT**, composants permissifs (dont une mention BSD pour SHA-2) ; compatible Play Store ; vérifiée aussi sur l'étiquette livrée v2.5.0 (SECURITY §18.2) ; liste des mentions à valider par le juriste ; repli : SQLCipher |
| R15 | Implémentation de l'assemblage cryptographique (mauvaise donnée associée, mauvaise clé) | fuite ou perte | revue de code dédiée, vecteurs de test, revue cryptographique externe avant production |
| R16 | Appareil autorisé compromis avant que la rotation de clé existe | exposition durable de l'UMK | révocation immédiate ; rotation implémentée avant le lancement public (D17) |
| R17 | Utilisateurs qui ne conservent pas leur code (36 chiffres) | pertes de données | fiche de secours papier, lecture audio des chiffres, confirmation, rappels, second appareil encouragé ; mesurer en test utilisateur ; option séquestre B si nécessaire |
| R18 | Binaires natifs téléchargés au build (sqlite3mc) | chaîne d'approvisionnement | empreintes SHA-256 figées dans le paquet ; miroir interne possible (`url_pattern`) |
