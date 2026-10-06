# Eripoo — Sécurité et confidentialité

Principe : **le projet appartient à l'utilisateur.** Les données privées d'un
projet ne sont considérées comme accessibles à **personne** chez Eripoo,
administrateurs compris. Ce document décrit comment l'architecture le
garantit techniquement, et ce qu'elle ne garantit pas.

Statut : conception. Implémenté en Phase 0 : désactivation de la sauvegarde
Android (`allowBackup="false"` + règles d'extraction excluant toutes les
données). Tout le reste est à venir.

⚠️ Ce document ne constitue pas un avis juridique. Le cadre légal malgache
(protection des données, mineurs) et celui des autres juridictions n'est
volontairement pas décrit ici : il doit être établi et validé par un juriste
avant la mise en production. L'architecture rend les règles configurables
par juridiction pour pouvoir appliquer ce qui sera validé.

---

## 1. Données et sensibilité

| Catégorie | Exemples | Où | Protection |
|---|---|---|---|
| Contenu privé du projet | réponses, hypothèses, interviews, photos, audio, finances | appareil + `sync_records` / `user-media` | chiffré de bout en bout |
| Données de tiers | notes sur des personnes interviewées, voix enregistrées | idem | idem + pseudonymes recommandés, consentement à l'enregistrement |
| Identité de compte | e-mail, téléphone, identité Google | Supabase Auth | RLS, jamais exposée au back-office |
| Profil minimal | langue, juridiction, tranche d'âge, statut consentement parental | `profiles` | RLS propriétaire |
| Contenu pédagogique | quêtes, missions, traductions | public | intégrité (sha256), édition par rôles |
| Analytics | événements sans identifiant | `analytics_events` | anonymes, agrégés |

## 2. Modèle de menaces

| Menace | Mesure principale |
|---|---|
| Autre utilisateur tente de lire mes données | RLS + RPC vérifiant `auth.uid()` + chiffrement |
| **Personnel Eripoo / administrateur curieux** | chiffrement de bout en bout (§4), aucune politique RLS pour le personnel, back-office sans accès (§5) |
| Fuite ou compromission de la base Supabase | données privées illisibles sans les clés des utilisateurs |
| Téléphone perdu, volé ou **partagé en famille** | base SQLite chiffrée, clés dans Android Keystore, verrou applicatif optionnel ⚠️, sauvegarde Android désactivée |
| Réseau hostile (Wi-Fi public) | HTTPS uniquement, trafic en clair interdit |
| Journaux / rapports de crash qui fuient du contenu | logger expurgé, messages d'exception non transmis (§6) |
| Fournisseur IA / transcription | désactivé par défaut, consentement par usage, proxy sans stockage (§8) |
| Mise à jour malveillante de l'app (chaîne d'approvisionnement) | revue de code obligatoire, dépendances épinglées, signature de release protégée — **limite résiduelle reconnue** (§5.3) |

## 3. Authentification

- **Invité local** : aucun compte, aucune requête réseau ; données sur
  l'appareil uniquement. Proposition de sauvegarde après le début du
  parcours.
- **Méthodes MVP** : e-mail + mot de passe (confirmation d'e-mail), Google
  (SDK natif → `signInWithIdToken`), téléphone (OTP SMS — fournisseur SMS à
  choisir et tester pour Madagascar, risque R4). **Facebook** : présent dans
  l'énumération `AuthProviderKind`, désactivé par configuration.
- **Plusieurs méthodes sur un même compte** : liaison d'identités Supabase
  (`linkIdentity`, `linkIdentityWithIdToken`, `unlinkIdentity` — présentes
  dans `supabase_flutter` 2.18.0, vérifié). Nécessite d'activer la liaison
  manuelle dans la configuration Auth du projet Supabase.
- **Session** : flux PKCE ; **la session n'est pas stockée dans
  SharedPreferences** (comportement par défaut de `supabase_flutter`,
  vérifié dans le code source 2.18.0) mais dans un `LocalStorage`
  personnalisé adossé à `flutter_secure_storage` (Android Keystore).
- Limitation de débit et CAPTCHA côté Supabase Auth sur inscription et envoi
  d'OTP (paramétrage du projet).
- L'authentification ne déverrouille pas les données : le déchiffrement
  dépend de la clé (§4). Se connecter sur un nouvel appareil exige le code
  de récupération ou un transfert depuis un appareil existant.

## 4. Chiffrement de bout en bout

⚠️ **Décision majeure, difficile à inverser une fois des données en
production.** Recommandée car c'est la seule manière *technique* (et pas
seulement organisationnelle) d'empêcher le personnel d'Eripoo de lire les
projets : avec Supabase, quiconque détient un accès propriétaire à la base
ou la clé `service_role` contourne la RLS.

