# Eripoo — Architecture produit

Comment le produit (parcours, missions, hypothèses, contenu) est traduit en
mécanismes logiciels. Les structures de données correspondantes sont dans
[DATA_MODEL.md](DATA_MODEL.md).

Règle directrice appliquée partout : **Eripoo ne fait jamais à la place de
l'utilisateur une réflexion qu'il peut faire lui-même.** Techniquement, cela
se traduit par : le contenu pose des questions et propose des missions ; le
moteur décide *quoi montrer ensuite* de façon déterministe ; aucune
composante centrale n'est générée par une IA.

---

## 1. Vue d'ensemble des moteurs

```
Pack de contenu (JSON versionné, fr/mg/en)
        │
        ▼
 ┌──────────────┐  faits (diagnostic, projet, progression)  ┌───────────────┐
 │ Évaluateur   │◄──────────────────────────────────────────│ FactProvider  │
 │ de règles    │                                           └───────────────┘
 └──────┬───────┘
        ▼
 ┌──────────────┐   plan ordonné (quêtes/étapes + statut)
 │ Planificateur│──────────────────────────────► UI « Ma quête »
 │ de parcours  │
 └──────┬───────┘
        ▼
 ┌──────────────┐  réponses, missions, preuves   ┌────────────────────────┐
 │ Exécuteur    │───────────────────────────────►│ Projet + Hypothèses    │
 │ d'étape      │  (écritures via repositories)  │ + Expériences (Drift)  │
 └──────────────┘                                └────────────────────────┘
        │ événements de domaine
        ▼
 Badges · déblocage d'outils · maturité · niveau de préparation
```

Tous ces moteurs sont du **Dart pur dans `lib/content/` et
`lib/features/*/domain/`**, testés unitairement, sans dépendance à Flutter.

## 2. Onboarding et diagnostic (avant compte)

