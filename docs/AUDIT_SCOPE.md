# Périmètre proposé pour l'audit de sécurité externe (2026-10-25)

À remettre à l'auditeur avec l'accès au dépôt, une APK release du projet
de développement et un compte de test sur ce projet. **Jamais
l'environnement de production**, et uniquement des données fictives.
Document de référence : [SECURITY.md](SECURITY.md) (modèle de menace §2).

## Ce que l'auditeur doit chercher à prouver

Qu'une personne, quelle qu'elle soit (pirate, administrateur Supabase,
autre utilisateur), peut lire ou modifier le projet privé d'un utilisateur
sans son téléphone ni son code de récupération. Tout le reste est
secondaire.

## 1. Cryptographie et clés (priorité haute)

- Revue de l'usage de libsodium (`sodium` 4.1.1+2) : génération des clés,
  nonces, formats v1 des données, des médias et de l'enveloppe de clé
  (SECURITY §4.3 à §4.8).
- Code de récupération : aléa de 116 bits, Argon2id, absence de tout
  vérificateur côté serveur (§5).
- Rotation de la clé de données et révocation d'un appareil (§4.10, §6.8).
- Transfert vers un nouvel appareil par double QR hors ligne :
  interposition, rejeu, hameçonnage (§6.5).
- Stockage des clés dans Android Keystore et base locale chiffrée
  (sqlite3mc, ChaCha20-Poly1305) : comportement sur téléphone rooté ou sans
  composant sécurisé (§4.4, §4.5).

## 2. Serveur Supabase (priorité haute)

- RLS sur toutes les tables (`supabase/migrations/`) : un utilisateur ne
  doit jamais lire ni écrire les lignes d'un autre. Politiques : profils,
  consentements, appareils, Storage `user-media`.
- Les 18 fonctions RPC, en particulier : `sync_push`, `sync_pull`,
  `register_device`, `revoke_device`, `leave_device`, `list_devices`,
  `rotate_data_key`, `get_recovery_wrap` (limite de 5 par heure),
  `set_recovery_wrap`, `delete_account`, `record_usage`.
- Back-office (`staff_*`, schéma `authoring`) : contournement du rôle ou
  de la double authentification (aal2), accès à des données privées.
- Quotas et limites de débit (taille, nombre de fichiers, appels).

## 3. Application Android (priorité moyenne)

- Analyse de l'APK release : permissions, `allowBackup`, trafic en clair,
  activités exportées, obfuscation (`tool/check_apk.sh`).
- Données laissées en clair sur le téléphone : caches, fichiers
  temporaires des réponses orales, PDF exportés, journaux (`AppLogger`).
- Verrou Eripoo (code, biométrie) : contournement, limite d'essais (§4.11).
- `FLAG_SECURE` sur les écrans du code et du transfert : **jamais vérifié
  sur un vrai téléphone**.
- Absence de « certificate pinning » : avis de l'auditeur sur l'intérêt de
  l'ajouter, sachant que le contenu est déjà chiffré de bout en bout.

## 4. Chaîne de construction (priorité moyenne)

- Secrets GitHub et environnement `production` protégé, clé de signature
  Play hors Git.
- Dépendances (`pubspec.lock`) : bibliothèques à risque ou abandonnées.
- Workflows GitHub Actions : injection possible depuis une PR.

## Hors périmètre

- Production (n'existe pas encore).
- Attaques physiques avancées sur le matériel.
- Ingénierie sociale envers l'utilisateur (documentée comme non protégée,
  SECURITY §2.2).
- Packs de contenu signés : non implémentés tant que le contenu reste
  intégré à l'APK (SECURITY §15), à auditer quand ils le seront.

## Livrable attendu

Un rapport classant chaque défaut par gravité (critique, élevée, moyenne,
faible), avec un scénario reproductible et une recommandation ; puis une
contre-vérification après correction.