### 4.1 Hiérarchie de clés

```
Clé de récupération RK (128 bits aléatoires, détenue par l'utilisateur)
   └─HKDF─► KEK ──AES-256-GCM──► DEK enveloppée  → user_keys (serveur)

Clé appareil (Android Keystore via flutter_secure_storage)
   └──────────────AES-256-GCM──► DEK enveloppée  → stockage sécurisé local

DEK (256 bits, par utilisateur, versionnée)
   ├─► chiffre chaque payload de sync_records (AES-256-GCM)
   └─► enveloppe une clé par fichier média (AES-256-GCM, segments de 64 Ko)

Clé de base locale (256 bits, Keystore) ─► SQLite3MultipleCiphers
```

- AAD (données authentifiées) de chaque payload : `id || key_version ||
  schema_version` — empêche de déplacer un payload chiffré d'un
  enregistrement à un autre.
- Nonces aléatoires de 96 bits, jamais réutilisés.
- Algorithmes via `cryptography` 2.9.0 (`AesGcm`, `Hkdf`, `Argon2id`
  disponibles, vérifié) avec accélération native `cryptography_flutter`.
  Aucune primitive maison.
- Chiffrement exécuté hors du thread UI (isolat).

### 4.2 Création

La DEK est générée **dès le premier lancement** (invité compris) : la base
est chiffrée immédiatement et l'inscription n'a qu'à envelopper la DEK
existante avec une RK nouvellement créée.

### 4.3 Code de récupération

Affiché à l'inscription sous forme de code groupé (ex. `K7Q2-…`, alphabet
sans caractères ambigus) et de QR, avec possibilité de l'imprimer ou de le
recopier ; vérification par ressaisie partielle ; rappel ultérieur doux s'il
n'a pas été confirmé.

### 4.4 Transfert entre appareils

L'appareil existant affiche un QR contenant une clé éphémère ; le nouvel
appareil la scanne ; la DEK est transmise chiffrée via un échange de clés
éphémère (X25519) relayé par le serveur. Le serveur ne voit jamais la DEK en
clair.

### 4.5 Ce que l'utilisateur doit accepter

**Si l'utilisateur perd tous ses appareils ET son code de récupération, la
copie en ligne de son projet est illisible, définitivement — y compris pour
Eripoo.** C'est le prix de la garantie. Options, à trancher (D1) :

| Option | Garantie « admins ne peuvent pas lire » | Risque de perte |
|---|---|---|
| **A. E2EE + code de récupération** (recommandée) | technique, forte | réel pour les utilisateurs qui perdent le code |
| B. A + séquestre de récupération à double contrôle (DEK aussi enveloppée par une clé de séquestre conservée hors ligne, scindée entre 2 personnes, utilisée uniquement à la demande de l'utilisateur après vérification d'identité) | affaiblie : une collusion interne permettrait la lecture ; doit être dit honnêtement | faible |
| C. Pas d'E2EE, RLS + règles internes | organisationnelle seulement : **ne satisfait pas l'exigence 13** | nul |

B peut être ajoutée plus tard **sans migration** (c'est une enveloppe
supplémentaire de la même DEK) : commencer par A ne ferme aucune porte.

### 4.6 Conséquences assumées

- Pas de recherche ni d'agrégation serveur sur le contenu privé (non
  souhaitées de toute façon).
