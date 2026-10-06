# Eripoo — Plan de développement

Chaque phase est : implémentée → testée → vérifiée → documentée → **validée
par le porteur du projet** avant la suivante. Une phase n'est « terminée »
que selon la Definition of Done du cahier des charges (§56).

---

## Phase 0 — Architecture et fondations

### Réalisé

| Élément | État |
|---|---|
| Documents d'architecture (6 fichiers dans `docs/`) | ✅ v1 rédigée, orientation validée ; **v2 (revue ciblée) à valider** |
| Projet Flutter Android (Flutter 3.47.6, minSdk 24) | ✅ créé — identifiant `mg.eripoo.eripoo` **provisoire** (D6) |
| Lints stricts | ✅ `flutter analyze` : 0 problème |
| i18n de l'interface mg/fr/en (gen-l10n) + repli français des composants Flutter pour `mg` | ✅ testé (4 tests) |
| Sauvegarde Android et transfert d'appareil désactivés | ✅ écrit — **non vérifié par un build Android** (pas de SDK Android dans l'environnement de développement) |
| CI GitHub Actions (format, analyze, test, build APK debug) | ✅ écrite — **pas encore exécutée** |
| Résolution de l'ensemble des dépendances cibles (projet de test séparé, dont `sodium` 4.1.1+2) | ✅ compatibles |

### Revue ciblée v2 (documentaire, aucun code ajouté)

- **Clés et chiffrement** : trois secrets distincts (authentification, clé
  de données UMK, clé de récupération RK) ; cycle de vie complet (génération,
  Keystore, données locales, données synchronisées, récupération, mot de
  passe, changement de téléphone, plusieurs appareils, perte du téléphone,
  perte du code, récupération du compte, suppression) ; bibliothèque unique
  **libsodium** au lieu de `cryptography` ; transfert entre appareils par
  double QR sans serveur ; packs de contenu signés.
- **Synchronisation simplifiée** : plus d'horloges logiques, plus de fusion
  par champ, plus de table d'outbox ni de table d'opérations serveur ;
  compteur de versions par utilisateur ; copies de conflit synchronisées ;
  justification du développement interne.
- **Malagasy** : système de localisation du contenu propre à Eripoo (sans
  `intl`), malagasy présélectionné, stratégie de localisation complète des
  composants Flutter.
- **Vie privée** : trois catégories (données privées / métadonnées
  techniques / analytics).
- **Séparation contenu / interface** confirmée et bornée.
- **Région Supabase** : analyse comparative et protocole de mesure, sans
  choix arbitraire.
- **Identifiant Android** : documenté comme provisoire.
- `DATA_MODEL.md` et `PRODUCT_ARCHITECTURE.md` mis en cohérence (tables de
  sync, enveloppes de clé, signature des packs, liens).

## Phases suivantes

Ordre du cahier des charges conservé, avec deux ajustements ⚠️ :

1. **Le socle de sync (table `sync_meta`, marquage à l'écriture,
   enveloppes chiffrées) est construit en Phase 2** avec la base locale, car
   la migration invité → compte en dépend ; la Phase 5 garde le moteur
   réseau complet et les tests de faute.
2. **Le format de contenu, sa signature et l'évaluateur de règles sont
   posés en Phase 2** (le diagnostic est du contenu), enrichis en Phase 3.