Séquence : installation → onboarding (langue, promesse, confidentialité en
une phrase) → diagnostic → début de parcours → proposition de sauvegarde →
création de compte (facultative, voir [SECURITY §10](SECURITY.md#10-authentification)).

- Le diagnostic est **lui-même du contenu** (un pack `diagnostic`) : des
  questions courtes, une par écran, majoritairement à choix avec icônes,
  réponse vocale possible, toujours « Je ne sais pas ».
- Chaque réponse écrit un **fait typé** (`diag.idea_stage = vague_idea`,
  `diag.weekly_hours = 3_5`, `diag.has_customers = false`…). Les faits sont
  des énumérations, nombres ou booléens, **jamais du texte libre**, ce qui
  permet aux règles de les lire sans manipuler de contenu privé.
- Profils d'entrée (fait `diag.entry_profile`, dérivé par règle) :
  `no_idea`, `vague_idea`, `problem_identified`, `existing_activity`,
  `existing_customers`.
- Objectif : ≤ 10 écrans, ≤ 4 minutes. Tout champ non essentiel est reporté
  au moment où il devient utile dans le parcours.
- Le diagnostic peut être refait ; le plan est recalculé sans effacer le
  travail fait.

**État (Phase 3)** : diagnostic de 8 écrans (`content/diagnostic.yaml`),
réponses à choix → faits `diag.*`, puis nom du projet (« Je ne sais pas »
→ titre provisoire). Le profil d'entrée est **demandé** directement au lieu
d'être dérivé par règle (pas encore de faits dérivés). Le diagnostic ne
peut pas être mis de côté (« Je ne sais pas » reste toujours possible) et
le parcours ne s'ouvre qu'après lui, car il crée le projet. Pas encore
faits : icônes des choix, réponse vocale, refaire le diagnostic, choix de
la langue au-delà de mg/fr/en.

## 3. Moteur de parcours « Ma quête »

### 3.1 Hiérarchie de contenu

```
Pack ─► Quête (16 grandes quêtes minimum) ─► Étape ─► Blocs
                                              └──► Mission(s)
```

- **Quête** : `id` stable, ordre, stade de maturité visé, règle
  `available_when`, règle `fast_track_when` (pour profils avancés), liste
  d'étapes, résultat attendu dans le projet.
- **Étape** : type (`learn`, `reflect`, `act`, `checkpoint`, `tool`), blocs,
  règle de complétion, **sorties** (quels champs du projet ou quels faits elle
  écrit), éventuelles missions.
- **Bloc** : unité affichable — texte court, exemple, terme (« langage simple
  → terme entrepreneurial »), question, audio, image, astuce, renvoi vers un
  outil. Une idée par écran.

### 3.2 Langage de règles (déterministe, sans `eval`)

Règles exprimées en JSON, évaluées par un interpréteur Dart de ~200 lignes :

```json
{ "all": [
    { "fact": "diag.entry_profile", "in": ["problem_identified", "existing_activity"] },
    { "not": { "step": "q03.s02", "is": "completed" } },
    { "count": "hypotheses", "where": { "status": "invalidated" }, "gte": 1 }
] }
```

Opérateurs : `all`, `any`, `not`, comparaison de fait (`eq`, `in`, `gte`,
`lte`, `exists`), état d'étape/quête/mission, compteurs sur entités du projet
(par statut/type, **jamais sur le texte**), date relative (`days_since`).
Le validateur de contenu rejette toute règle inconnue ou référence cassée.

### 3.3 Planificateur

Fonction pure : `plan(pack, facts, progress) → List<PlannedQuest>` où chaque
étape reçoit un statut :

| Statut | Signification |
|---|---|
| `locked` | prérequis non remplis (affiché avec « ce qu'il faut faire avant ») |
| `available` | peut être commencée |
| `in_progress` | commencée |
| `completed` | complétée selon sa règle |
| `fast_tracked` | profil avancé : seule la **sortie** est demandée (ex. écrire directement le problème), sans les blocs d'apprentissage ; le contenu reste consultable |
| `deferred` | « Passer temporairement » : réapparaît selon une règle ou après N jours |
| `postponed` | « Revenir plus tard » choisi explicitement |

Adaptation :

- Un utilisateur avancé **ne refait pas** ce qu'il maîtrise : `fast_track_when`
  transforme l'étape en simple vérification de livrable, jamais en saut
  silencieux (le projet doit quand même contenir l'information).
- Les quêtes ne sont pas strictement linéaires : plusieurs peuvent être
  `available` en même temps ; le planificateur propose **une prochaine action
  recommandée** (affichée sur Accueil) selon un ordre de priorité déclaré dans
  le contenu.
- Retour en arrière : une décision « revenir en arrière » sur une hypothèse
  (voir §4) peut rouvrir des étapes antérieures (statut `in_progress` avec
  la raison affichée), sans effacer l'historique.
- Progression affichée : « 4 / 12 » par quête, et maturité globale du projet
  (§7). Le planificateur est recalculé à chaque changement de fait ou de
  progression (coût négligeable : quelques centaines de nœuds).

### 3.4 Système anti-blocage

Chaque bloc `question` déclare obligatoirement ses aides :

| Action utilisateur | Effet déterministe |
|---|---|
| « Je ne comprends pas » | affiche la reformulation de niveau 1, puis niveau 2 (plus simple, avec exemple concret) |
| « Voir un exemple » | exemple localisé (contexte malgache) |
| « M'aider » | indices progressifs déclarés dans le contenu ; l'IA n'intervient que si activée et consentie (§9) |
| Réponse vocale | enregistrement audio offline ; transcription facultative |
| « Je ne sais pas » | réponse enregistrée comme `unknown` (information utile) ; le planificateur peut programmer une mission « va le découvrir » |
| « Passer temporairement » | étape `deferred`, rappel ultérieur |
| « Revenir plus tard » | étape `postponed` |

Garde-fous contre les questions infinies, **vérifiés par le validateur de
contenu** : au plus 5 questions consécutives sans action ni retour visible ;
toute étape `reflect` se termine par une synthèse de ce que l'utilisateur a
construit. Détection de blocage : deux « Je ne comprends pas » sur un même
bloc ⇒ proposer directement l'exemple + la possibilité de passer.

## 4. Hypothèse → Expérience → Résultat → Preuve → Conclusion → Décision

Système central, intégré au modèle de données (voir
[DATA_MODEL §3.4](DATA_MODEL.md#34-hypothèses-expériences-preuves)).

### 4.1 Machine d'états de l'hypothèse

```
draft ──► to_test ──► testing ──► validated
   │          │          │    └─► invalidated
   │          │          └──────► inconclusive ──► testing (tester davantage)
   └──────────┴────────────────► abandoned
validated / invalidated / inconclusive ──(modifier)──► nouvelle hypothèse
                                                       (parent_id = ancienne)
```

Règles métier (service de domaine, tests unitaires obligatoires) :

1. Une hypothèse est formulée par l'utilisateur ; le contenu aide avec un
   gabarit (« Je pense que [qui] a [problème] quand [situation] »), jamais
   une génération.
2. Passer à `testing` exige une expérience avec **critère de réussite défini
   avant le test** (« Si au moins 3 personnes sur 5… »). Ce critère devient
   immuable une fois l'expérience démarrée (on peut créer une nouvelle
   expérience).
3. Passer à `validated` ou `invalidated` exige au moins un résultat et au
   moins une preuve rattachée (exigence paramétrable par type d'hypothèse
   dans le contenu).
4. Une hypothèse n'est jamais modifiée en place après test : « modifier »
   crée une nouvelle version liée (`parent_hypothesis_id`) — l'historique de
   l'apprentissage est conservé.
5. `invalidated` est un résultat positif pour la progression (badge
   « Chercheur de vérité ») ; aucun texte de culpabilisation.

### 4.2 Expérience

Méthodes : interview, observation, prototype, test de prix, prévente, essai
gratuit, autre. Champs clés : hypothèse(s) testée(s), plan, critère de
réussite, échantillon visé, dates, statut (`planned → running → done |
cancelled`). Une expérience est généralement portée par une **mission**.

### 4.3 Résultat, preuve, conclusion, décision

- **Résultat** : ce qui a été observé (texte court + métriques simples :
  « 7 sur 10 »). Plusieurs résultats possibles par expérience.
- **Preuve** : élément documentaire polymorphe rattaché à n'importe quelle
  entité (expérience, mission, observation, interview, section du projet) :
  note, photo, audio, document, lien, chiffre de vente.
- **Conclusion** : ce que l'utilisateur pense désormais + confiance après
  (1–5), comparée à la confiance avant.
- **Décision** (journal immuable) : `continue`, `modify`, `test_more`,
  `abandon`, `go_back`, avec justification. Chaque décision déclenche des
  effets déterministes (ex. `go_back` rouvre l'étape source de l'hypothèse).

## 5. Missions

Une mission est un **gabarit de contenu** instancié pour un projet.

- Contenu : titre, objectif, explication courte, durée estimée, difficulté,
  instructions, exemple, livrable attendu (type), critère de complétion
  (règle), exigences de preuve (types, nombre minimum), indicateur « action
  dans le monde réel ».
- Instance (données utilisateur) : statut (`proposed → accepted →
  in_progress → submitted → completed | abandoned`), dates, preuves liées,
  réflexion finale, lien vers l'expérience si elle en porte une.
- Exemple : « Parle à 3 personnes qui rencontrent ce problème » ⇒ livrable
  `interview` × 3 ⇒ la mission est complétée quand 3 interviews liées
  existent (règle `count`), pas sur simple déclaration.
- Rappels : notifications **locales** planifiées à partir des missions
  acceptées, plafonnées (au plus une par jour, désactivables), jamais de
  rappel de « série » culpabilisant.

## 6. Contenu multilingue fr / mg / en

### 6.1 Chaîne de production

```
content/*.yaml (git, revue) ─► tool/content_validate ─► tool/content_build
     ─► pack JSON + manifeste (version, sha256, min_app_version, types de blocs)
     ─► signature Ed25519 hors ligne (SECURITY §15)
     ─► APK (pack de base) et Supabase Storage `content/` (mises à jour)
```

⚠️ Décision proposée : **le contenu est rédigé en fichiers YAML dans le dépôt
jusqu'à la Phase 6**, avec revue par pull request et validation en CI. Le
back-office web (cahier des charges §44) vient ensuite et écrira le même
format. Cela évite de construire un CMS avant de savoir ce dont les auteurs
ont besoin.

### 6.2 Format des textes

Chaque texte est un objet localisé avec statut de traduction :

```yaml
title:
  fr: "Observe ton quartier"
  mg: "..."            # rédigé ou relu par un locuteur natif
  en: "Observe your neighbourhood"
  _status: { mg: needs_review }
```

- Langue de repli configurable par utilisateur (par défaut `mg → fr → en`,
  `fr → en`, `en → fr`) ; l'UI signale discrètement un texte affiché dans une
  autre langue.
- Le validateur refuse la publication si une langue est manquante sans repli
  déclaré, et liste les textes `needs_review`.
- **Aucune traduction automatique publiée sans relecture humaine.** Une
  traduction machine peut servir de brouillon, marquée comme telle.
- L'audio des textes (lecture à voix haute) est fourni comme ressource du
  pack, téléchargée à la demande, plutôt que via la synthèse vocale Android
  dont le support du malagasy n'est pas garanti.

### 6.3 Mise à jour du contenu sur l'appareil

- Pack de base embarqué ⇒ le parcours fonctionne au premier lancement sans
  réseau.
- Le client compare son manifeste au manifeste distant (requête légère) et
  télécharge les packs modifiés ; installation atomique (nouvelle version
  écrite puis bascule), ancienne version conservée jusqu'à succès.
- Identifiants de contenu **stables et jamais réutilisés** ; un pack peut
  déclarer des migrations (`renamed: {old: new}`, `retired: [...]`) pour que
  la progression existante reste valide.

### 6.4 Informations Madagascar (réglementation, financement, structures)

Type de contenu dédié `regulatory_info` / `resource` avec champs
**obligatoires** : source (nom + URL ou référence), date de vérification,
vérifié par, date de prochaine revue, juridiction. Le validateur bloque toute
publication sans source ; l'app affiche « Vérifié le … — confirme auprès de
[organisme] » et marque les informations dont la revue est dépassée.
**Aucune information réglementaire n'est rédigée dans le cadre de la
Phase 0.**

## 7. Projet, maturité et niveau de préparation

- Le **projet existe dès la première étape** du parcours (créé à la fin du
  diagnostic, même pour « aucune idée » : titre provisoire choisi par
  l'utilisateur).
- Sections typées (`vision`, `problem`, `customers`, `solution`, `offer`,
  `market`, `competition`, `business_model`, `pricing`, `finances`,
  `marketing`, `launch`, `formalization`, `pitch`) remplies par les
  **sorties d'étapes** ; l'utilisateur peut aussi les éditer directement.
- **Historique** : les champs marqués `tracked` dans le contenu produisent
  une révision (ancienne/nouvelle valeur, étape source, raison facultative).
  Affichage léger : « Avant / Maintenant » à la demande.
- **Maturité** (`exploration → validation → construction → préparation →
  lancement`) : calculée par règles de contenu à partir des quêtes et preuves.
- **Niveau de préparation** : 7 dimensions (problème, client, validation,
  offre, business model, finance, lancement), chacune calculée par critères
  explicites et affichée avec « ce qui manque ». Libellé imposé par le
  contenu : il mesure la complétude et la solidité du travail, **jamais une
  probabilité de réussite**.
- **Business Model Canvas** : vue de synthèse calculée à partir des
  sections ; les cases se remplissent au fil du parcours ; jamais présenté
  comme neuf cases vides au départ.
- **Dossier entrepreneurial** : assemblé à partir des sections remplies ;
  une section vide reste vide avec un renvoi vers l'étape qui la construit.
  Aucun bouton ne « fabrique » le dossier. Export PDF local (Phase 7).

## 8. Gamification

- Badges définis dans le contenu par règles sur événements/compteurs
  (ex. `hypothesis.invalidated ≥ 1` ⇒ « Chercheur de vérité » ; `interview
  ≥ 5` ; première expérience terminée ; première vente documentée).
- Récompense l'action, l'expérimentation et la validation — pas la lecture.
  Le validateur de contenu interdit un badge basé uniquement sur des étapes
  `learn`.
- Célébrations courtes, désactivables ; pas de classement, pas de série
  quotidienne punitive.
- Outils débloqués progressivement par règles (`tool_unlock`), toujours
  accessibles en lecture d'aide.

## 9. Voix et IA

- **Capture audio offline** partout où une réponse texte est possible.
- **Transcription** : service optionnel online via Edge Function (proxy
  remplaçable) ; indiqué clairement « nécessite une connexion » ; le malagasy
  peut ne pas être supporté (risque R3).
- **IA** : interface `AiAssistant` avec implémentation `Disabled` par
  défaut ; usages autorisés : reformuler une question, synthétiser des notes,
  détecter des incohérences, traduire un brouillon. Avant chaque usage :
  « une règle ou un contenu suffit-il ? ». Envoi de texte privé uniquement
  après consentement explicite par usage (voir
  [SECURITY §13](SECURITY.md#13-ia-et-services-externes)).

## 10. Finance (principes)

- Montants en **entiers d'ariary** (`int`, pas de `double`) ; affichage
  « 15 000 Ar ».
- Calculateurs pédagogiques déterministes (coût unitaire, prix, marge,
  seuil de rentabilité, trésorerie mensuelle) dans le domaine, couverts par
  des tests avec cas limites (marge négative, volume nul, arrondis).
- Exemples chiffrés réalistes fournis par le contenu (révisables), jamais
  codés en dur.