- Fusion des conflits côté client ([OFFLINE_SYNC §4](OFFLINE_SYNC.md#4-résolution-des-conflits)).
- Export et génération de documents faits sur l'appareil.
- Support utilisateur : le personnel ne peut pas « regarder le projet » pour
  aider ; il faut des outils de diagnostic sans contenu.

## 5. Isolation des administrateurs

### 5.1 Couches

1. **Cryptographique** : §4.
2. **RLS** : aucune politique accordant au personnel l'accès à
   `sync_records`, `user_keys`, `consents`, `profiles` d'autrui ni au bucket
   `user-media`. Tests pgTAP qui le vérifient (un utilisateur ayant chaque
   rôle du personnel obtient 0 ligne).
3. **Back-office** : authentifié par JWT utilisateur + `staff_roles` ; ne
   reçoit jamais la clé `service_role` ; ses écrans se limitent au contenu,
   aux traductions, aux badges, aux outils, aux ressources, aux informations
   administratives, aux statistiques agrégées et à la santé technique.
   **Aucun écran de recherche ou de consultation d'utilisateur ou de
   projet.**
4. **Clé `service_role`** : uniquement dans les secrets des Edge Functions
   (suppression de compte, ingestion analytics) ; jamais dans l'app, le
   dépôt ou le back-office.
5. **Accès au tableau de bord Supabase** : 2 personnes maximum, MFA
   obligatoire, journal d'audit ; les actions du back-office sont tracées
   dans `audit_log`.

### 5.2 Ce que le personnel peut encore voir (honnêtement)

Adresse e-mail ou numéro de téléphone du compte, dates de création et de
dernière activité, nombre et taille des enregistrements chiffrés, horodatages
serveur. Ces métadonnées sont minimisées (le type d'entité et le projet sont
dans le chiffré) et ne sont exposées dans aucun outil interne.

### 5.3 Limite résiduelle

Le chiffrement de bout en bout protège contre la lecture des données
stockées. Il ne protège pas contre une **version malveillante de
l'application** qui exfiltrerait les données au moment où elles sont
déchiffrées sur l'appareil. Mesures : revue de code obligatoire sur la
branche principale, CI qui construit les releases, clé de signature protégée,
dépendances épinglées (`pubspec.lock` commité). Builds reproductibles à
étudier en Phase 10.

## 6. Journaux, erreurs, stockage local

- **Logger expurgé** (`core/logging`) : seuls des codes d'événement, des
  identifiants techniques et des durées sont journalisés. Interdits : textes
  saisis, noms, e-mails, téléphones, jetons, chemins de médias, payloads.
  Test automatique : un jeu de « données sentinelles » écrites dans l'app ne
  doit apparaître dans aucune sortie de log.
- **Rapports d'erreur** : type d'exception + pile d'appels + version ;
  **le message d'exception n'est pas transmis** (il peut contenir une saisie,
  ex. `FormatException`). Envoi via l'Edge Function d'analytics, sans
  identifiant d'utilisateur. Pas de SDK de crash tiers au départ ⚠️.
- `print`/`debugPrint` interdits par lint (`avoid_print`, en place).
- Base locale chiffrée (SQLite3MultipleCiphers via l'option de hook
  `sqlite3` ; licence à vérifier avant release) ; médias chiffrés ; fichiers
  temporaires d'export supprimés après partage.
- Sauvegarde Android désactivée (**fait**) : sinon la base irait dans la
  sauvegarde Google Drive de l'utilisateur ou dans un transfert d'appareil.
- Verrou applicatif (PIN / biométrie) optionnel pour téléphones partagés ⚠️
  (dépendance `local_auth` à ajouter si validé).

## 7. Analytics anonymisés

- Consentement : ⚠️ proposition **opt-in** au cours de l'onboarding (choix
  clair, modifiable dans Profil), compte tenu d'un public pouvant être
  mineur. À valider juridiquement.
- **Aucun identifiant** : ni `user_id`, ni identifiant d'appareil, ni
  identifiant publicitaire. Chaque événement porte seulement : nom, propriétés
  énumérées, version d'app, langue, **jour** (pas l'heure), semaine
  d'installation (cohorte), tranche d'ancienneté.
