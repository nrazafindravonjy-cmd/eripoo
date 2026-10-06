# Eripoo — Plan de développement

Chaque phase est : implémentée → testée → vérifiée → documentée → **validée
par le porteur du projet** avant la suivante. Une phase n'est « terminée »
que selon la Definition of Done du cahier des charges (§56).

---

## Phase 0 — Architecture et fondations

### Réalisé

| Élément | État |
|---|---|
| Documents d'architecture (6 fichiers dans `docs/`) | ✅ v1 et v2 validées dans leur orientation ; **v3 (clarification sécurité) à valider** |
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
| **D2** | Accepter que « tous appareils + code perdus ⇒ copie en ligne illisible » (option A) | accepter, avec fiche de secours et rappels ; séquestre B ajoutable plus tard sans migration | Phase 2 |
| **D4** | Verrou Eripoo (PIN/biométrie) : optionnel ou obligatoire | optionnel, proposé à l'onboarding, fortement suggéré si le téléphone n'a pas de verrouillage d'écran | Phase 2 |
| **D5** | Contenu en YAML dans le dépôt jusqu'à la Phase 6 | oui | Phase 3 |
| **D6** | Identifiant Android définitif (domaine possédé) | à fixer avant la création de l'app dans la Play Console | publication |
| **D7** | Analytics opt-in, sans identifiant, auto-hébergés | oui | Phase 2 (onboarding) |
| **D8** | Rapports de crash maison | oui au départ | — |
| **D9** | Région Supabase | après mesures depuis Madagascar et avis juridique (ARCHITECTURE §14) | création du projet Supabase de production (un projet de développement peut être créé avant) |
| **D10** | Fournisseur SMS (OTP) | après test de délivrabilité et de coût | connexion par téléphone |
| **D11** | Appareils de référence | 2 vrais appareils (Android 7–10, 1–2 Go, 32 bits) | mesures de la Phase 2 |
| **D12** | Analyse juridique (mineurs, loi 2014-038, transferts hors de Madagascar) | volet mineurs avant la Phase 2 | Phase 2 (onboarding des mineurs) |
| **D13** | Relecteurs natifs malagasy | dès la Phase 1 | — (améliore la Phase 1) |
| **D14** | Langue de rédaction du contenu | co-rédaction mg + fr par des auteurs natifs | Phase 3 |
| **D15** | Plafond de 10 Mo par média | oui | Phase 4 |
| **D17** | Rotation de l'UMK avant le lancement public | oui (Phase 10) | lancement public |

## Portes

### Phase 1 — **GO recommandé**

Aucune décision ouverte ne la bloque : la Phase 1 ne touche ni aux clés, ni
à la sync, ni à Supabase, ni au contenu. Sans D11 et D13, les tests sur
appareil réel et la relecture malagasy des libellés resteront signalés comme
« non vérifiés ».

### Phase 2 — conditions

- [ ] D2 et D4 tranchés
- [ ] D12, volet mineurs (au moins le principe du consentement parental)
- [ ] D11 : appareils de référence disponibles (mesures Argon2id et base)
- [ ] Licence sqlite3mc revérifiée sur l'étiquette exacte livrée (2.5.0) et
      liste des mentions de licences validée
- [ ] Projet Supabase **de développement** créé (la région de production,
      D9, peut attendre)
