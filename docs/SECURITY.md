# Eripoo — Sécurité et confidentialité

Principe : **le projet appartient à l'utilisateur.** Le contenu privé d'un
projet n'est accessible à **personne** chez Eripoo — administrateurs
Supabase et personnel Eripoo compris — et cela doit être garanti par la
cryptographie, pas seulement par des règles internes.

Statut : conception (revue Phase 0, v2). Seul élément implémenté :
désactivation de la sauvegarde Android et du transfert d'appareil pour les
données de l'app (`allowBackup="false"` + `data_extraction_rules.xml`).

⚠️ Ce document n'est pas un avis juridique. Madagascar dispose d'une loi
sur la protection des données personnelles (loi n° 2014-038, autorité de
contrôle : CMIL — voir [ARCHITECTURE §14](ARCHITECTURE.md#14-région-dhébergement-supabase)
pour les sources). Son application concrète à Eripoo (mineurs, transferts
hors de Madagascar, déclarations) doit être analysée par un juriste ; aucune
règle n'en est déduite ici.

---

## 1. Trois catégories de données

| | **Données privées du projet** | **Métadonnées techniques** | **Analytics** |
|---|---|---|---|
| Contenu | tout ce que l'utilisateur produit : réponses, projet et ses sections, historique, hypothèses, expériences, résultats, preuves, décisions, observations, interviews (y compris sur des tiers), photos, audio, transcriptions, finances, documents, profil détaillé (nom affiché, année de naissance), progression, badges | identifiants de compte (e-mail, téléphone ou identité Google), `user_id`, appareils (id aléatoire, dates, version d'app), métadonnées de sync (id aléatoires, numéros de version, indicateur de suppression, taille arrondie, horodatages serveur), dates de création des enveloppes de clé, profil minimal (langue, juridiction, tranche d'âge, statut de consentement parental), consentements, journaux d'infrastructure de la plateforme (IP, horodatage de requête) | événements de produit sans identifiant, propriétés énumérées (identifiants de **contenu public** uniquement), jour, version, langue, cohorte d'installation |
| Protection | **chiffrées de bout en bout sur l'appareil** avant tout envoi ; base locale chiffrée | RLS (chacun ne voit que les siennes) ; minimisées par conception | anonymes, agrégées, opt-in |
| Accès du personnel Eripoo | **impossible techniquement** (§5) | **uniquement si nécessaire** (incident, demande de l'utilisateur), réservé au rôle `ops` (2 personnes max, MFA), justifié et journalisé ; jamais exposées dans le back-office | agrégats seulement dans le back-office ; cellules < 10 masquées |
| Rétention | jusqu'à suppression par l'utilisateur | durée de vie du compte (+ sauvegardes de la plateforme) | brut 90 jours, puis agrégats |

Minimisation des métadonnées : le type d'entité, le projet de rattachement,
les dates métier et les relations entre éléments sont **dans le chiffré** ;
les tailles sont arrondies par remplissage (§4.4) ; aucun identifiant n'est
dérivé de données personnelles.

## 2. Modèle de menaces

| Menace | Mesure principale |
|---|---|
| Autre utilisateur tente de lire mes données | RLS + RPC vérifiant `auth.uid()` + chiffrement |
| **Administrateur Supabase / personnel Eripoo** | chiffrement de bout en bout ; le serveur ne détient aucune clé utilisable (§5) |
| Fuite ou vol de la base ou des sauvegardes Supabase | uniquement du chiffré + enveloppes nécessitant le code de récupération |
| Vol de session / prise de contrôle du compte (SIM swap, mot de passe volé) | donne accès au chiffré seulement ; déverrouiller exige un appareil existant ou le code de récupération |
| Téléphone perdu, volé ou **partagé en famille** | base chiffrée, clés dans Android Keystore, verrou applicatif optionnel, révocation à distance (§4.10) |
| Copie du stockage du téléphone (sauvegarde, extraction) | clés non exportables du Keystore ; sauvegarde Android désactivée (fait) |
| Contenu pédagogique falsifié (ex. « envoie ton code de récupération à… ») | packs de contenu **signés** hors ligne, vérifiés par l'app (§13) ; le code de récupération n'est jamais saisi ailleurs que dans l'écran système dédié |
| Réseau hostile | HTTPS uniquement, trafic en clair interdit |
| Journaux / rapports de crash qui fuient | logger expurgé, messages d'exception non transmis (§9) |
| Mise à jour malveillante de l'app | revue de code, CI de release, signature protégée — **limite résiduelle reconnue** (§5.3) |

## 3. Trois secrets distincts

Ils ne doivent jamais être confondus, ni dérivés l'un de l'autre.

| | **Authentification du compte** | **Clé de données (UMK)** | **Clé de récupération (RK)** |
|---|---|---|---|
| Rôle | prouver au serveur « je suis ce compte » ⇒ accès aux enveloppes chiffrées de ce compte (RLS) | chiffrer et déchiffrer tout le contenu privé | permettre de retrouver l'UMK quand aucun appareil n'est disponible |
| Nature | mot de passe, compte Google ou numéro de téléphone (OTP), gérés par Supabase Auth ; session = jetons | 256 bits aléatoires, une par utilisateur, versionnée (`umk_version`) | 128 bits aléatoires, montrés une fois à l'utilisateur sous forme de code |
| Où elle vit | Supabase Auth (serveur) ; jetons de session sur l'appareil (stockage sécurisé) | sur chaque appareil autorisé, protégée par le Keystore ; sur le serveur **uniquement enveloppée par la RK** | **chez l'utilisateur uniquement** (papier, photo du QR…) ; jamais stockée par Eripoo ni sur l'appareil |
| Si elle est perdue | récupérable (réinitialisation, autre méthode liée) | récupérable depuis un autre appareil ou via la RK | régénérable tant qu'un appareil autorisé existe |
| Si elle est volée | l'attaquant obtient du **chiffré inutilisable** | compromission des données → révoquer, rotation (§4.14) | l'attaquant doit aussi accéder au compte ; régénérer immédiatement |

**Pourquoi la clé de données n'est pas dérivée du mot de passe :** une
réinitialisation de mot de passe (cas fréquent) détruirait les données ; les
comptes Google et téléphone n'ont pas de mot de passe ; un mot de passe
faible affaiblirait le chiffrement ; et le serveur d'authentification verrait
passer le secret qui protège les données.

Secrets auxiliaires, propres à chaque appareil : la **clé du Keystore**
(non exportable), la **clé de base locale** (DBK) et, ponctuellement, une
**paire de clés éphémère** de transfert entre appareils.

## 4. Gestion des clés : cycle de vie complet

### 4.0 Bibliothèques et primitives — aucune cryptographie maison

| Usage | Construction | Bibliothèque |
|---|---|---|
| Aléa | `randombytes_buf` (CSPRNG du système) | **libsodium** 1.0.22 via `sodium` 4.1.1+2 (Dart FFI) |
| Chiffrement authentifié (enregistrements, médias, enveloppes de clé) | `crypto_aead_xchacha20poly1305_ietf` (nonce aléatoire de 192 bits) | libsodium |
| Sous-clés dérivées de l'UMK | `crypto_kdf_derive_from_key` | libsodium |
| Dérivation de la clé d'enveloppe depuis la RK | `crypto_pwhash` (Argon2id) | libsodium (variante « sumo ») |
| Transfert de clé entre appareils | `crypto_box_seal` (X25519 + XSalsa20-Poly1305) | libsodium |
| Vérification de signature des packs de contenu | `crypto_sign_verify_detached` (Ed25519) | libsodium |
| Remplissage (masquer les tailles) | `sodium_pad` / `sodium_unpad` | libsodium |
| Protection des clés sur l'appareil | clé AES-GCM non exportable d'Android Keystore (StrongBox si disponible) | `flutter_secure_storage` 11.2.0 (code Android vérifié : valeurs chiffrées en AES-GCM par une clé elle-même protégée par le Keystore) |
| Chiffrement de la base locale | SQLite3MultipleCiphers (chiffrement de page) | `sqlite3` 3.5.2, option de hook `source: sqlite3mc` |
| Transport | TLS du système | Android / Supabase |

Règles :

- **Aucune primitive, aucun mode, aucun format de flux écrit par Eripoo.**
  Seules les constructions de haut niveau documentées de libsodium sont
  utilisées, telles quelles. Le seul code Eripoo est l'assemblage
  (quelle clé chiffre quoi, avec quelles données associées), revu et testé.
- Pourquoi libsodium plutôt que `cryptography` (retenu en v1) : une seule
  bibliothèque C largement auditée et déployée, des API difficiles à mal
  utiliser, et **XChaCha20-Poly1305**, rapide en logiciel sur les processeurs
  ARMv7 d'entrée de gamme dépourvus d'accélération AES, avec des nonces
  aléatoires sans risque de collision. Le paquet Dart `sodium` compile
  libsodium à la construction (hooks) ; `sodium_libs` est abandonné au profit
  de `sodium` (vérifié sur pub.dev).
- Les opérations coûteuses (Argon2id, chiffrement de médias) s'exécutent dans
  un isolat (`Sodium.runIsolated`).
- Une revue cryptographique externe de l'assemblage est prévue avant la
  production (Phase 10).

### 4.1 Génération de la clé de données

- Au **premier lancement**, avant même tout compte : `UMK =
  randombytes_buf(32)`, `umk_version = 1`. L'invité bénéficie donc dès le
  départ d'une base chiffrée, et l'inscription n'a qu'à envelopper une clé
  existante.
- Au même moment : `DBK = randombytes_buf(32)` (clé de base, propre à
  l'appareil) et `device_id` (UUID aléatoire).
- Sous-clés (calculées à l'ouverture, jamais stockées) :
  `K_rec = kdf(UMK, id=1, ctx="ERPREC01")` pour les enregistrements,
  `K_med = kdf(UMK, id=2, ctx="ERPMED01")` pour les médias.

### 4.2 Stockage local et Android Keystore

```
Android Keystore : clé AES-256-GCM non exportable (StrongBox si présent)
        │ protège
        ▼
flutter_secure_storage (fichier privé de l'app, exclu des sauvegardes)
        ├── UMK + umk_version
        └── DBK
```

- Les clés du Keystore ne quittent jamais le composant sécurisé du
  téléphone (TEE ou StrongBox selon le matériel ; sur certains appareils
  anciens, le Keystore peut n'être que logiciel — limite connue).
- Une copie du stockage (sauvegarde, extraction par câble) est inutilisable
  sans le Keystore du même appareil.
- Le Keystore ne protège pas contre quelqu'un qui **utilise le téléphone
  déverrouillé** et ouvre l'app : d'où le **verrou applicatif optionnel**
  (PIN ou biométrie) qui lie l'accès à la clé à une authentification
  (`setUserAuthenticationRequired`, option prise en charge par
  `flutter_secure_storage`). Recommandé pour les téléphones partagés.
- L'UMK n'est en mémoire qu'app ouverte ; elle est effacée de la mémoire
  quand l'app passe en arrière-plan au-delà d'un délai (si verrou activé).

### 4.3 Chiffrement des données locales

- Toute la base Drift est chiffrée par SQLite3MultipleCiphers avec la DBK
  (clé brute aléatoire de 256 bits, pas de mot de passe). Le paramétrage
  exact (algorithme de page, itérations de dérivation inutiles pour une clé
  aléatoire) sera fixé en Phase 2 d'après la documentation de sqlite3mc et
  mesuré sur appareil de référence. Licence de sqlite3mc à vérifier.
- Médias locaux : chiffrés dès l'enregistrement avec `K_med` (§4.5).
- Fichiers temporaires (export, partage) : supprimés après usage.

### 4.4 Chiffrement des données synchronisées

Le chiffrement a lieu **au moment de l'envoi**, pas à l'écriture locale. Une
enveloppe par enregistrement :

```
enveloppe = format(1 octet = 1) || umk_version (2 octets) || nonce (24 octets)
            || XChaCha20-Poly1305(K_rec, nonce, clair, AD)
AD        = "eripoo/rec/1" || owner_id || record_id || umk_version
clair     = sodium_pad( JSON { type, schema_version, data, deleted_at }, 256 )
```

- Les **données associées (AD)** lient le chiffré à son propriétaire et à son
  identifiant : un chiffré déplacé vers un autre enregistrement ou un autre
  compte est rejeté au déchiffrement.
- Le remplissage par blocs de 256 octets masque la longueur exacte des
  textes.
- Le serveur ne reçoit jamais `type`, `schema_version` en clair, ni
  `project_id`, ni dates métier.

### 4.5 Médias (photos, audio)

- Fichier chiffré **en une seule opération** :
  `XChaCha20-Poly1305(K_med, nonce, fichier, AD = "eripoo/med/1" || owner_id || media_id)`.
- Pour rester en mémoire bornée sans inventer de format de flux, la taille
  d'un média est plafonnée (proposition : 10 Mo — photos redimensionnées,
  audio mono ~32 kbit/s ≈ 20 min). Une interview plus longue est enregistrée
  en plusieurs parties.

### 4.6 Mécanisme de récupération

Création, à l'inscription (ou plus tard depuis Profil) :

1. `RK = randombytes_buf(16)`.
2. Affichage : 26 caractères en base 32 de Crockford (sans caractères
   ambigus) + 2 caractères de contrôle de saisie, groupés par 4
   (`K7Q2-9MXA-…`), et un QR imprimable. L'encodage n'est pas de la
   cryptographie ; il sert à recopier sans erreur.
3. Confirmation par ressaisie de 2 groupes tirés au hasard.
4. `KEK = crypto_pwhash(RK, sel aléatoire de 16 octets, Argon2id, paramètres
   « interactive » à mesurer sur appareil de référence)`. La RK étant
   aléatoire (128 bits), la force vient de l'aléa ; Argon2id ajoute un coût
   par essai.
5. `enveloppe_RK = XChaCha20-Poly1305(KEK, nonce, UMK, AD = "eripoo/wrap/1"
   || owner_id || wrap_id || umk_version)` → table `user_keys`.
6. Vérification immédiate : l'app relit l'enveloppe depuis le serveur et la
   déchiffre avant d'annoncer « code de récupération actif ».

Le code n'est jamais stocké sur l'appareil ni envoyé au serveur. Il n'est
saisi que dans l'écran de déverrouillage de l'app (jamais dans un écran de
contenu).

### 4.7 Changement de mot de passe

- **Aucun effet sur le chiffrement**, par construction (§3) : changer ou
  réinitialiser le mot de passe (par e-mail) ne touche ni l'UMK ni la RK.
- Après un changement, l'app propose « Déconnecter les autres appareils »
  (`signOut(scope: others)`, présent dans `gotrue` 2.27.2).
- Comptes Google / téléphone : pas de mot de passe Eripoo ; même principe.

### 4.8 Changement de téléphone

**Cas 1 — l'ancien téléphone est disponible (recommandé) : transfert par
double QR, sans passer par le serveur.**

1. Le nouveau téléphone : installation, connexion au compte, choix
   « Récupérer depuis mon ancien téléphone ». Il génère une paire éphémère
   (`crypto_box_keypair`) et affiche un QR contenant sa clé publique.
2. L'ancien téléphone (app déverrouillée) : « Ajouter un appareil » → scanne
   le QR → l'utilisateur confirme → calcule `crypto_box_seal(UMK ||
   umk_version, clé_publique)` et l'affiche en QR (≈ 100 octets).
3. Le nouveau téléphone scanne ce QR, ouvre l'enveloppe avec sa clé privée
   éphémère, stocke l'UMK dans son Keystore, efface la clé éphémère, puis
   télécharge et déchiffre les données.

Le serveur ne voit rien de ce transfert. Le sens (nouveau → ancien, puis
ancien → nouveau) garantit que l'ancien téléphone chiffre pour la clé qu'il
a lue physiquement.

**Cas 2 — l'ancien téléphone n'est pas disponible :** connexion, puis saisie
du code de récupération (§4.6, en sens inverse).

Dans les deux cas, le nouvel appareil est enregistré (`devices`). Les
données non synchronisées restées sur l'ancien téléphone ne sont transférées
que si celui-ci se synchronise.

### 4.9 Plusieurs appareils

- Chaque appareil autorisé (ex. téléphone + tablette) détient sa propre
  copie de l'UMK protégée par **son** Keystore ; ajout par §4.8.
- Plafond proposé : 5 appareils actifs.
- Liste visible dans Profil (« Téléphone ajouté le … ») avec révocation.

### 4.10 Perte (ou vol) du téléphone

1. Sur un autre appareil autorisé ou un nouveau (récupéré par RK) :
   « J'ai perdu un appareil » → l'appareil est marqué `revoked_at` et toutes
   les autres sessions sont fermées (`signOut(scope: others)`).
2. Les RPC de sync refusent tout appareil révoqué. Si le téléphone perdu se
   reconnecte un jour, l'app reçoit `device_revoked` et **efface ses
   données et ses clés locales**.
3. Ce qui reste exposé, honnêtement : les données déjà présentes sur le
   téléphone perdu, protégées par le verrouillage d'écran du téléphone, le
   Keystore, la base chiffrée et le verrou applicatif s'il était activé.
   Les modifications jamais synchronisées depuis ce téléphone sont perdues.
4. Si une compromission de l'UMK est suspectée : rotation (§4.14).

### 4.11 Perte du code de récupération

- **Un appareil autorisé existe encore :** « Créer un nouveau code » →
  réauthentification récente exigée (`reauthenticate()` de Supabase, ou
  nouvelle connexion) + verrou applicatif s'il est actif → nouvelle RK,
  nouvelle enveloppe vérifiée, **l'ancienne enveloppe est supprimée
  immédiatement** (un ancien code retrouvé par un tiers ne doit plus rien
  ouvrir) → e-mail/SMS de notification « ton code de récupération a
  changé ».
- **Aucun appareil et aucun code :** les données en ligne sont
  **définitivement illisibles**, y compris pour Eripoo. L'utilisateur peut
  toujours accéder à son compte (§4.12) et choisir « Recommencer » : nouvelle
  UMK, ancien chiffré supprimé après confirmation explicite. C'est le prix
  de la garantie « personne d'autre ne peut lire » (décision D2).
- Prévention : rappel doux tant que le code n'est pas confirmé ;
  encouragement à ajouter un second appareil ; option de séquestre B
  (§6) si la perte s'avère fréquente.

### 4.12 Récupération du compte (authentification)

| Situation | Accès au compte | Accès aux données |
|---|---|---|
| Mot de passe oublié | réinitialisation par e-mail | inchangé (appareil ou RK) |
| Numéro de téléphone / SIM perdus | via une autre méthode liée (e-mail, Google) — d'où l'invitation à lier 2 méthodes | inchangé |
| Toutes les méthodes perdues | procédure manuelle d'identification par le support, limitée à l'accès au compte | le support **ne peut pas** rendre les données : il faut un appareil ou la RK |

Conséquence utile : une prise de contrôle du compte par ingénierie sociale
(y compris auprès du support) n'expose pas le contenu des projets.

### 4.13 Suppression du compte

1. Depuis l'app, avec réauthentification récente ; avertissement si des
   données ne sont pas synchronisées ; proposition d'export préalable.
2. Edge Function `delete-account` (clé `service_role` côté serveur
   uniquement) : suppression des objets `user-media/{uid}/*`, puis de
   l'utilisateur Auth (cascade : `sync_records`, `user_keys`, `devices`,
   `profiles`, `consents`, `sync_heads`), trace minimale dans
   `deletion_requests`.
3. Sur l'appareil : effacement de la base, des médias, de l'UMK et de la DBK
   (Keystore) après confirmation du serveur.
4. **Effacement cryptographique** : les sauvegardes de la plateforme
   peuvent conserver du chiffré et des enveloppes pendant leur durée de
   rétention (à documenter selon le plan Supabase retenu) ; elles restent
   illisibles sans un appareil ou la RK, qui n'existent plus.

### 4.14 Rotation de l'UMK (prévue dans le format, implémentée plus tard)

`umk_version` figure dans chaque enveloppe dès le départ. Une rotation
(compromission suspectée) : nouvelle UMK, nouvelle RK, rechiffrement
progressif de tous les enregistrements, distribution aux appareils restants
par §4.8, suppression des anciennes enveloppes. Non nécessaire au MVP.

## 5. Pourquoi un administrateur ne peut pas déchiffrer

### 5.1 Inventaire de ce que le serveur détient

| Élément sur le serveur | Ce qu'il faudrait pour le lire | Où cela se trouve |
|---|---|---|
| `sync_records.payload` | `K_rec` ← UMK | uniquement sur les appareils de l'utilisateur |
| `user-media` | `K_med` ← UMK | idem |
| `user_keys` (UMK enveloppée) | RK (128 bits aléatoires + Argon2id) | uniquement chez l'utilisateur |
| Session / jetons, accès `service_role` | — | donnent accès au chiffré, rien de plus |
| Code des Edge Functions | — | ne reçoivent jamais de clé ni de contenu (sauf §11, sur consentement) |
| Transfert entre appareils | — | ne passe pas par le serveur (QR) |

Un administrateur Supabase avec tous les droits obtient donc des blobs
chiffrés, des enveloppes de clé et des métadonnées (§1).

### 5.2 Couches complémentaires

1. RLS : aucune politique n'accorde au personnel l'accès à `sync_records`,
   `user_keys`, `devices`, `consents`, aux `profiles` d'autrui ni au bucket
   `user-media`. Tests pgTAP : un compte ayant chaque rôle du personnel lit
   0 ligne.
2. Back-office sans aucun écran de consultation d'utilisateur ou de projet ;
   il ne reçoit jamais la clé `service_role`.
3. `service_role` uniquement dans les secrets des Edge Functions.
4. Tableau de bord Supabase : 2 personnes max, MFA, journal d'audit.

### 5.3 Limites résiduelles (dites honnêtement)

- **Version malveillante de l'application** : elle pourrait lire les données
  au moment où elles sont déchiffrées sur l'appareil. Mesures : revue de
  code obligatoire, releases construites par la CI, clé de signature
  protégée, `pubspec.lock` commité ; builds reproductibles à étudier.
- **IA / transcription sur consentement** : le texte ou l'audio envoyé
  transite en clair par le proxy Eripoo et le fournisseur (§11).
- **Métadonnées** (§1) : visibles du serveur, minimisées.
- **Appareil compromis** (logiciel espion, téléphone déverrouillé prêté) :
  hors de portée d'une application.

## 6. Décision D1/D2 : niveau de garantie

| Option | Garantie « le personnel ne peut pas lire » | Risque de perte |
|---|---|---|
| **A. E2EE + code de récupération + transfert QR** (recommandée) | technique, forte | réel si appareils et code sont tous perdus |
| B. A + séquestre à double contrôle (UMK aussi enveloppée par une clé de séquestre conservée hors ligne, scindée entre 2 personnes, utilisée seulement à la demande vérifiée de l'utilisateur) | affaiblie : une collusion interne permettrait la lecture ; à annoncer clairement | faible |
| C. Pas d'E2EE, RLS seule | organisationnelle seulement — **ne satisfait pas l'exigence** | nul |

B s'ajoute plus tard **sans migration** (une enveloppe de plus de la même
UMK) : commencer par A ne ferme aucune porte.

## 7. Authentification

- **Invité local** : aucun compte, aucune requête réseau.
- **Méthodes MVP** : e-mail + mot de passe (confirmation d'e-mail), Google
  (SDK natif → `signInWithIdToken`), téléphone (OTP SMS — fournisseur à
  choisir et tester, risque R4). **Facebook** : présent dans l'énumération
  des fournisseurs, désactivé par configuration.
- **Plusieurs méthodes sur un compte** : `linkIdentity`,
  `linkIdentityWithIdToken`, `unlinkIdentity` (vérifiés dans
  `supabase_flutter` 2.18.0 / `gotrue` 2.27.2) ; liaison manuelle à activer
  dans la configuration Auth.
- **Session** : flux PKCE ; stockée via un `LocalStorage` adossé à
  `flutter_secure_storage` — **pas** dans SharedPreferences, qui est le
  comportement par défaut de `supabase_flutter` (vérifié dans le code
  source).
- Limitation de débit et CAPTCHA sur inscription et envoi d'OTP.
- Opérations sensibles (nouveau code de récupération, suppression de
  compte, révocation d'appareil) : réauthentification récente exigée.

## 8. Isolation des administrateurs (organisation)

Rôles du personnel (`staff_roles`) : `content_editor`, `translator`,
`content_publisher`, `analyst`, `ops`. Le back-office gère contenu,
traductions, quêtes, missions, badges, outils, ressources, informations
administratives, statistiques agrégées et santé technique. Les métadonnées
techniques (§1) ne sont consultées par `ops` qu'en cas de nécessité,
directement en base, avec justification consignée dans `audit_log`.

## 9. Journaux, erreurs, stockage local

- **Logger expurgé** : codes d'événement, identifiants techniques, durées.
  Interdits : textes saisis, noms, e-mails, téléphones, jetons, clés, codes
  de récupération, chemins de médias, payloads. Test automatique par
  « données sentinelles » qui ne doivent apparaître dans aucune sortie.
- **Rapports d'erreur** : type d'exception + pile + version ; **le message
  d'exception n'est pas transmis** (il peut contenir une saisie). Envoi via
  l'Edge Function d'analytics, sans identifiant. Pas de SDK de crash tiers au
  départ (D8).
- `print` interdit par lint (en place).
- Sauvegarde Android et transfert d'appareil désactivés (fait).

## 10. Analytics anonymisés

- Consentement **opt-in** proposé à l'onboarding, modifiable (D7) ;
  désactivé par défaut pour les mineurs.
- Aucun identifiant (ni utilisateur, ni appareil, ni publicitaire). Chaque
  événement : nom, propriétés énumérées, version, langue, **jour**, semaine
  d'installation, tranche d'ancienneté.
- Liste blanche d'événements et de propriétés dans le code, revalidée par
  l'Edge Function. Exemples : `onboarding_completed`,
  `diagnostic_profile{profile}`, `step_completed{quest_id, step_id}`,
  `help_used{level}`, `mission_completed{mission_template_id}`,
  `hypothesis_status_changed{from,to}`, `tool_opened{tool_id}`,
  `sync_failed{error_code}`, `app_start{cold_ms_bucket}`. Seuls des
  identifiants du **contenu public** apparaissent.
- Envoi par lot quotidien. L'Edge Function ne stocke pas l'IP ; la
  plateforme peut journaliser les IP de requête (à vérifier et à mentionner
  dans la politique de confidentialité).
- On mesure des entonnoirs agrégés par cohorte, pas des parcours
  individuels.

## 11. IA et services externes

- Implémentation « désactivée » par défaut ; fournisseur remplaçable derrière
  une Edge Function proxy (clé fournisseur côté serveur).
- Envoi de texte ou d'audio privé **uniquement après consentement explicite
  pour cet usage précis**, en montrant ce qui part ; le proxy ne journalise
  ni ne stocke ; contrat fournisseur excluant l'entraînement (à vérifier au
  choix du fournisseur). Le texte de consentement dit clairement que ce
  contenu sort, ponctuellement, de la protection de bout en bout.

## 12. Mineurs

- Déclaration d'âge à l'onboarding (année de naissance chiffrée ; seule la
  tranche `under_min / minor / adult` est connue du serveur).
- Règles lues depuis `jurisdiction_policies` (âge minimum, seuil de
  consentement parental, `legal_validated`) ; **aucune valeur dans le
  code** ; release bloquée tant que `legal_validated = false`.
- Parcours identique ; analytics et IA désactivés par défaut.
- Flux de consentement parental conçu après analyse juridique (D12).

## 13. Intégrité du contenu pédagogique

- Chaque pack de contenu est signé (Ed25519) par une clé de publication
  conservée **hors ligne** ; la clé publique est intégrée à l'app ; un pack
  dont la signature est invalide est refusé.
- Ainsi, même une compromission de Supabase ne permet pas de pousser du
  contenu trompeur (par exemple un faux message demandant le code de
  récupération).
- Le contenu est de la donnée : le langage de règles n'exécute aucun code.

## 14. Droits de l'utilisateur

- **Export** sur l'appareil (JSON + médias, et dossier PDF), sans serveur.
- **Suppression** d'un élément (corbeille 30 jours puis purge) ou du compte
  (§4.13).
- **Consentements** versionnés et révocables.
- Politique de confidentialité fr/mg/en, à valider juridiquement.

## 15. Validation et durcissement

- Client : validation de domaine avant écriture.
- Serveur : contraintes Postgres, RPC validant taille, versions, appareil,
  quotas et débit ; Edge Functions validant chaque entrée.
- Secrets : URL Supabase et clé `anon` (publique par conception) via
  `--dart-define-from-file` (fichier non commité) ; aucune clé privée dans
  l'app.
- Android : trafic en clair interdit explicitement, release obfusquée, pas
  de WebView exécutant du contenu distant, permissions au moment de l'usage.