- Liste blanche d'événements et de propriétés définie dans le code et
  revalidée par l'Edge Function (tout le reste est rejeté). Exemples :
  `onboarding_completed`, `diagnostic_profile{profile}`,
  `step_completed{quest_id, step_id}`, `step_deferred{…}`,
  `help_used{level}`, `mission_completed{mission_template_id}`,
  `hypothesis_status_changed{from,to}`, `tool_opened{tool_id}`,
  `sync_failed{error_code}`, `app_start{cold_ms_bucket}`. Les identifiants
  sont ceux du **contenu public**, jamais du contenu privé.
- Envoi par lots, au plus une fois par jour, en ligne uniquement.
- L'Edge Function ne stocke pas l'adresse IP ; noter que l'infrastructure
  Supabase peut journaliser les IP des requêtes au niveau de la plateforme
  (à vérifier dans sa documentation et à mentionner dans la politique de
  confidentialité).
- Rétention : événements bruts 90 jours, puis agrégats journaliers.
- Tableaux de bord : uniquement des agrégats ; cellules de moins de 10
  occurrences masquées.
- Conséquence assumée : on mesure des entonnoirs agrégés par cohorte, pas des
  parcours individuels.

## 8. IA et services externes

- Interface `AiAssistant` / `TranscriptionService` avec implémentation
  « désactivée » par défaut ; fournisseur remplaçable derrière une Edge
  Function proxy (clé fournisseur côté serveur uniquement).
- Envoi de texte ou d'audio privé **uniquement après consentement explicite
  pour cet usage**, avec indication de ce qui sera envoyé ; le proxy ne
  stocke rien et le contrat fournisseur doit exclure l'entraînement sur les
  données (à vérifier au choix du fournisseur).
- Indication claire « nécessite une connexion ».

## 9. Mineurs

- Déclaration d'âge à l'onboarding (année de naissance, conservée chiffrée ;
  seule la tranche `under_min / minor / adult` est connue du serveur).
- Règles lues depuis `jurisdiction_policies` (âge minimum, âge en dessous
  duquel un consentement parental est requis, champ `legal_validated`).
  **Aucune valeur n'est fixée dans le code** ; tant que `legal_validated =
  false`, la mise en production est bloquée par la checklist de release.
- Le parcours pédagogique est identique pour mineurs et majeurs ; seuls
  changent les consentements, l'analytics (désactivé par défaut) et les
  fonctions IA (désactivées sans consentement adapté).
- Flux de consentement parental : conçu en Phase 2 une fois les exigences
  juridiques connues (la méthode de vérification dépend du droit
  applicable).

## 10. Droits de l'utilisateur

- **Export** : sur l'appareil, données déchiffrées en JSON + médias, et
  dossier lisible (PDF) ; aucune dépendance au serveur.
- **Suppression du compte** : depuis l'app ; Edge Function qui supprime les
  objets `user-media/{uid}`, puis l'utilisateur Auth (cascade sur
  `sync_records`, `user_keys`, `profiles`, `consents`) ; trace minimale dans
  `deletion_requests`. Les données locales sont effacées après
  confirmation serveur.
- **Suppression d'un élément** : tombstone synchronisée ; purge du payload
  serveur.
- **Consentements** versionnés et révocables (`consents`, append-only).
- Politique de confidentialité en fr/mg/en, rédaction à valider
  juridiquement.

## 11. Validation et durcissement

- **Client** : validation de domaine (longueurs, énumérations, montants
  entiers ≥ 0 quand pertinent) avant toute écriture.
- **Serveur** : contraintes Postgres, RPC qui valident taille, versions et
  quotas, limitation de débit ; Edge Functions validant chaque entrée.
- **Secrets** : URL Supabase et clé `anon` (publique par conception, la RLS
  protège) injectées par `--dart-define-from-file` depuis un fichier non
  commité ; secrets CI dans GitHub ; secrets serveur dans Supabase. Aucune
  clé privée dans l'application.
- **Android** : trafic en clair interdit explicitement (minSdk 24 < API 28
  où c'est le défaut), release obfusquée, pas de WebView exécutant du
  contenu distant, permissions demandées au moment de l'usage (micro, caméra,
  notifications).
- **Revue sécurité** à chaque phase touchant auth, sync, stockage ou
  serveur ; audit externe recommandé avant la production (Phase 10).
