# Eripoo — Reprise du projet : ce qui reste à faire

État au 2026-10-22. Les dix phases du cahier des charges sont livrées (code,
tests, docs) sur la branche `claude/nifty-mccarthy-a74111`, PR n° 1 en
brouillon. Dernière CI complète verte sur 315a6df ; 667 tests locaux verts
sur d5ac011. **Rien n'a été vérifié sur un vrai téléphone ni sur un serveur
Supabase en ligne.**

Ce document découpe le reste en chantiers indépendants. Chaque chantier
« code » se fait dans **un nouveau chat** : copier son message de départ.
Les consignes générales (règles, commandes, conventions) sont dans
[CLAUDE.md](../CLAUDE.md), lu automatiquement par chaque chat.

## 0. Avant tout : fusionner la PR n° 1

`main` ne contient que le commit initial. Un nouveau chat part de `main` :
sans fusion, il ne verrait rien du travail fait. Relire puis fusionner la
PR n° 1 dans `main` (le libellé « ne pas fusionner » datait de la revue des
phases). Ensuite, un chantier = une branche = une PR.

## 1. Ce que seul le porteur peut fournir

| # | Quoi | Débloque | Obligatoire ? |
|---|---|---|---|
| P-1 | **Projet Supabase de développement** (`eripoo-dev`, plan gratuit, région Paris ou Francfort ; MFA sur le compte) | C-1, toute la synchronisation réelle | oui |
| P-2 | **Au moins un vrai téléphone Android**, idéalement d'entrée de gamme (1 Go de RAM, appareil A) ; un second pour les tests à deux téléphones | toutes les vérifications V-1 | oui (un suffit pour commencer) |
| P-3 | **Juriste** : politique de confidentialité et CGU, transferts hors de Madagascar (loi 2014-038), durées de conservation | C-12, publication | oui |
| P-3b | Juriste : mineurs 14–17 ans | ouverture aux mineurs | non si la v1 est réservée aux 18 ans et plus |
| P-3c | Juriste : relecture du contenu EDBM (`content/formalization.yaml`) | préparation administrative | non si cet outil est masqué en v1 |
| P-4 | **Relecteur natif malagasy** : 585 chaînes `needs_review` (`lib/l10n/mg_review_status.json`), ~40 chaînes Material, tout le contenu (brouillon automatique) | publication en malagasy | oui (sauf sortie en français d'abord) |
| P-5 | **Auteurs du contenu** : valider quêtes, missions, outils, sections, guide de financement (fr/en), avis d'entrepreneurs malgaches | C-2, publication | oui (peut être le porteur) |
| P-6 | **Décisions** : identifiant Android définitif + domaine (D6), clé d'envoi Play, région de production (D9, après mesures + juriste), âge minimum de la v1, analytics (D7), transcription vocale (aucune ou sur l'appareil) | C-11, C-13, C-14 | oui pour D6, clé, D9, âge |
| P-7 | Audit de sécurité et revue cryptographique par un tiers | ouverture au grand public | non pour un test fermé |
| P-8 | Informations de financement vérifiées et sourcées (organismes, taux) | guide de financement enrichi | non |

## 2. Chantiers de code (un chat chacun)

Ordre conseillé : C-1, puis C-2 en continu (le plus gros), puis le reste
selon les priorités. Entre parenthèses : dépendance, taille estimée.

### C-1. Brancher le Supabase de développement (P-1 ; petit)
> Lis CLAUDE.md et docs/NEXT_STEPS.md (chantier C-1). Crée un workflow
> GitHub **manuel** (`workflow_dispatch`) qui applique les migrations
> `supabase/migrations/` au projet de développement (`supabase link` +
> `supabase db push`) puis construit une APK release « dev » branchée dessus
> (`--dart-define-from-file` généré depuis les secrets, `ERIPOO_ENV=development`)
> et la publie en artefact. Secrets attendus : SUPABASE_ACCESS_TOKEN,
> SUPABASE_PROJECT_REF, SUPABASE_DB_PASSWORD, SUPABASE_URL, SUPABASE_ANON_KEY.
> Ajoute un second job manuel qui lance les tests de contrat RPC
> (`test/contract/`) contre ce projet. Documente la procédure dans
> docs/DEVELOPMENT_PLAN.md (P4). Aucun secret dans Git.

