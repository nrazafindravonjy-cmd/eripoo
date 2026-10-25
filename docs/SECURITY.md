# Eripoo — Sécurité et confidentialité

Principe : **le projet appartient à l'utilisateur.** Le contenu privé d'un
projet n'est accessible à **personne** chez Eripoo — administrateurs
Supabase et personnel Eripoo compris — et cela est garanti par la
cryptographie, pas seulement par des règles internes.

Statut : conception (revue Phase 0, v3) **et implémentation Phase 2**
(non acceptée). L'état réel est indiqué section par section : §4.4–4.5
(clés, base chiffrée), §4.11 (verrou), §6.0 (multi-appareil), §6.8
(révocation), §11 (journaux). Les valeurs « à mesurer » sont mesurées sur
émulateur en CI ; **les appareils de référence A et B restent à faire**.

⚠️ Ce document n'est pas un avis juridique. Madagascar dispose d'une loi
sur la protection des données personnelles (loi n° 2014-038, autorité de
contrôle : CMIL — sources dans
[ARCHITECTURE §14](ARCHITECTURE.md#14-région-dhébergement-supabase)). Son
application à Eripoo doit être analysée par un juriste.

Sommaire : [1. Catégories de données](#1-trois-catégories-de-données) ·
[2. Modèle de menace](#2-modèle-de-menace) ·
[3. Trois secrets](#3-trois-secrets-distincts) ·
[4. Schéma cryptographique](#4-schéma-cryptographique-de-bout-en-bout) ·
[5. Code de récupération](#5-code-de-récupération) ·
[6. Transfert vers un nouvel appareil](#6-transfert-vers-un-nouvel-appareil-double-qr-hors-ligne) ·
[7. Scénarios de compte](#7-scénarios-de-compte) ·
[8. Pourquoi un administrateur ne peut pas déchiffrer](#8-pourquoi-un-administrateur-ne-peut-pas-déchiffrer) ·
[9–17. Autres mesures](#9-décision-d1d2--niveau-de-garantie) ·
[18. Dépendances cryptographiques](#18-dépendances-cryptographiques)

---

## 1. Trois catégories de données

| | **Données privées du projet** | **Métadonnées techniques** | **Analytics** |
|---|---|---|---|
| Contenu | tout ce que l'utilisateur produit : réponses, projet, historique, hypothèses, expériences, résultats, preuves, décisions, observations, interviews (y compris sur des tiers), photos, audio, transcriptions, finances, documents, profil détaillé, progression, badges | identifiants de compte (e-mail, téléphone, identité Google), `user_id`, appareils (id aléatoire, libellé choisi, dates, version d'app), métadonnées de sync (id aléatoires, versions, indicateur de suppression, taille arrondie, horodatages serveur), paramètres et dates des enveloppes de clé, profil minimal (langue, juridiction, tranche d'âge, statut de consentement parental), consentements, journaux d'infrastructure (IP, horodatage) | événements sans identifiant, propriétés énumérées (identifiants du **contenu public** uniquement), jour, version, langue, cohorte |
| Protection | **chiffrées de bout en bout sur l'appareil** avant tout envoi ; base locale chiffrée | RLS ; minimisées par conception | anonymes, agrégées, opt-in |
| Accès du personnel | **impossible techniquement** (§8) | **uniquement si nécessaire** (incident, demande de l'utilisateur), rôle `ops` (2 personnes max, MFA), justifié et journalisé ; jamais dans le back-office | agrégats seulement ; cellules < 10 masquées |
| Rétention | jusqu'à suppression par l'utilisateur | durée de vie du compte (+ sauvegardes de la plateforme) | brut 90 jours, puis agrégats |

## 2. Modèle de menace

### 2.1 Contre quoi les données privées sont protégées

| Menace | Résultat | Comment | Limite |
|---|---|---|---|
| **Administrateur Supabase** (accès total à la base, au Storage, aux journaux) | ✅ protégé | il n'obtient que du chiffré et une enveloppe protégée par un code de 116 bits (§4, §5) | voit les métadonnées (§1) |
| **Personnel Eripoo** | ✅ protégé | idem ; aucun outil interne n'expose de données utilisateur | idem |
| **Fuite de la base ou des sauvegardes** | ✅ protégé | idem ; aucune clé utilisable n'est stockée côté serveur | métadonnées exposées |
| **Brute-force du code de récupération** | ✅ protégé | 116 bits d'aléa + Argon2id : recherche exhaustive irréalisable (§5.5) ; aucun vérificateur côté serveur | — |
| **Interception réseau** | ✅ protégé | TLS + contenu déjà chiffré de bout en bout ; transfert de clé entre appareils hors réseau | un observateur voit qu'un téléphone parle à Supabase et le volume échangé |
| **Téléphone perdu** | ⚠️ partiel | base chiffrée, clés dans le Keystore (copie du stockage inutilisable), révocation à distance (§6.9) | si le téléphone n'a pas de verrouillage d'écran **et** que le verrou Eripoo n'est pas activé, la personne qui le trouve peut ouvrir l'app |
| **Téléphone volé** | ⚠️ partiel | idem ; le voleur ne reçoit plus aucune donnée nouvelle après révocation | mêmes limites ; un téléphone *rooté* peut affaiblir le Keystore logiciel des appareils sans composant sécurisé |
| **Appareil secondaire compromis** (logiciel espion sur la tablette autorisée) | ❌ non protégé pour ce qu'il voit | révocation pour couper son accès au serveur | un appareil autorisé détient la clé de données : tant que la rotation de clé (§4.10) n'a pas eu lieu, cette clé reste exposée |
| **Version malveillante de l'application** | ❌ non protégé | revue de code, releases construites par la CI, clé de signature protégée, `pubspec.lock` commité | l'app voit les données déchiffrées ; aucune cryptographie ne protège contre le code qui les affiche |

### 2.2 Ce que l'architecture NE peut PAS protéger

- Un téléphone **déverrouillé et sans verrou Eripoo** entre de mauvaises mains.
- Un téléphone infecté (logiciel espion, service d'accessibilité malveillant,
  capture d'écran à distance).
- Une version malveillante d'Eripoo, ou une dépendance compromise intégrée
  à une release.
- L'utilisateur qui **communique son code de récupération** (contrainte,
  arnaque, photo partagée).
- Ce que l'utilisateur **exporte et partage** (PDF envoyé par WhatsApp…).
- Le texte ou l'audio envoyé **avec son accord** à l'IA ou à la
  transcription (§13).
- Les **métadonnées** (§1) : qui a un compte, quand il synchronise, combien
  de données.
- La **perte** : si tous les appareils et le code sont perdus, les données
  en ligne sont irrécupérables (c'est la contrepartie de la garantie).

## 3. Trois secrets distincts

Jamais confondus, jamais dérivés l'un de l'autre.

| | **Authentification du compte** | **Clé de données (UMK)** | **Code de récupération (RK)** |
|---|---|---|---|
| Rôle | prouver au serveur « je suis ce compte » ⇒ accès au **chiffré** de ce compte | chiffrer et déchiffrer tout le contenu privé | retrouver l'UMK quand aucun appareil autorisé n'est disponible |
| Nature | mot de passe, compte Google ou numéro de téléphone (OTP), gérés par Supabase Auth | 256 bits aléatoires, une par utilisateur | 35 chiffres aléatoires (116 bits) + 1 chiffre de contrôle |
| Où il vit | Supabase Auth ; jetons de session sur l'appareil (stockage sécurisé) | appareils autorisés (Keystore) ; serveur **seulement enveloppée par la RK** | **chez l'utilisateur uniquement** (papier) |
| Perdu | récupérable (réinitialisation, autre méthode liée) | récupérable via un appareil ou la RK | régénérable tant qu'un appareil autorisé existe |
| Volé | l'attaquant obtient du chiffré inutilisable | compromission ⇒ révocation + rotation | inutile sans accès au compte ; régénérer aussitôt |

La clé de données n'est **pas** dérivée du mot de passe : une
réinitialisation détruirait les données, les comptes Google et téléphone
n'ont pas de mot de passe, un mot de passe faible affaiblirait le
chiffrement, et le serveur d'authentification verrait passer ce secret.

## 4. Schéma cryptographique de bout en bout

### 4.1 Vue d'ensemble

```
                     ┌──────────── APPAREIL ────────────────────────────────┐
 CSPRNG ─► UMK (32 o) ┤                                                      │
                     │  Keystore (AES-GCM non exportable)                   │
                     │     └─ protège ─► stockage sécurisé : UMK, DBK       │
                     │                                                      │
                     │  UMK ─kdf(1,"ERPREC01")─► K_rec ─► enveloppes d'enregistrements ─┐
                     │  UMK ─kdf(2,"ERPMED01")─► K_med ─► fichiers médias ──────────────┤
 CSPRNG ─► DBK (32 o) ─► base SQLite chiffrée (sqlite3mc)                     │          │
                     └──────────────────────────────────────────────────────┘          │
                                                                                       ▼
 Utilisateur : RK (35 chiffres) ─Argon2id(sel)─► KEK ─► UMK enveloppée ─►  SERVEUR : chiffré
                                                                            + UMK enveloppée
```

### 4.2 Primitives et bibliothèques — aucune cryptographie maison

| Usage | Construction | Bibliothèque |
|---|---|---|
| Aléa (clés, sels, nonces) | `randombytes_buf` | libsodium 1.0.22 via `sodium` 4.1.1+2 |
| Chiffres aléatoires uniformes (RK) | `randombytes_uniform(10)` (sans biais modulo) | libsodium |
| Chiffrement authentifié | `crypto_aead_xchacha20poly1305_ietf` (nonce aléatoire de 192 bits) | libsodium |
| Sous-clés | `crypto_kdf_derive_from_key` | libsodium |
| Code → clé | `crypto_pwhash`, `crypto_pwhash_ALG_ARGON2ID13` | libsodium (variante « sumo ») |
| Transfert de clé | `crypto_box_keypair`, `crypto_box_seal` / `crypto_box_seal_open` (X25519 + XSalsa20-Poly1305) | libsodium |
| Empreinte affichée (code de vérification) | `crypto_generichash` (BLAKE2b) | libsodium |
| Signature des packs de contenu | `crypto_sign_verify_detached` (Ed25519) | libsodium |
| Remplissage | `sodium_pad` / `sodium_unpad` | libsodium |
| Clés en mémoire | `SecureKey` (`sodium_malloc` + `sodium_memzero` à la libération) | `sodium` |
| Protection au repos sur l'appareil | clé RSA-OAEP non exportable d'Android Keystore qui enveloppe la clé AES-GCM du stockage | `flutter_secure_storage` 11.2.0 |
| Chiffrement de la base | schéma ChaCha20-Poly1305 de SQLite3MultipleCiphers | `sqlite3` (hook `source: sqlite3mc`) |
| Transport | TLS | Android / Supabase |

Le seul code propre à Eripoo est l'**assemblage** : quelle clé chiffre
quoi, avec quelles données associées, dans quel format. Il est revu, couvert
par des vecteurs de test, et soumis à une revue cryptographique externe
avant la production. Le chiffre de contrôle de Damm (§5.2) n'est pas de la
cryptographie : c'est un code de détection d'erreurs de saisie.

### 4.3 Génération exacte des clés

Au **premier lancement**, avant tout compte :

| Valeur | Génération | Usage |
|---|---|---|
| `UMK` | `randombytes_buf(32)` | clé de données ; `umk_version = 1` |
| `DBK` | `randombytes_buf(32)` | clé de la base locale, propre à l'appareil |
| `device_id` | UUID v4 aléatoire | identité de l'appareil |

Sous-clés, recalculées à chaque ouverture et jamais stockées :

```
K_rec = crypto_kdf_derive_from_key(32, subkey_id = 1, ctx = "ERPREC01", UMK)
K_med = crypto_kdf_derive_from_key(32, subkey_id = 2, ctx = "ERPMED01", UMK)
```

L'invité bénéficie donc dès le départ d'une base chiffrée ; l'inscription
n'a qu'à envelopper une UMK existante (§5.3).

### 4.4 Stockage local et Android Keystore

```
Android Keystore : clé AES-256-GCM non exportable (StrongBox si présent)
   └─ protège la clé de stockage de flutter_secure_storage
         └─ chiffre (AES-GCM) les entrées :
              "eripoo.umk"  = 0x01 || umk_version (2 o) || UMK (32 o)
              "eripoo.dbk"  = 0x01 || DBK (32 o)
              "eripoo.session" = session Supabase (jetons)
```

- Configuration (implémentée, `lib/security/secure_key_store.dart`) :
  `AndroidOptions(keyCipherAlgorithm: RSA_ECB_OAEPwithSHA_256andMGF1Padding,
  storageCipherAlgorithm: AES_GCM_NoPadding, resetOnError: false)` —
  la configuration par défaut recommandée par la bibliothèque.
  **Corrigé en validation Phase 2** : la configuration précédente
  (`keyCipherAlgorithm: AES_GCM_NoPadding`) est le mode *biométrique* de la
  bibliothèque. Au premier lancement, elle passe par `BiometricPrompt` :
  **plantage sur Android 7–8** (API < 28, constaté sur l'émulateur CI
  Android 8) et demande d'authentification à chaque ouverture sur les
  téléphones verrouillés. Aucune donnée n'existait encore (pas de
  migration nécessaire). Une règle d'architecture interdit d'y revenir.
  ⚠️ **`resetOnError` vaut `true` par défaut dans la bibliothèque** : à la
  moindre erreur de déchiffrement, elle efface toutes les valeurs stockées,
  ce qui détruirait silencieusement les clés. Il est désactivé ; une erreur
  de lecture est remontée explicitement (`SecureStoreUnavailable`), et une
  base existante sans clé est signalée (`LocalKeysLost`) au lieu d'être
  recréée.
- Fichier exclu des sauvegardes et du transfert d'appareil (fait).
- Une copie du stockage (câble, sauvegarde) est inutilisable sans le
  Keystore du même téléphone. Sur certains appareils anciens, le Keystore
  n'est que logiciel : protection plus faible face à un téléphone *rooté*.
- **Verrou Eripoo (décision D4, 2026-10-06)** : facultatif, et **séparé du
  chiffrement**, qui reste toujours actif. Le verrou est une protection
  d'**accès à l'interface** (PIN local, biométrie si disponible, délai
  configurable) ; il ne protège pas les fichiers et n'en a pas besoin (base
  chiffrée, clés dans le Keystore). En particulier :
  - le PIN n'est **ni une clé ni une source de dérivation** : l'appareil
    garde seulement un vérificateur Argon2id (`crypto_pwhash_str`) dans le
    stockage sécurisé ;
  - les clés du Keystore **ne sont pas** liées à une authentification de
    l'utilisateur (`setUserAuthenticationRequired` n'est pas utilisé) :
    activer ou oublier le verrou ne peut jamais rendre les données
    illisibles ;
  - détail du mécanisme : §4.11.
- En mémoire, UMK et sous-clés sont des `SecureKey` (mémoire native
  protégée, effacée à la libération). Quand une clé doit passer dans un
  isolat (Argon2id en arrière-plan), elle transite comme liste d'octets
  Dart, effacée après usage — au mieux de ce que permet la machine
  virtuelle Dart, qui peut en garder des copies. Les tampons renvoyés par
  libsodium sont toujours recopiés en mémoire Dart avant de sortir de
  `CryptoService` (un tampon natif envoyé à un autre isolat faisait planter
  le processus, constaté en test).

### 4.5 Chiffrement des données locales

- Toute la base Drift est chiffrée par SQLite3MultipleCiphers (schéma par
  défaut **ChaCha20-Poly1305**, adapté aux processeurs sans accélération
  AES) avec la DBK.
- La DBK est passée avec le préfixe documenté `raw:` de sqlite3mc
  (`pragma key = 'raw:<64 hex>'`, vérifié dans le code source) : la
  dérivation PBKDF2 du schéma est **contournée**, car la clé est déjà
  aléatoire ; l'ouverture est plus rapide sur les téléphones d'entrée de
  gamme et ce paramètre n'a plus à être mesuré. Ouverture mesurée sur
  émulateur : 11–27 ms au redémarrage (clés + base). Sur appareil :
  NON VÉRIFIÉ (P7).
- Une mauvaise clé est détectée à l'ouverture (`DatabaseKeyMismatch`).
  sqlite3mc refuse les clés sur les bases en mémoire : les tests métier
  utilisent donc une base en mémoire non chiffrée, le chiffrement étant
  testé séparément sur fichier.
- `pragma temp_store = memory` : les tables temporaires et les tris
  restent en mémoire. Le chiffrement des fichiers temporaires par
  sqlite3mc n'a pas été vérifié ; aucun n'est donc écrit (précaution).
- Au démarrage (`lib/app/startup/app_services.dart`) : clés chargées ou
  créées, base ouverte et **interrogée immédiatement** pour qu'une
  mauvaise clé échoue au lancement, pas au milieu du travail. Base présente
  mais clés absentes → `LocalKeysLost` : **aucune recréation silencieuse** ;
  un écran simple l'explique et propose de recommencer sur ce téléphone
  **après confirmation explicite** (efface la base et les clés locales ; ce
  qui était synchronisé reste récupérable avec le code de récupération).
  Toute autre erreur : écran sans action destructive.
- Médias locaux : chiffrés dès l'enregistrement (§4.7).

### 4.6 Chiffrement des données synchronisées — format v1

Chiffrement **au moment de l'envoi**. Une enveloppe par enregistrement :

```
octet 0        format         = 0x01
octets 1–2     umk_version    (entier non signé, gros-boutiste)
octets 3–26    nonce          24 octets aléatoires
octets 27–…    chiffré || tag (16 o)  = XChaCha20-Poly1305(K_rec, nonce, clair, AD)

AD    = "eripoo:rec:v1" || 0x00 || owner_id (16 o) || record_id (16 o) || umk_version (2 o)
clair = sodium_pad( UTF-8( JSON { "t": type, "s": schema_version,
                                  "d": données, "x": deleted_at } ), 256 )
```

- Les **données associées** (champs de taille fixe) lient le chiffré à son
  compte et à son identifiant : un chiffré déplacé ou rejoué ailleurs est
  rejeté au déchiffrement.
- Le remplissage par blocs de 256 octets masque la longueur des textes.
- Le serveur ne voit ni le type, ni la version de schéma, ni le projet, ni
  les dates métier.

### 4.7 Médias — format v1

```
octet 0  format = 0x01 ; octets 1–2 umk_version ; octets 3–26 nonce ;
reste    XChaCha20-Poly1305(K_med, nonce, fichier, AD)
AD     = "eripoo:med:v1" || 0x00 || owner_id || media_id || umk_version
```

Chiffrement en une seule opération ; taille plafonnée à 10 Mo (D15) pour
rester en mémoire bornée sans format de flux maison.

**Implémentation (Phase 4, `lib/features/media/data/media_store.dart`)** :
chiffrement en mémoire puis écriture de `<id>.part` renommé en `<id>.bin`
dans le répertoire privé de l'app : aucun octet en clair n'est écrit
(vérifié par test). Avant tout compte, `owner_id` vaut l'UUID nul ; l'envoi
au serveur (Phase 5) rechiffrera le fichier pour l'identifiant du compte.
Le sélecteur photo du système remet une copie en clair dans le cache de
l'app : elle est lue puis supprimée aussitôt ; une photo choisie dans la
galerie y reste (c'est la copie de l'utilisateur). Les fichiers médias sont
effacés avec les données locales (réinitialisation, révocation). Photos
réduites à 1 600 px (≈ 300 Ko) ; écriture synchrone pour ne jamais laisser
de fichier à moitié écrit.

### 4.8 Copie serveur de la clé de données — format v1

Seule copie de l'UMK hors des appareils : la table `user_keys`.

```
KEK         = crypto_pwhash(32, RK_chiffres, sel, opslimit, memlimit, ARGON2ID13)
wrapped_umk = 0x01 || nonce (24 o) || XChaCha20-Poly1305(KEK, nonce, UMK, AD)
AD          = "eripoo:wrap:v1" || 0x00 || owner_id || wrap_id || umk_version
```

| Paramètre | Valeur prévue | Justification |
|---|---|---|
| Algorithme | Argon2id v1.3 | standard (RFC 9106), résistant aux GPU/ASIC |
| Entrée | les 35 chiffres aléatoires en ASCII, sans séparateurs ni chiffre de contrôle | normalisation unique |
| `opslimit` | 3 | à mesurer ; plancher 2 |
| `memlimit` | 64 Mio | supportable sur 1 Go de RAM ; plancher 32 Mio |
| Parallélisme | 1 (fixé par libsodium) | — |
| Sel | 16 octets aléatoires (`crypto_pwhash_SALTBYTES`), **nouveau à chaque enveloppe**, stocké en clair | empêche tout précalcul commun à plusieurs comptes ; n'est pas un secret |
| Durée cible | < 3 s sur appareil de référence | n'intervient qu'à la création, à la vérification et à la récupération |

**Mesures (validation Phase 2, émulateurs CI x86_64 — indicatives,
`docs/DEVICE_TESTS.md`)** : 3 × 64 Mio = 124–430 ms selon le run (2 × 32 Mio
: 44–131 ms ; 4 × 64 Mio : 163–283 ms), coût identique à chaque essai (5
mauvais codes : ~190–480 ms chacun), sur isolat de fond, interface jamais
bloquée plus de 51 ms, aucun échec mémoire sur l'émulateur « 1 Go » (qui
avait en réalité 1,5 Go).

**Décision provisoire** : on garde **3 passes / 64 Mio** pour le code de
récupération et **2 passes / 32 Mio** pour le vérificateur du PIN. Raison :
les émulateurs sont loin de la cible de 3 s, ce qui laisse une marge pour
un processeur ARM d'entrée de gamme, plusieurs fois plus lent (estimation
**NON VÉRIFIÉE**). **Rien n'est figé** : paramètres définitifs après mesure
sur les appareils A et B, avec cette règle fixée à l'avance :

- 3 × 64 Mio dépasse 3 s ou échoue faute de mémoire sur A → 2 × 64 Mio ;
- 2 × 64 Mio dépasse aussi 3 s ou échoue → plancher 2 × 32 Mio ;
- 3 × 64 Mio reste sous 1 s sur A → on peut monter à 4 × 64 Mio.

Les paramètres sont stockés avec l'enveloppe (`kdf_params`), ce qui permet
de les faire évoluer pour les nouvelles enveloppes sans casser les
anciennes. Le serveur ne stocke **aucun** vérificateur, hachage ou indice
du code.

### 4.9 Versionnement des formats

| Format | Octet de version | Évolution |
|---|---|---|
| Enveloppe d'enregistrement | `0x01` | une nouvelle version est lue en parallèle ; réécriture au format courant à la modification suivante |
| Média | `0x01` | idem |
| Enveloppe de clé (`user_keys`) | `0x01` + `wrap_format` | nouvelle enveloppe créée au prochain renouvellement du code |
| Entrée du stockage sécurisé | `0x01` | migration locale au démarrage |
| QR de transfert | préfixes `ERPT1` / `ERPT2` | une app refuse une version inconnue avec un message clair |

### 4.10 Rotation de l'UMK

`umk_version` figure dans chaque format dès la v1. **Implémentée en
Phase 10** (D17) : c'est la seule réponse à un appareil autorisé qui ne
l'est plus (perdu, volé, donné), une fois retiré de « Mes appareils ».

Déroulé (`lib/features/account/application/key_rotation.dart`, migration
`20261009000001_data_key_rotation.sql`) :

1. **Sur l'appareil** : nouvelle UMK (`randombytes_buf(32)`, version
   `v + 1`) et nouveau code de récupération, affiché une fois et vérifié
   (4 derniers chiffres) ; enveloppe de récupération de la nouvelle UMK
   (Argon2id, nouveau sel, §4.8), vérifiée avant tout envoi. Le mot de
   passe du compte est redemandé juste avant (connexion de moins de
   10 minutes exigée par le serveur).
2. **Clé en attente** : la nouvelle UMK est d'abord rangée dans le
   stockage sécurisé (entrée `eripoo.umk.pending`), puis le serveur bascule
   **en une seule transaction** (`rotate_data_key`) : version du compte
   `v → v + 1` (seulement depuis `v`), ancienne enveloppe supprimée et
   nouvelle enregistrée, événement `data_key_rotated` (métadonnée seule).
   Dès cet instant, l'ancien code n'ouvre plus rien et le serveur **refuse
   toute enveloppe scellée avec une autre version** (`stale_key`), ainsi
   qu'une enveloppe de récupération d'une autre version
   (`key_version_mismatch`). Si la réponse se perd, la synchronisation
   suivante apprend la version du compte (`sync_pull` la renvoie) et
   termine la bascule avec la clé en attente, ou l'abandonne si le serveur
   n'a pas basculé (après 10 minutes, au cas où la requête serait encore
   en route).
3. **Bascule locale** : l'UMK `v + 1` devient la clé courante ; l'ancienne
   est gardée comme *clé précédente* ; l'app redémarre.
4. **Rechiffrement** à chaque synchronisation : chaque enregistrement du
   serveur encore en version `v` est ouvert avec la clé précédente et
   scellé à nouveau avec la nouvelle, **sans être interprété** (y compris
   ceux d'une version plus récente de l'app) ; chaque fichier est relu (ou
   téléchargé), scellé à nouveau, supprimé puis renvoyé (fichiers jamais
   écrasés), en Wi-Fi seulement si l'utilisateur l'a choisi. Un passage
   jusqu'à la tête suffit : le serveur refusant l'ancienne version, aucun
   ancien enregistrement ne peut réapparaître derrière le curseur.
5. **Fin** : la clé précédente est effacée quand plus rien n'en a besoin.

**Autres appareils** : à leur synchronisation suivante, ils apprennent
qu'une clé plus récente existe et s'arrêtent (« La clé de tes données a
été changée sur un autre téléphone… ») ; rien de local n'est perdu ; ils
reprennent avec le nouveau code ou un transfert depuis un appareil à jour,
puis envoient leurs modifications avec la nouvelle clé (celles-ci peuvent
donner des copies de conflit, jamais de perte).

**Limites connues** : l'ancien appareil a pu lire, avant d'être retiré,
tout ce qui existait — la rotation protège ce qui vient **après**. Un
fichier envoyé par un appareil resté sur l'ancienne clé pendant les
quelques secondes de la bascule (fichiers non versionnés côté serveur)
resterait illisible pour les autres appareils (fenêtre très courte, non
couverte). Tests : `test/sync/key_rotation_test.dart` (deux appareils),
`test/features/account/key_rotation_screen_test.dart` (écrans),
`supabase/tests/sql/60_key_rotation_test.sql`, contrat RPC sur Supabase
local.

### 4.11 Verrou Eripoo (accès à l'application)

Décision D4 (2026-10-06) ; implémenté dans `lib/features/app_lock/`.

| Aspect | Choix |
|---|---|
| Rôle | protection d'**accès à l'interface** sur un téléphone partagé ; **jamais** une protection cryptographique |
| Facultatif | désactivé par défaut ; activable et désactivable par l'utilisateur |
| PIN | 4 à 8 chiffres ; seul un **vérificateur Argon2id** (`crypto_pwhash_str`, 2 passes, 32 Mio, calculé dans un isolat) est conservé dans le stockage sécurisé ; le PIN n'est **jamais** stocké, ni utilisé comme clé ou pour dériver une clé |
| Biométrie | facultative, si disponible (`local_auth`, empreinte ou visage) ; activée seulement par l'utilisateur |
| Délai | immédiat, 1, 5 ou 15 min en arrière-plan (1 min par défaut) ; un démarrage à froid redemande toujours le PIN ; une horloge qui recule verrouille |
| Erreurs | 4 essais libres, puis attentes de 30 s, 1 min, 5 min, 15 min, puis 1 h ; compteurs conservés au redémarrage ; **aucun effacement de données** après des erreurs (le verrou ne protège pas les données, effacer détruirait le travail non synchronisé) |
| PIN oublié | si le téléphone a son propre verrouillage (ou la biométrie), il prouve que c'est le propriétaire et le verrou Eripoo est désactivé ; sinon, l'app explique de se reconnecter avec le code de récupération (les données synchronisées sont alors retrouvées ; un invité sans compte n'a pas ce recours) |
| Indépendance | les clés du Keystore ne sont pas liées à une authentification de l'utilisateur : activer, désactiver ou oublier le verrou ne peut **jamais** rendre les données illisibles |
| Affichage | l'app reste en mémoire sous l'écran de verrouillage, masquée aux lecteurs d'écran et au toucher |

Limites assumées : le délai d'attente repose sur l'horloge du téléphone
(modifiable par l'utilisateur) ; la miniature de l'app dans la liste des
applications récentes peut montrer le dernier écran (protection par
`FLAG_SECURE` à étudier, car elle bloque aussi les captures d'écran
légitimes) ; **biométrie et configuration Android non vérifiées sur
appareil** (activité `FlutterFragmentActivity`, permission
`USE_BIOMETRIC`, thème AppCompat ajoutés selon la documentation de
`local_auth`, vérifiables seulement par un build Android).

## 5. Code de récupération

### 5.1 Rôle exact

Le code ne sert **qu'à une chose** : déchiffrer la copie serveur de l'UMK
quand aucun appareil autorisé n'est disponible. Il ne permet pas de se
connecter (il faut aussi l'accès au compte), et l'accès au compte ne permet
pas de déchiffrer (il faut aussi le code ou un appareil).

### 5.2 Format pour l'utilisateur

```
 1      2      3      4      5      6      7      8      9
4829   1730   6654   0912   3388   7015   2246   9581   0637
```

- **36 chiffres en 9 groupes de 4** : 35 chiffres aléatoires
  (`randombytes_uniform(10)`) + 1 chiffre de contrôle **de Damm** (détecte
  toute erreur sur un chiffre et toute inversion de deux chiffres voisins).
- **Pourquoi des chiffres** : connus de tous, lisibles à voix haute en
  malagasy, français et anglais, sans confusion entre lettres (l'alphabet
  malagasy n'utilise pas c, q, u, w, x), familiers (numéros de téléphone,
  codes de mobile money). Contrepartie : plus long qu'un code alphanumérique
  (26 caractères pour 128 bits) à sécurité comparable.
- **Entropie** : 35 × log₂(10) ≈ **116 bits**, au-dessus du niveau de
  sécurité de 112 bits généralement recommandé pour une protection à long
  terme.

### 5.3 Création, affichage et sauvegarde

1. Proposée après l'inscription (ou plus tard depuis Profil), avec une
   explication en une phrase : « Ce code est la seule clé de secours de ton
   projet. Eripoo ne peut pas le retrouver. »
2. **Affichage** : grands chiffres à chasse fixe, groupes numérotés,
   bouton « Écouter » qui lit les chiffres avec des enregistrements audio
   (0–9) fournis par le contenu (pas de synthèse vocale, peu fiable en
   malagasy), écran protégé contre les captures (`FLAG_SECURE`).
3. **Sauvegarde, par ordre de préférence** :
   - **recopier à la main sur la « fiche de secours Eripoo »** (modèle
     imprimable ou à recopier sur papier) et la ranger chez soi ;
   - imprimer la fiche (PDF généré sur l'appareil, contenant aussi un QR du
     code) ;
   - confier une copie sous enveloppe à une personne de confiance ;
   - photo de la fiche : **déconseillée** (les galeries photo sont souvent
     sauvegardées dans le cloud et les téléphones partagés) ; si
     l'utilisateur le fait, l'app explique le risque.
   - L'app **déconseille explicitement** l'envoi par SMS, WhatsApp ou e-mail
     à soi-même.
4. **Confirmation** : ressaisie de 2 groupes tirés au hasard (ex. groupes 3
   et 7) ; puis vérification complète (§5.4) avant d'afficher « Code de
   secours actif ».
5. **Rappels** : à 7 jours, 30 jours, puis tous les 6 mois : « As-tu
   toujours ta fiche de secours ? » avec vérification facultative.

### 5.4 Vérification de validité du code

| Étape | Où | Ce qu'elle établit |
|---|---|---|
| 1. Format : 36 chiffres | appareil | saisie complète |
| 2. Chiffre de contrôle de Damm | appareil, instantané | erreur de frappe probable ⇒ message « un chiffre semble faux » sans calcul coûteux |
| 3. Argon2id puis déchiffrement authentifié de `wrapped_umk` | appareil | **preuve que le code est le bon** : le tag Poly1305 n'est valide qu'avec la bonne KEK |

Le serveur ne participe pas à la vérification et ne reçoit jamais le code.
L'appareil conserve une copie locale de l'enveloppe pour les vérifications
périodiques sans réseau.

### 5.5 Résistance au brute-force hors ligne

- **Constat honnête** : tout système où le serveur garde une copie de la
  clé protégée par un code permet, en théorie, de tester un code candidat
  (le tag d'authentification confirme ou non). La protection ne peut donc
  venir que de l'**impossibilité pratique** de tester assez de codes. C'est
  pourquoi le serveur ne détient rien d'autre : ni hachage du code, ni
  chiffre de contrôle, ni indice, ni partie du code.
- **Ordre de grandeur**, avec une hypothèse très favorable à l'attaquant de
  10¹⁰ évaluations Argon2id (64 Mio) par seconde : il faut en moyenne
  2¹¹⁵ ≈ 4 × 10³⁴ essais, soit environ **10¹⁷ années**. Même sans Argon2id,
  à 10¹⁵ essais par seconde, il faudrait environ 10¹² années.
- Argon2id est donc une **défense en profondeur**, pas la protection
  principale : c'est l'aléa du code qui protège.
- **Pourquoi pas un code court ou un PIN** : un PIN de 6 chiffres (20 bits)
  serait épuisé en quelques secondes hors ligne. Le protéger exigerait un
  limiteur de tentatives matériel côté serveur (enclave sécurisée, module
  matériel), exploité par Eripoo — ce qui contredit l'objectif de ne pas
  faire confiance à l'opérateur. Décision : **pas de récupération par PIN**.

### 5.6 Limitation des tentatives

La limitation ne peut pas arrêter une attaque hors ligne (couverte par
§5.5) ; elle limite les attaques en ligne et alerte l'utilisateur.

| Où | Règle |
|---|---|
| Téléchargement de l'enveloppe (RPC `get_recovery_wrap`) | session authentifiée exigée ; 5 appels par heure, 20 par jour et par compte ; chaque appel est journalisé (métadonnée) et déclenche une notification « Une récupération a été demandée sur ton compte » (e-mail ou SMS, et sur les appareils autorisés) |
| Saisie dans l'app | après 5 échecs, délais croissants (30 s, 1 min, 5 min, 15 min) ; le coût d'Argon2id (≈ 1–3 s) ralentit déjà chaque essai |
| Connexion au compte | limites de débit et CAPTCHA de Supabase Auth |
| Remplacement de l'enveloppe (RPC `set_recovery_wrap`) | réauthentification récente exigée (mécanisme exact de Supabase à confirmer en Phase 2) ; notification à l'utilisateur |

## 6. Transfert vers un nouvel appareil (double QR hors ligne)

### 6.0 Où en est le multi-appareil (Phase 2) — à lire d'abord

Deux mécanismes différents donnent la clé de données (UMK) à un autre
téléphone. **Seul le premier existe aujourd'hui.**

| | Récupération par le code (§5, §7) | Transfert par double QR (§6.1–6.7) |
|---|---|---|
| À quoi il sert | retrouver ses données sans autre appareil (perte, vol, réinstallation) ; aujourd'hui aussi : ajouter un 2ᵉ appareil | ajouter un appareil quand on en a encore un autorisé, sans taper le code |
| Implémenté | **oui** : création du code, enveloppe Argon2id stockée sur le serveur, déverrouillage sur un nouvel appareil (`AccountLinker.unlockWithRecoveryCode`), refus d'un appareil lié à un autre compte | **oui (Phase 5)** — voir §6.10 ; appareils réels non vérifiés |
| Testé | automatique : faux serveur (scénario 10 : invité → compte → 2ᵉ téléphone avec le code) ; contrat RPC sur **Supabase local** (stockage exact de l'enveloppe, paramètres faibles refusés, limite de 5 récupérations/heure) ; Argon2id mesuré sur émulateur | — |
| Provisoire | **c'est le seul chemin vers un 2ᵉ appareil**, donc tout ajout demande le code. Pas encore d'écran, pas de notification des autres appareils (§6.8), pas de fiche de secours imprimable | — |
| Après la Phase 5 | reste le **chemin de secours** (plus aucun appareil). Format de l'enveloppe inchangé | devient le **chemin normal** quand un appareil autorisé est présent ; ajoute les notifications d'ajout |

La migration invité → compte actuelle n'est donc **pas** le protocole
multi-appareil définitif : elle couvre « premier compte » et « récupération
par le code », pas le transfert direct entre deux téléphones.

### 6.1 Principe

L'UMK passe de l'ancien appareil (**A**, déjà autorisé) au nouvel appareil
(**N**) par deux QR codes, téléphones côte à côte. **Rien ne passe par le
réseau.** Seules des constructions libsodium sont utilisées :
`crypto_box_keypair`, `crypto_box_seal`, `crypto_box_seal_open`,
`crypto_generichash`. C'est le même modèle que la liaison d'appareils par QR
des messageries chiffrées : le canal optique (l'utilisateur tient les deux
téléphones) est le canal authentifié.

### 6.2 Prérequis

- N est installé et **connecté au même compte** (sinon A refuse).
- A est autorisé, l'app est déverrouillée, et l'utilisateur confirme son
  identité localement : verrouillage du téléphone (PIN, schéma, empreinte)
  s'il existe, sinon verrou Eripoo s'il est activé.
- Moins de 5 appareils actifs (§6.8).

### 6.3 Déroulé

```
 N (nouveau)                                      A (ancien, autorisé)
 ───────────                                      ────────────────────
 1. (pk_N, sk_N) = crypto_box_keypair()   [RAM seulement]
    tid = randombytes_buf(16)
    V   = 6 chiffres issus de generichash("eripoo:xfer:v1" || tid || pk_N)
    affiche QR1 + code V
                         ── QR1 (optique) ──►    2. scanne QR1 (écran « Ajouter un appareil »)
                                                    vérifie version, compte, limite
                                                 3. demande : « Tape le code affiché sur
                                                    ton nouvel appareil » → doit égaler V
                                                    + « Ajouter « Tablette » ? »
                                                 4. P = 0x01 || owner_id || umk_version
                                                        || UMK || tid || device_id_A
                                                    C = crypto_box_seal(P, pk_N)
                                                    affiche QR2 (2 min max, FLAG_SECURE)
                         ◄── QR2 (optique) ──
 5. P = crypto_box_seal_open(C, pk_N, sk_N)
    vérifie : version, owner_id = compte connecté, tid = le sien
 6. affiche « Clé reçue de « Téléphone » » → confirmation
 7. stocke l'UMK (Keystore), efface sk_N, P
 8. vérifie la clé : déchiffre les derniers enregistrements du compte
 9. s'enregistre (RPC register_device) ; les autres appareils et l'e-mail
    du compte reçoivent « Nouvel appareil ajouté »
```

Formats :

```
QR1 = "ERPT1:" || base64url( 0x01 || tid (16) || pk_N (32) || device_id_N (16)
                             || compte_indice (8) || libellé UTF-8 (≤ 24) )
      compte_indice = generichash(owner_id, 8 octets)  -- évite d'exposer l'id

QR2 = "ERPT2:" || base64url( C )      -- P = 83 octets, C = 83 + 48 = 131 octets
```

### 6.4 Comment les appareils s'authentifient

| Sens | Mécanisme |
|---|---|
| A s'assure de parler à **N** | A lit QR1 **directement sur l'écran de N** ; l'utilisateur tape sur A le code V affiché par N ; l'indice de compte doit correspondre |
| N s'assure de recevoir **la bonne clé** de **A** | N lit QR2 directement sur l'écran de A ; le contenu contient `tid` (connu seulement de qui a vu QR1) et `owner_id` ; N vérifie enfin que la clé déchiffre bien les données existantes du compte |
| Le serveur | n'intervient pas dans l'échange ; il enregistre seulement l'appareil |

### 6.5 Protection pendant le transfert et interposition

| Tentative | Résultat |
|---|---|
| Photographier QR1 | n'apporte que `pk_N` et `tid` (publics) |
| Photographier QR2 | inutile : seul `sk_N`, qui n'a jamais quitté la RAM de N, ouvre `C` |
| Capturer l'écran de A à distance (partage d'écran, capture) | bloqué par `FLAG_SECURE` sur les écrans de transfert et du code |
| Faire scanner à A un QR1 envoyé par un tiers (hameçonnage : « scanne ce code ») | le scan n'est possible que depuis l'écran « Ajouter un appareil » après confirmation d'identité ; avertissement explicite (« ne scanne que ton propre téléphone, que tu tiens en main ») ; le tiers devrait en plus voir QR2, protégé par `FLAG_SECURE` |
| Présenter physiquement un faux QR1 à A au bon moment | l'utilisateur doit taper le code de **son** appareil ; un attaquant présent, préparé, qui aurait vu ce code, pourrait en théorie fabriquer une clé correspondante — **risque résiduel accepté**, qui suppose une présence physique au moment exact |
| Présenter physiquement un faux QR2 à N | N rejette tout contenu dont `tid` ne correspond pas (il faut avoir vu QR1) et toute clé qui ne déchiffre pas les données du compte |

### 6.6 Expiration

Indépendante de l'horloge du téléphone (souvent fausse) :

- `sk_N` n'existe qu'en RAM ; elle est détruite après 5 minutes
  d'affichage, à l'annulation, au succès, ou si l'app passe en arrière-plan
  plus de 30 s ou est fermée. Après cela, QR2 devient inexploitable pour
  toujours.
- A n'affiche QR2 que 2 minutes et n'en garde aucune copie.

### 6.7 Interruption

| Moment | Effet | Reprise |
|---|---|---|
| Avant le scan de QR2 | aucun changement | recommencer |
| N fermé après le scan, avant stockage | `sk_N` perdue | recommencer avec un nouveau QR1 |
| UMK stockée, appareil pas encore enregistré | N termine l'enregistrement et la sync au prochain lancement (opérations idempotentes) | automatique |
| A a annoncé N mais N n'a jamais fini | l'enregistrement en attente expire après 24 h et ne compte pas dans la limite | automatique |

### 6.8 Ajout, révocation, limite

- **Ajout** : par double QR (§6.3) ou par code de récupération (§7).
  Chaque ajout est notifié aux autres appareils et par e-mail/SMS.
- **Limite** : 5 appareils actifs (réglable côté serveur) ; au-delà, il
  faut d'abord en révoquer un.
- **Révocation** depuis tout appareil autorisé (confirmation d'identité +
  réauthentification de moins de 10 minutes) : `revoked_at` posé, sync
  refusée pour l'appareil révoqué, qui **efface ses données, ses clés et sa
  session** à sa prochaine tentative de synchronisation.

**Implémenté en Phase 2** (migration `20261007000001_device_sessions.sql`,
`SyncRunner`, `LocalDataEraser`) :

- chaque appareil retient la **session d'authentification** qu'il utilise
  (`session_id` du jeton Supabase, conservé lors des rafraîchissements) ;
- la révocation **supprime cette session** côté Supabase (son jeton de
  rafraîchissement ne marche plus) ; les jetons d'accès déjà émis restent
  valides jusqu'à expiration (1 h), mais **toutes** les fonctions les
  refusent (`device_revoked`), y compris pour enregistrer un nouvel
  identifiant d'appareil ou lire l'enveloppe de récupération ;
- pourquoi c'était nécessaire : sans ce lien, l'appareil révoqué (ou des
  jetons volés) pouvait s'enregistrer sous un nouvel identifiant et
  continuer à synchroniser. Une session ordinaire sur un autre appareil
  n'est pas touchée (pas de `signOut(scope: others)` nécessaire) ;
- côté appareil révoqué : base, WAL, clés, identifiant d'appareil, session
  et réglages du verrou sont effacés ; au redémarrage l'app repart vide avec
  un nouvel identifiant. Le revenir au compte exige une nouvelle connexion
  **et** le code de récupération. **Les modifications non synchronisées
  sont perdues** (choix assumé : l'appareil est présumé perdu ou volé) ;
- testé : SQL (PostgreSQL + Supabase local), contrat RPC sur Supabase local
  (dont « la session révoquée ne peut plus se rafraîchir »), test de bout
  en bout sur base chiffrée réelle (`test/sync/revocation_test.dart`).

**Fait au chantier C-4 (2026-10-22)** : sur chaque autre téléphone,
l'Accueil signale « Nouvel appareil sur ton compte » (nom et date d'ajout
seulement, lus par `list_devices`), avec « C'est moi » et « Voir mes
appareils ». Chaque téléphone retient localement la date serveur du plus
récent appareil déjà vu (pas son horloge) ; la première fois, les appareils
existants sont considérés comme connus. Hors ligne ou sans compte : rien.
**Reste** : l'e-mail (Edge Function ou hook Supabase, avec un fournisseur
d'envoi à choisir par le porteur) ; pas de SMS sans décision.

**Fait en Phase 5** : écran « Mes appareils » (liste par `list_devices`,
métadonnées seulement) et retrait avec mot de passe redemandé quand le
serveur l'exige ; synchronisation automatique (le téléphone retiré
découvre son retrait au cycle suivant, efface tout et affiche
« Redémarrer »). **Pas encore fait** : message au redémarrage expliquant
l'effacement (la raison est conservée : `LocalDataEraser.lastReason`),
notifications.

### 6.9 Appareil perdu ou volé

1. Depuis un autre appareil autorisé, ou un nouvel appareil récupéré par le
   code : « J'ai perdu un appareil » ⇒ révocation (§6.8).
2. Le voleur n'obtient plus aucune donnée nouvelle.
3. Les données déjà présentes sur l'appareil restent protégées par son
   verrouillage d'écran, le Keystore, la base chiffrée et le verrou Eripoo
   s'il était actif — pas au-delà (§2.2).
4. Si une compromission de l'UMK est suspectée (téléphone non verrouillé,
   *rooté*) : rotation (§4.10).
5. Les modifications jamais synchronisées depuis cet appareil sont perdues.

### 6.10 Implémentation (Phase 5) et écarts

Code : `lib/security/device_transfer.dart` (protocole pur),
`lib/features/account/application/device_transfer_service.dart` (côté
serveur et stockage), écrans `lib/features/devices/presentation/`.
Tests : `test/security/device_transfer_test.dart` (formats, §6.5, §6.6),
`test/features/account/device_transfer_service_test.dart` (§6.7, deux
téléphones sur le faux serveur), `test/features/account/
profile_screens_test.dart` (écrans des deux côtés).

| Point | Spécification | Implémenté | Pourquoi |
|---|---|---|---|
| Indice de compte (QR1) | `generichash(owner_id, 8)` | 8 premiers octets de `generichash("eripoo:xfer:v1:" ‖ owner_id, 16)` | libsodium refuse une sortie de moins de 16 octets ; le préfixe sépare cet usage des autres |
| Code V | 6 chiffres du `generichash` | 8 premiers octets modulo 10⁶ (biais < 10⁻¹³) | — |
| Ordre côté N (§6.3 étapes 7–9) | stocker, vérifier, s'enregistrer | **s'enregistrer, vérifier, puis stocker** | la vérification lit les données du compte, ce qui demande un appareil enregistré ; ainsi une clé non vérifiée n'est jamais stockée. Hors ligne, la clé reçue reste en mémoire et l'utilisateur réessaie sans rescanner |
| Vérification de la clé | déchiffre les données existantes | ouvre le premier enregistrement de la même version de clé (5 pages de 50 au plus) ; toute erreur ⇒ refus | — |
| Compte sans aucune donnée | — | clé acceptée sans vérification possible | **risque résiduel** : il faut avoir vu QR1 et être présent au moment exact (§6.5) |
| Enregistrement « en attente » 24 h (§6.7, ligne 4) | A annonce N au serveur | **pas d'annonce** : N s'enregistre lui-même | sans annonce, rien n'est en attente ; un enregistrement fait puis interrompu est refait sans être compté deux fois |
| Confirmation d'identité sur A (§6.2) | verrouillage du téléphone, sinon verrou Eripoo | verrouillage du téléphone s'il existe, sinon code du verrou Eripoo (mêmes limites d'essais que l'écran de verrouillage) ; fait au chantier C-5, aussi pour le retrait d'un appareil, la rotation de clé et la suppression du compte | sans aucun verrou, rien de plus ne peut être demandé sur ce téléphone |
| Notification « Nouvel appareil ajouté » (§6.8) | autres appareils + e-mail | **non faite** | l'événement `device_added` est enregistré côté serveur |
| Lecture des QR | — | `camera` + `zxing2` (Dart pur, sur un isolat, ≈ 4 images/s) ; génération `qr` | pas de Google ML Kit (métriques d'usage envoyées à Google, services Play requis) |
| `FLAG_SECURE` | écrans de transfert et du code | canal natif `eripoo/secure_window` (`MainActivity.kt`) : écrans QR1/code, QR2, code de secours (affichage et saisie) | non vérifié sur appareil |
| Permissions | — | caméra demandée au moment du scan ; `RECORD_AUDIO` et `WRITE_EXTERNAL_STORAGE` (déclarées par le module caméra) retirées du manifeste final | aucun enregistrement audio (avis P6 en attente) |

**Changement de la clé de données (récupération ou transfert).** Défaut
trouvé en Phase 5 : les photos locales sont chiffrées avec une sous-clé de
la clé de données ; la remplacer les rendait illisibles. `KeyManager`
garde désormais l'ancienne clé (`eripoo.umk.previous`, Keystore) jusqu'à
ce que chaque photo lisible soit rechiffrée (au démarrage, fichier par
fichier via `.part` + renommage) ; un arrêt brutal entre-temps ne perd
rien (test). L'ancienne clé est effacée ensuite et avec toutes les données
locales.

## 7. Scénarios de compte

| Scénario | Accès au compte | Accès aux données |
|---|---|---|
| **Changement de mot de passe** | via Supabase Auth ; option « Déconnecter les autres appareils » | **aucun effet** : UMK et code inchangés |
| **Mot de passe oublié** | réinitialisation par e-mail | aucun effet ; un appareil ou le code reste nécessaire sur un nouvel appareil |
| **Authentification Google** | jeton d'identité du SDK Google natif ⇒ `signInWithIdToken` ; pas de mot de passe Eripoo | aucun effet ; Google ne voit aucune clé. Compte Google compromis ⇒ l'attaquant obtient une session, donc du chiffré, et peut demander l'enveloppe (limitée, notifiée) — inutile sans le code |
| **Authentification téléphone** | OTP par SMS ; changement de numéro via la mise à jour du téléphone du compte (OTP sur le nouveau numéro) | aucun effet. *SIM swap* ⇒ session seulement ; d'où l'invitation à lier une seconde méthode (`linkIdentity`) |
| **Récupération du compte** (toutes les méthodes perdues) | procédure manuelle d'identification par le support, limitée à l'accès au compte | le support **ne peut pas** rendre les données : il faut un appareil ou le code |
| **Suppression du compte** (Phase 10) | Profil → « Supprimer mon compte » : avertissement, mot de passe redemandé (connexion de moins de 10 minutes), puis suppression des fichiers chiffrés (Storage), puis RPC `delete_account` (suppression de l'utilisateur Auth et, en cascade, de `sync_records`, `sync_heads`, `user_keys`, `devices`, `profiles`, `consents`, `security_events`) — fonction SQL plutôt qu'Edge Function : rien à exécuter hors de la base | effacement local (base, médias, UMK, DBK) après confirmation du serveur ; hors ligne, rien n'est effacé et on peut réessayer. Les autres téléphones gardent leur copie locale jusqu'à « Me déconnecter et effacer ce téléphone ». Proposition d'export (PDF du dossier) : non ajoutée à ce flux. Les sauvegardes de la plateforme peuvent garder du chiffré pendant leur rétention : illisible sans appareil ni code. **Avis juridique** (durées de conservation, loi 2014-038) : en attente |
| **Se déconnecter et effacer ce téléphone** (Phase 10) | le téléphone se retire lui-même du compte (`leave_device`, seulement l'appareil lié à la session appelante), puis fin de session | tout ce qu'Eripoo garde sur ce téléphone est effacé ; le compte et les autres téléphones ne changent pas ; hors ligne, l'effacement local a lieu quand même (retirer l'appareil plus tard depuis un autre) |
| **Perte de tous les appareils, code conservé** | connexion sur un nouvel appareil | saisie du code (§5.4) ⇒ UMK ⇒ enregistrement de l'appareil ⇒ téléchargement complet |
| **Perte de tous les appareils et du code** | compte accessible | **données en ligne définitivement illisibles**, pour tout le monde. Option « Recommencer » : nouvelle UMK, ancien chiffré supprimé après confirmation explicite |
| **Perte du code, un appareil restant** | — | « Créer un nouveau code » : confirmation d'identité + réauthentification ⇒ nouveau code, nouveau sel, nouvelle enveloppe vérifiée ⇒ **ancienne enveloppe supprimée immédiatement** (un ancien code retrouvé n'ouvre plus rien) ⇒ notification |

## 8. Pourquoi un administrateur ne peut pas déchiffrer

| Élément sur le serveur | Ce qu'il faudrait pour le lire | Où cela se trouve |
|---|---|---|
| `sync_records.payload` | `K_rec` ← UMK | appareils de l'utilisateur |
| `user-media` | `K_med` ← UMK | idem |
| `user_keys.wrapped_umk` | le code de récupération (116 bits) | chez l'utilisateur |
| Sel et paramètres Argon2id | — (publics par conception) | — |
| Sessions, clé `service_role` | — | donnent accès au chiffré, rien de plus |
| Edge Functions | — | ne reçoivent jamais de clé ni de contenu (sauf §13, sur consentement) |
| Transfert entre appareils | — | ne passe pas par le serveur |

Couches complémentaires : RLS sans aucune politique pour le personnel sur
les tables privées (tests pgTAP : 0 ligne lisible par chaque rôle) ;
back-office sans écran utilisateur ni clé `service_role` ; tableau de bord
Supabase limité à 2 personnes avec MFA et audit.

## 9. Décision D1/D2 : niveau de garantie

| Option | Garantie « le personnel ne peut pas lire » | Risque de perte |
|---|---|---|
| **A. E2EE + code de récupération + transfert QR** (recommandée) | technique, forte | réel si appareils et code sont tous perdus |
| B. A + séquestre à double contrôle (UMK aussi enveloppée par une clé conservée hors ligne, scindée entre 2 personnes, utilisée seulement à la demande vérifiée de l'utilisateur) | affaiblie : une collusion interne permettrait la lecture ; à annoncer | faible |
| C. Pas d'E2EE, RLS seule | organisationnelle — **ne satisfait pas l'exigence** | nul |

B s'ajoute plus tard sans migration (une enveloppe de plus de la même UMK).

## 10. Authentification

- **Invité local** : aucun compte, aucune requête réseau.
- **MVP** : e-mail + mot de passe (confirmation d'e-mail), Google (SDK natif
  → `signInWithIdToken`), téléphone (OTP SMS, fournisseur à tester — R4).
  **Facebook** prévu dans l'énumération des fournisseurs, désactivé.
- **Plusieurs méthodes** : `linkIdentity`, `linkIdentityWithIdToken`,
  `unlinkIdentity` (vérifiés dans `supabase_flutter` 2.18.0 / `gotrue`
  2.27.2) ; liaison manuelle à activer dans la configuration Auth.
- **Session** : flux PKCE ; stockée dans `flutter_secure_storage`, **pas**
  dans SharedPreferences (comportement par défaut de `supabase_flutter`,
  vérifié dans le code source).
- Limitation de débit et CAPTCHA sur inscription et OTP.

## 11. Journaux, erreurs, stockage local

- Logger expurgé : codes d'événement, identifiants techniques, durées.
  Interdits : textes saisis, noms, e-mails, téléphones, jetons, clés, codes
  de récupération, chemins de médias, contenus de QR, payloads.
- Rapports d'erreur : type + pile + version, **sans le message
  d'exception**. Aucun service de rapport de crash n'est intégré.
- `print` et `debugPrint` interdits dans `lib/` (test). Sauvegarde Android
  désactivée.

Vérifié automatiquement (Phase 2) :

| Canal | Test |
|---|---|
| journaux (mémoire et console) | `test/security/privacy_leak_test.dart` : une sentinelle saisie dans le projet, une section et le profil n'apparaît dans aucun enregistrement, ni rendu |
| erreurs et exceptions | même test (erreurs de validation sur entrée privée, erreurs réseau) ; règle d'architecture : aucune exception de `lib/` ne porte de texte ; les erreurs Supabase sont converties en codes sans message |
| requêtes RPC | même test : corps JSON exacts de toutes les requêtes (sync, appareil, enveloppe) ; contrat sur Supabase local |
| fichiers temporaires | même test : seuls `eripoo.sqlite`, `-wal`, `-shm` existent, sans texte clair ; `temp_store = memory`. **Exception volontaire** : un PDF partagé par l'utilisateur (§11.1), effacé après le partage et au démarrage |
| stockage sécurisé | même test : clés et identifiants seulement |
| analytics, crash, IA | règle d'architecture : aucun SDK d'analytics, de crash ou d'IA dans `pubspec.lock` |
| messages de debug | règle d'architecture (`print`, `debugPrint`) ; **exception connue** : en build *debug* uniquement, le gestionnaire Flutter par défaut affiche aussi le message d'erreur dans la console du développeur (données fictives seulement) |
| données de test et CI | règle d'architecture : adresses e-mail seulement en `example.com/.org/.invalid`, aucun numéro malgache ; les tests Supabase créent des comptes fictifs aléatoires |

Non vérifiable automatiquement : journaux système Android (`logcat`) sur
appareil réel — l'app n'y écrit que via `developer.log` en debug.

### 11.1 Export PDF (Phase 7) — seule sortie volontaire en clair

Le dossier et le pitch deck peuvent être partagés en PDF. C'est la seule
façon de faire sortir le projet **en clair** de l'application, et
seulement sur action de l'utilisateur :

- avant tout fichier, un message dit que le PDF n'est plus protégé par
  Eripoo une fois partagé (« Envoie-le seulement à qui tu choisis ») ;
- le PDF est construit sur l'appareil (paquet `pdf`, police Roboto
  embarquée), jamais par un serveur ; rien n'est envoyé par Eripoo :
  c'est le menu de partage d'Android (`share_plus`) qui le passe à
  l'application choisie par l'utilisateur ;
- le fichier est écrit dans le cache privé de l'application
  (`cache/export`), puis effacé dès que le partage rend la main ;
  `share_plus` en garde une copie dans `cache/share_plus` jusqu'au
  partage suivant (l'application qui reçoit peut encore la lire) : les
  deux dossiers sont effacés à chaque démarrage. Risque résiduel : la
  copie reste dans le cache privé (inaccessible aux autres applications)
  entre un partage et le démarrage suivant ;
- le contenu du PDF n'est jamais journalisé ; le nom du fichier reprend
  le titre du projet, réduit aux lettres et chiffres.

Vérifié automatiquement : construction du PDF (mg, fr, en, caractères
typographiques), avertissement avant partage, fichier effacé après le
partage, purge des deux dossiers (`test/features/documents/`). Non
vérifié : partage réel vers une autre application sur A et B.

### 11.2 Réponses orales (Phase 9)

Une question ouverte du parcours peut recevoir une réponse orale :

- l'autorisation `RECORD_AUDIO` est demandée au premier enregistrement ;
  un refus est expliqué et la réponse écrite reste possible ;
- l'enregistreur du système (`record`) écrit l'audio (AAC, mono, 16 kHz,
  32 kbit/s, 3 minutes au plus ≈ 750 Ko) dans `cache/voice`, dans le
  stockage privé de l'application : c'est le seul moment où la voix est
  **en clair sur le disque**, le temps de l'enregistrement ;
- dès l'arrêt, le fichier est lu, chiffré dans le magasin de médias
  (format §4.7, `kind = audio`) puis effacé, y compris en cas d'erreur ;
  « Annuler », quitter la question pendant l'enregistrement ou une
  erreur effacent aussi le fichier ; `cache/voice` est vidé à chaque
  démarrage (fichier laissé par un arrêt brutal) ;
- pour l'écoute, le média est déchiffré dans une copie temporaire du même
  dossier, effacée après l'écoute (et au démarrage suivant au plus tard) ;
- rien n'est transcrit, rien n'est envoyé à un service de reconnaissance
  vocale ou d'IA ; l'enregistrement est synchronisé chiffré comme une
  photo ; un enregistrement remplacé ou supprimé est effacé pour toujours,
  sans passer par la corbeille ;
- jamais proposé pour les personnes interrogées (avis juridique P6).

Risque résiduel : le fichier en clair de l'enregistrement en cours existe
dans le cache privé (inaccessible aux autres applications sans root)
jusqu'à l'arrêt. Vérifié automatiquement : chiffrement, effacement du
fichier en clair, purge, remplacement et suppression
(`test/features/voice/`). Non vérifié : micro réel sur A et B.

## 12. Analytics anonymisés

Opt-in (D7), désactivés par défaut pour les mineurs ; aucun identifiant ;
liste blanche d'événements et de propriétés (identifiants du contenu public
uniquement) revalidée par l'Edge Function ; envoi quotidien par lot ;
l'IP n'est pas stockée par l'Edge Function (la plateforme peut la
journaliser — à vérifier et à mentionner) ; brut 90 jours puis agrégats.

## 13. IA et services externes

Règle du porteur (2026-10) : **aucune donnée de projet privée n'est
envoyée à un modèle d'IA externe.** Elle prime sur la version précédente
de cette section (envoi après consentement).

État à la Phase 9 :

- aucune IA n'est branchée ; `AiAssistant` (`lib/features/ai/`) est le
  seul point où un fournisseur pourrait l'être, et son implémentation par
  défaut, `DisabledAiAssistant`, ne fait rien et n'envoie rien ;
- la détection d'incohérences (« Points à revoir ») est faite par des
  règles fixes, sur l'appareil, sans IA (§24 du cahier des charges : une
  règle déterministe suffit) ;
- les réponses orales ne sont **pas** transcrites (§11.2).

Si une IA est un jour ajoutée : uniquement sur l'appareil, ou pour un
texte que l'utilisateur choisit d'envoyer après un écran de consentement
explicite montrant ce qui part, jamais pour le contenu privé du projet
sans son geste ; fournisseur remplaçable derrière une Edge Function
proxy sans stockage ; contrat excluant l'entraînement (à vérifier) ;
décision du porteur et avis juridique (transferts hors de Madagascar)
avant tout branchement.

## 14. Mineurs

Déclaration d'âge (année de naissance chiffrée ; seule la tranche est
connue du serveur) ; règles lues depuis `jurisdiction_policies`, **aucune
valeur dans le code**, release bloquée tant que `legal_validated = false` ;
parcours identique ; analytics et IA désactivés par défaut ; consentement
parental conçu après analyse juridique (D12).

## 15. Intégrité du contenu pédagogique

**État (vérifié le 2026-10-25) : non implémenté.** Aujourd'hui, le seul
pack est intégré à l'APK (`assets/content/base_pack.json`) ; l'app ne
télécharge aucun contenu, donc l'intégrité du contenu repose sur la
signature de l'APK. La signature des packs ci-dessous est **obligatoire
avant** toute mise à jour du contenu sans nouvelle APK (NEXT_STEPS, C-14).

Conception : packs signés Ed25519 par une clé de publication conservée **hors ligne** ;
clé publique intégrée à l'app ; pack à signature invalide refusé. Même une
compromission de Supabase ne permet pas de pousser du contenu trompeur
(ex. demander le code de récupération). Le langage de règles n'exécute
aucun code. Le code de récupération n'est saisi que dans l'écran système
dédié, jamais dans un écran de contenu.

## 16. Droits de l'utilisateur

Export sur l'appareil (JSON + médias, dossier PDF) ; suppression d'un
élément (corbeille 30 jours puis purge) ou du compte (§7) ; consentements
versionnés et révocables ; politique de confidentialité fr/mg/en à valider
juridiquement.

## 17. Validation et durcissement

Validation de domaine côté client ; contraintes Postgres et RPC validant
taille, versions, appareil, quotas et débit ; URL Supabase et clé `anon`
(publique par conception) via `--dart-define-from-file` non commité ; aucune
clé privée dans l'app ; trafic en clair interdit ; release obfusquée ;
permissions au moment de l'usage ; `FLAG_SECURE` sur les écrans du code de
récupération et du transfert.

**Contrôles automatiques (Phase 10)** :

- `test/architecture/android_release_test.dart` : permissions déclarées
  (`INTERNET`, `USE_BIOMETRIC`, `RECORD_AUDIO`, `POST_NOTIFICATIONS` —
  demandée seulement à l'activation des rappels de missions, chantier
  C-10 ; `WRITE_EXTERNAL_STORAGE` et `READ_EXTERNAL_STORAGE` retirées), sauvegarde Android désactivée
  (`allowBackup="false"` + règles d'extraction excluant tout), trafic en
  clair refusé (autorisé seulement en debug, pour Supabase local), une
  seule activité exportée, clés de signature hors Git.
- `tool/check_apk.sh` sur l'APK release en CI : permissions **fusionnées**
  (aucune permission « dangereuse » hors caméra et micro), drapeaux
  `usesCleartextTraffic`, `allowBackup`, `debuggable`, budget de taille.
- `AppConfig.hasBackend` : hors environnement local, une URL qui n'est pas
  en HTTPS est ignorée (pas de serveur plutôt qu'un serveur en clair).
- Scan des secrets versionnés et des SDK interdits (analytics, crash,
  IA) : `test/architecture/source_rules_test.dart`.

Deuxième défaut, trouvé par `check_apk.sh` sur la première APK contrôlée :
`READ_EXTERNAL_STORAGE` arrivait par une bibliothèque ; retirée (les photos
passent par le sélecteur du système, sans permission).

Défaut trouvé par cet audit : le manifeste principal ne déclarait pas
`INTERNET` (seules les variantes debug et profile l'avaient) : une APK
release n'aurait jamais pu joindre le serveur. Corrigé.

Quota : 2 000 fichiers par compte (politique Storage). Un quota en octets
demande une vérification sur le vrai Storage (NON VÉRIFIÉ).

## 18. Dépendances cryptographiques

Vérifications faites le 2026-10-06 (pub.dev, code source des paquets dans
le cache pub, dépôt public de SQLite3MultipleCiphers).

### 18.1 `sodium` (liaison Dart) et libsodium

| Point | Constat |
|---|---|
| Version retenue | `sodium` **4.1.1+2** (publiée le 2026-09-29), embarquant **libsodium 1.0.22**. Utiliser la variante « sumo » pour Argon2id. `sodium_libs` est abandonné au profit de `sodium` 4.x. |
| Maintenance | liaison maintenue principalement par une personne (dépôt `libsodium_dart_bindings`), publications régulières ; libsodium : projet de référence, largement déployé et audité |
| Dépendances natives | l'archive source de libsodium est **incluse dans le paquet** avec sa signature minisign, vérifiée par l'outil du mainteneur au moment où il l'intègre (pas à chaque build) ; l'intégrité du paquet lui-même est garantie par l'empreinte de `pubspec.lock` ; un *build hook* compile libsodium avec le NDK Android (autotools) à la construction de l'app. Vérification de la signature minisign à ajouter dans notre CI (Phase 2) |
| Compatibilité Android | architectures `armv7-a`, `arm64` (`armv8-a+crypto`), `x86_64`, `i686` ; API minimale = celle de l'app (24) ; pages de 16 Ko prises en charge (`max-page-size=16384`, exigence Play récente) |
| Licences | `sodium` : BSD 3-Clause ; libsodium : ISC — permissives, compatibles avec une distribution gratuite sur Play ; mentions à inclure dans l'écran des licences |
| Risques | dépendance à un mainteneur principal ; build natif plus long et nécessitant le NDK en CI (déjà requis pour Android) ; compilation sous Windows plus délicate (documentée par le paquet) |
| Remplacement | les formats stockés n'utilisent que des standards (XChaCha20-Poly1305 IETF, Argon2id v1.3, BLAKE2b, Ed25519) : ils restent lisibles par une autre implémentation (ex. paquet `cryptography`, ou bibliothèque native via canal Android). `crypto_box_seal` n'est utilisé que pendant un transfert, sans donnée stockée : remplaçable sans migration. Toute la cryptographie passe par une interface `CryptoService` étroite |

### 18.2 SQLite3MultipleCiphers (via le paquet `sqlite3`)

| Point | Constat |
|---|---|
| Version retenue | **SQLite3 Multiple Ciphers 2.5.0** avec **SQLite 3.53.4**, fournis par `sqlite3` 3.5.2 (version imposée par `drift` 2.35.1 ; `sqlite3` 3.7.0 existe). Dernière version amont : 2.5.1 (août 2026) |
| Maintenance | sqlite3mc : mainteneur principal unique (Ulrich Telle), actif depuis 2020, publications fréquentes ; `sqlite3` (Dart) : mainteneur de `drift`, très lié à notre pile |
| Dépendances natives | **binaires précompilés** par les mainteneurs de `sqlite3` (GitHub Actions, depuis les sources amont), téléchargés à la construction depuis les releases GitHub et **vérifiés par empreintes SHA-256 figées dans le paquet** ; option `url_pattern` pour servir ces binaires depuis un dépôt interne |
| Compatibilité Android | binaires `arm`, `arm64`, `ia32`, `x64` pour Android (empreintes vérifiées dans le paquet) |
| Chiffrement | schéma ChaCha20-Poly1305 (fixé explicitement) ; clé brute `raw:` sans PBKDF2 |
| **Licence** | **MIT — vérifiée** (fichier `LICENSE` et déclaration SPDX `PackageLicenseDeclared: MIT` du dépôt). Composants inclus examinés : SQLite (domaine public), implémentations ChaCha20-Poly1305, MD5, SHA-1, miniz (domaine public / Unlicense), fastpbkdf2 (CC0), Rijndael (MIT, d'après un original du domaine public), Ascon (MIT), autres composants sous CC0, Apache 2.0 ou ISC, **SHA-2 d'Olivier Gay sous licence BSD (mention de copyright à reproduire dans les distributions binaires)** |
| Verdict licence | **compatible avec une distribution gratuite sur le Play Store.** Obligations : afficher les mentions MIT, BSD (SHA-2) et ISC dans l'écran des licences de l'app (enregistrement via `LicenseRegistry` pour les bibliothèques natives) |
| Vérification de l'étiquette livrée | **faite le 2026-10-06** : `LICENSE` (MIT) et `LICENSE.spdx` (`PackageLicenseDeclared: MIT`) lus sur l'étiquette **v2.5.0**, version livrée par `sqlite3` depuis la 3.5.1 ; mention BSD de SHA-2 présente. Reste : validation de la liste des mentions par le juriste (DEVELOPMENT_PLAN P3, P6) |
| Risques | mainteneur principal unique ; binaires précompilés téléchargés au build (chaîne d'approvisionnement — atténuée par les empreintes figées) |
| Remplacement | 1) **SQLCipher Community Edition** par le même mécanisme (`source: sqlcipher`) : licence de type BSD avec mention ; sur Android il embarque OpenSSL (APK plus lourd, licence à vérifier à ce moment) ; 2) pas de chiffrement de base + chiffrement applicatif des champs avec libsodium : plus de code et de fuites de structure, **non recommandé** |

### 18.3 `flutter_secure_storage`

Version 11.2.0 (2026-09-16), BSD 3-Clause ; code Android vérifié (clé
RSA-OAEP du Keystore enveloppant une clé AES-GCM ; le mode « clé AES du
Keystore » est réservé à l'authentification biométrique et ne fonctionne
pas avant Android 9 — voir §4.4). Remplacement possible : petit canal natif Kotlin utilisant
directement le Keystore (sans changer le format des données stockées par
Eripoo, qui est versionné).