| Phase | Contenu | Critères de sortie |
|---|---|---|
| **1 — Design system** | tokens clair/sombre, composants (boutons, cartes, champs, progression, badges, navigation adaptative, modales, états loading/error/offline, bloc d'aide anti-blocage), `AdaptiveScaffold`, go_router (shell 5 onglets, sans faux contenu), Riverpod, logger expurgé, `EripooFormatter` (mg/fr/en), **inventaire des chaînes Material visibles** | tests de widget clair/sombre × 2 tailles × 3 langues, `meetsGuideline`, aucune couleur ni chaîne littérale hors tokens/ARB (CI), test sur appareil de référence |
| **2 — Onboarding + diagnostic + socle données** | Drift chiffré (sqlite3mc), `sync_meta`, `CryptoService` libsodium, UMK/DBK + Keystore, format de contenu + `ContentLocalizer` + évaluateur de règles + validateur + signature, pack `diagnostic`, choix de langue (mg présélectionné), profil invité, création du projet, Supabase (migrations, RLS, `user_keys`, `devices`, `profiles`, `consents`), comptes e-mail/Google/téléphone, code de récupération, migration invité → compte | onboarding + diagnostic complets hors ligne ; migration sans perte ; vecteurs de test crypto ; tests pgTAP RLS ; tests d'intégration onboarding/compte |
| **3 — Ma quête** | planificateur, exécuteur d'étapes générique, missions, progression, anti-blocage, premières quêtes réelles relues | parcours de bout en bout hors ligne ; règles testées |
| **4 — Projet** | sections, historique, observations, interviews, hypothèses → décisions, preuves, médias chiffrés | machine d'états testée exhaustivement |
| **5 — Offline + sync** | RPC, moteur, conflits (UI), corbeille, médias, WorkManager, transfert QR, révocation d'appareil | les 14 scénarios d'OFFLINE_SYNC §13 passent (faux serveur **et** Supabase local) |
| **6 — Outils** | déblocage progressif | — |
| **7 — Finance, business model, documents** | calculateurs, canvas de synthèse, dossier, export PDF | calculs testés aux limites |
| **8 — Formalisation Madagascar** | contenu réglementaire sourcé et daté | 100 % des informations avec source et date |
| **9 — Voix + IA limitée** | transcription optionnelle, proxy IA, consentements | désactivable, rien n'est envoyé sans consentement |
| **10 — Production** | budgets de performance mesurés, localisation Material/Cupertino `mg` complète, revue cryptographique externe, audit sécurité, accessibilité, validation juridique, back-office | checklist de release complète |

## Décisions

### Validées (sous réserve de votre confirmation de la v2)

| # | Décision |
|---|---|
| V1 | Stack Flutter / Riverpod / go_router / Drift / Supabase |
| V2 | Offline-first, base locale source de vérité |
| V3 | Principe : aucun membre du personnel (administrateur Supabase ou Eripoo) ne peut déchiffrer le contenu privé ⇒ chiffrement de bout en bout |
| V4 | Contenu, missions, règles et traductions séparés du code d'interface |
| V5 | Malagasy langue native ; système de localisation du contenu propre à Eripoo |

### Nécessitant encore votre accord

| # | Décision | Recommandation | Alternative | Coût de changement ultérieur |
|---|---|---|---|---|
| **D1** | Modèle de récupération | **A** : code de récupération + transfert QR, sans séquestre | B : + séquestre à double contrôle (garantie affaiblie, à annoncer) | faible : B s'ajoute sans migration |
| **D2** | Accepter que « tous appareils + code perdus ⇒ copie en ligne illisible » | accepter, avec UX de récupération soignée | B dès le MVP | — (décision produit) |
| **D3** | Synchronisation interne simplifiée (v2) | **oui** | PowerSync (pertinent seulement sans E2EE) | élevé après lancement |
| **D4** | Base locale chiffrée (sqlite3mc) ; verrou applicatif **optionnel** | oui ; proposer le verrou à l'onboarding sans l'imposer | verrou obligatoire ; base non chiffrée | moyen |
| **D5** | Contenu en YAML dans le dépôt jusqu'à la Phase 6, back-office ensuite | oui | back-office dès la Phase 3 | faible |
| **D6** | Identifiant Android définitif | basé sur un domaine que vous possédez, à fixer **avant la création de l'app dans la Play Console** | — | **irréversible** après création Play |
| **D7** | Analytics opt-in, sans identifiant, auto-hébergés | oui | opt-out ; outil tiers | moyen |
| **D8** | Rapports de crash maison (sans message d'exception) | oui au départ | Sentry | faible |
| **D9** | Région Supabase | décider après mesures et avis juridique (ARCHITECTURE §14) ; présélection Paris / Francfort, Mumbai témoin | — | élevé |
| **D10** | Fournisseur SMS (OTP) | après test de délivrabilité et de coût vers les opérateurs malgaches | téléphone après e-mail/Google | moyen |
| **D11** | Appareils de référence | 2 vrais appareils achetés localement (Android 7–10, 1–2 Go, 32 bits) | émulateurs seuls | — |
| **D12** | Analyse juridique (mineurs, loi 2014-038, transferts hors de Madagascar, mentions) | avant la Phase 2 pour l'onboarding des mineurs ; complète avant production | — | élevé si tardive |
| **D13** | Relecteurs natifs malagasy (contenu, interface, composants Flutter, formats de date) | désigner dès la Phase 1 | — | — |
| **D14** | Langue de rédaction du contenu | co-rédaction malagasy + français par des auteurs natifs ; anglais traduit et relu | rédaction en français puis traduction | moyen |
| **D15** | Plafond par média (chiffrement en une opération) | 10 Mo (photos réduites ; audio ≈ 20 min, interviews en plusieurs parties) | plus haut avec un format de flux libsodium (`secretstream`) | faible |
| **D16** | Bibliothèque cryptographique | libsodium via `sodium` 4.1.1+2 | Tink via canal natif Android | moyen |

## Recommandation pour la Phase 1

**GO pour la Phase 1 (design system), dès validation de cette v2.**

- La Phase 1 ne touche ni aux clés, ni à la sync, ni à Supabase, ni au
  contenu : **aucune des décisions D1–D16 ne la bloque**.
- D11 (appareils de référence) et D13 (relecteur malagasy) **l'améliorent**
  sans la bloquer : sans eux, les tests sur appareil réel et la relecture
  des libellés malagasy du design system resteront signalés comme « non
  vérifiés ».
- **NO-GO pour la Phase 2** tant que D1, D2, D3, D4, D12 (au moins le volet
  mineurs) et la vérification de licence de sqlite3mc ne sont pas tranchés.
  D6 et D9 doivent l'être avant toute mise en ligne publique.