### C-2. Contenu : quêtes et missions manquantes (P-5 pour validation ; gros)
Le cahier des charges (§7) demande au moins 16 quêtes ; il y en a 4
(`content/quests/q01`–`q04`) plus le diagnostic, et 2 missions seulement
(`content/missions/missions.yaml`). À faire par lots de 3 ou 4 quêtes.
**Lot 1 fait (2026-10-22)** : q05 concurrence, q06 offre (nouvelle section
`offer`, absente du dossier PDF pour l'instant), q07 modèle économique, q08
premiers chiffres, et 3 missions. **Lot 2 fait (2026-10-22)** : q09 tester
l'offre (prévente), q10 préparer le lancement, q11 formalités (renvoie à
l'outil sourcé, aucune règle énoncée), q12 lancement réel, et 2 missions.
Restent (lot 3, quêtes d'avant q01 pour les profils « aucune idée », à
placer dans l'ordre) : comprendre l'entrepreneuriat, observer son
environnement, découvrir une opportunité.
> Lis CLAUDE.md, docs/PRODUCT_ARCHITECTURE.md et content/. Écris le lot
> suivant de quêtes manquantes parmi les 16 du cahier des charges (§7) :
> comprendre l'entrepreneuriat, observer son environnement, découvrir une
> opportunité, formuler et tester des hypothèses, construire une offre,
> marché et concurrence, business model, finances, tester l'offre,
> préparer le lancement, formalisation, lancement réel — en réutilisant les
> outils et écrans existants (BMC, finances, préparation administrative)
> plutôt qu'en les dupliquant. Ajoute les missions associées (actions
> réelles, hors de l'app). fr et en complets, mg en brouillon marqué à
> relire. Aucune information réglementaire non sourcée. Valide avec
> `dart run tool/content_build.dart` et les tests de contenu.

### C-3. Badges (§21 ; moyen)
> Lis CLAUDE.md et docs/END_CHECKLIST.md §4. Construis les badges du
> cahier des charges §21 : récompenser l'action, l'expérimentation, la
> validation (une hypothèse invalidée peut être récompensée, ex. « Chercheur
> de vérité »), jamais la seule consommation de contenu, pas de classement.
> Définis-les dans le contenu avec le même langage de règles et le même
> validateur que les outils (`content/tools.yaml`), une table synchronisée
> comme `tool_unlocks`, jamais retirés, célébration désactivable.

### C-4. Notification « Nouvel appareil ajouté » (C-1 ; moyen)
> Lis CLAUDE.md et docs/SECURITY.md §6.8. L'événement est enregistré côté
> serveur mais rien n'est envoyé. Affiche-le dans l'app sur les autres
> appareils (à la synchronisation, sans contenu privé) et prépare l'envoi
> d'un e-mail (Edge Function ou hook Supabase), testable sur le projet de
> développement uniquement.

### C-5. Verrou Eripoo comme confirmation d'identité (petit)
> Lis CLAUDE.md et docs/END_CHECKLIST.md §4. Quand le téléphone n'a pas de
> verrouillage d'écran, les actions sensibles (code de récupération,
> transfert, rotation de clé, suppression du compte) doivent pouvoir être
> confirmées par le verrou applicatif Eripoo (PIN) au lieu d'être bloquées.

### C-6. Chapitre « Marché » du dossier (lié à C-2 ; moyen)
> Lis CLAUDE.md et docs/END_CHECKLIST.md §4. Le dossier entrepreneurial n'a
> pas de chapitre « Marché » car aucune quête ne recueille ces données.
> Ajoute les questions dans le contenu (taille, clients, concurrents en
> réutilisant l'analyse concurrentielle existante) et le chapitre au
> dossier et au PDF, sans chiffre de marché inventé.

### C-7. Proposer l'export PDF avant la suppression du compte (petit)
> Lis CLAUDE.md. Dans le flux de suppression de compte
> (`lib/features/account/`), propose d'exporter le dossier en PDF avant de
> confirmer. Tests de widget.

### C-8. Mesure de latence pour choisir la région (C-1 ; petit)
> Lis CLAUDE.md et docs/DEVELOPMENT_PLAN.md P5. Ajoute à l'APK de
> développement seulement un écran de mesure de latence vers le projet
> Supabase (≥ 100 mesures, médiane, 95ᵉ centile, type de réseau) exportable,
> pour le rapport de mesures depuis Madagascar. Jamais dans la version de
> production.

### C-9. Préparation administrative à compléter (P-3c ; moyen, recherche)
> Lis CLAUDE.md et content/formalization.yaml. Complète avec des sources
> officielles datées : entreprise individuelle, régions autres
> qu'Analamanga, sources fiscales et CNaPS, codes d'activité. Tout ce qui
> n'est pas sourcé reste NON VÉRIFIÉ. Lance `dart run tool/check_sources.dart`.

### C-10. Rappels locaux (§46 ; moyen, facultatif pour la v1)
> Lis CLAUDE.md. Ajoute des rappels locaux facultatifs pour les missions
> en cours (sans serveur, sans harcèlement, désactivables, sans contenu
> privé sur l'écran verrouillé). Attention : la permission
> POST_NOTIFICATIONS a été retirée exprès ; mettre à jour
> `tool/check_apk.sh` et `test/architecture/android_release_test.dart`.

### C-11. Pipeline de release (P-6 : D6 et clé Play ; moyen)
> Lis CLAUDE.md et docs/RELEASE_CHECKLIST.md. Crée un workflow manuel qui
> construit l'App Bundle signé (clé depuis les secrets GitHub d'un
> environnement protégé), obfusqué, symboles archivés en artefact privé,
> avec `tool/check_apk.sh` sur les APK extraites. Change l'identifiant
> Android pour la valeur décidée.

### C-12. Textes légaux dans l'app (P-3 ; petit)
> Lis CLAUDE.md. Intègre la politique de confidentialité et les CGU fournies
> par le juriste (mg/fr/en), l'acceptation à l'onboarding et à la mise à
> jour des textes, et les valeurs de `jurisdiction_policies`.

### C-13. Analytics opt-in et rapports d'erreurs (P-6 : D7 ; moyen)
> Lis CLAUDE.md et docs/DEVELOPMENT_PLAN.md (D7, D8). Analytics opt-in,
> sans identifiant, sans contenu privé, auto-hébergés, et rapports d'erreurs
> maison. Ne pas commencer sans la décision D7 écrite.

### C-14. Production (P-3, P-6 : D9 ; gros — pas avant décision)
Environnement Supabase de production, édition du contenu hors du dépôt
(D5) et back-office (§44 : contenu, traductions, statistiques agrégées,
santé technique, jamais d'accès aux projets privés).

Facultatifs (« éventuellement » dans le cahier des charges) : niveau de
préparation (§23), aide à la recherche d'associés (§48), plusieurs
scénarios de prix.

## 3. Vérifications (après P-1 et P-2)

- **V-1, sur téléphone** : procédure complète dans
  [DEVICE_TESTS.md](DEVICE_TESTS.md) et [END_CHECKLIST.md](END_CHECKLIST.md)
  §2 (démarrage, mémoire, Argon2id, caméra et QR, micro, biométrie,
  transfert entre deux téléphones, rotation de clé, TalkBack, PDF).
- **V-2, sur Supabase en ligne** : END_CHECKLIST §3 (contrat RPC, RLS,
  synchronisation réelle, révocation, déconnexion, suppression de compte).
- **V-3, avant release** : lancer à la main les jobs Android de la CI et
  dérouler [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
