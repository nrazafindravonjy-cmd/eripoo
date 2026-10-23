# Eripoo — Checklist de release (Phase 10)

À dérouler **entièrement** avant toute publication (test fermé compris).
Chaque ligne est soit vérifiée automatiquement par la CI (✅ auto), soit
à faire et à prouver (capture, mesure, avis écrit) au moment de la
release. Rien n'est coché sans preuve. État au 2026-10-08 : **la release
n'est pas possible** — les points bloquants de la section 1 sont ouverts.

## 1. Bloquant : décisions et avis extérieurs

- [ ] **Avis juridique** : mineurs de 14 à 17 ans, transferts hors de
  Madagascar (loi 2014-038), données de tiers dans les entretiens,
  contenu réglementaire EDBM, durées de conservation après suppression de
  compte, politique de confidentialité et conditions d'utilisation
  (textes à rédiger, puis à faire relire).
- [ ] **Revue cryptographique externe** de l'assemblage (SECURITY §4, §6,
  rotation §4.10) et **audit de sécurité** (application + base) par un
  tiers. L'audit automatisé de la Phase 10 n'en tient pas lieu.
- [x] **Région de production** Supabase (D9) — **eu-west-3 (Paris)**,
  décidée par le porteur le 2026-10-23. L'avis juridique sur le transfert
  hors de Madagascar (P6) reste à obtenir.
- [ ] **Création de l'environnement de production** (non créé ; c'est le
  porteur qui le crée) :
  1. Supabase → New project, région **West EU (Paris) `eu-west-3`**, mot
     de passe de base long gardé au coffre ;
  2. Authentication : confirmation d'e-mail activée, limites de débit
     Auth vérifiées, inscriptions par e-mail seulement (pas de SMS, de
     Google ni de téléphone sans décision) ;
  3. dans l'environnement GitHub `production`, secrets
     `PROD_SUPABASE_ACCESS_TOKEN` (jeton personnel Supabase),
     `PROD_SUPABASE_PROJECT_REF`, `PROD_SUPABASE_DB_PASSWORD`,
     `PROD_SUPABASE_URL`, `PROD_SUPABASE_ANON_KEY` (publique) ;
  4. Actions → **Supabase production** → Run workflow depuis `main`, case
     « apply » décochée (essai à blanc : vérifie la région, liste les
     migrations en attente), puis cochée pour les appliquer ;
  5. aucune donnée de test en production : les tests SQL et de contrat
     tournent sur Supabase local et sur le projet de développement.
- [x] **Identifiant Android définitif** (D6) — `com.eripoo.app`, décidé le
  2026-10-22 (le domaine `eripoo.com` doit appartenir au porteur ; à
  vérifier avant de créer l'application dans la Play Console, après quoi il
  ne change plus). Le paquet Kotlin interne reste `mg.eripoo.eripoo`.
- [ ] **Clé d'envoi Play** créée, gardée hors Git, sauvegardée hors ligne ;
  Play App Signing activé. Procédure (poste du porteur, Java installé) :
  1. `keytool -genkeypair -v -keystore eripoo-upload.jks -keyalg RSA
     -keysize 4096 -validity 10000 -alias upload` (noter les deux mots de
     passe ; garder le fichier et les mots de passe dans un coffre hors
     ligne : sans eux, plus aucune mise à jour ne peut être envoyée tant
     que Google n'a pas réinitialisé la clé d'envoi) ;
  2. GitHub → Settings → Environments → **New environment** `production`,
     avec **Required reviewers** (le porteur) ;
  3. dans cet environnement, secrets `PLAY_UPLOAD_KEYSTORE_BASE64`
     (`base64 -w0 eripoo-upload.jks`), `PLAY_UPLOAD_STORE_PASSWORD`,
     `PLAY_UPLOAD_KEY_ALIAS` (`upload`), `PLAY_UPLOAD_KEY_PASSWORD`,
     `RELEASE_ARCHIVE_PASSPHRASE` (phrase longue, gardée au coffre) ;
  4. Actions → **Release** → Run workflow, puis approuver ; télécharger
     `eripoo-release-encrypted` et le déchiffrer :
     `gpg -d eripoo-release.tar.gpg > release.tar && tar -xf release.tar`
     (bundle, empreinte SHA-256, symboles de débogage).
- [ ] **Relecture native du malagasy** (interface, contenu, localisations
  Material) et des textes fr/en par les auteurs.
- [ ] **Appareils A et B** : toute la section 4 ci-dessous.

## 2. Vérifié automatiquement par la CI

À chaque PR : format, analyse, tests, tests SQL, contrat RPC. Les jobs
Android (build, APK release, émulateurs) se lancent **à la demande**
(Actions → CI → Run workflow) pour économiser les minutes Actions : à
lancer au moins une fois avant toute release.

| Contrôle | Où |
|---|---|
| ✅ auto — Format, analyse statique, règles d'architecture (couleurs, chaînes, couches pures, pas de `print`, exceptions sans texte, données de test fictives) | job « Format, analyze, test » |
| ✅ auto — Aucun secret versionné, aucun SDK d'analytics, de crash ou d'IA | `source_rules_test.dart` |
| ✅ auto — Manifeste : permissions attendues, sauvegarde désactivée, clair refusé, une activité exportée, signature hors Git | `android_release_test.dart` |
| ✅ auto — APK release fusionnée : permissions dangereuses limitées à caméra et micro, `INTERNET` présent, `usesCleartextTraffic=false`, `allowBackup=false`, non `debuggable`, ≤ 40 Mio | `tool/check_apk.sh` (job émulateur) |
| ✅ auto — Démarrage et mémoire dans les budgets sur émulateurs Android 8 et 14 | `tool/android_cold_start.sh`, [PERFORMANCE.md](PERFORMANCE.md) |
| ✅ auto — Accessibilité : cibles ≥ 48 dp, cibles libellées, contraste, sur 13 écrans, clair/sombre, mg/fr ; aucun débordement à 200 % de texte | `test/accessibility/` |
| ✅ auto — Tests SQL (RLS, RPC, révocation, rotation, suppression de compte, quota) sur PostgreSQL et Supabase local ; contrat RPC client ↔ Supabase | jobs « Database tests », « Supabase local » |
| ✅ auto — Aucune donnée privée dans les journaux, erreurs, corps d'appels ni fichiers hors base chiffrée | `privacy_leak_test.dart` |
| ✅ auto — Pack de contenu construit depuis `content/`, validé, 100 % des faits réglementaires sourcés | `tool/content_build.dart --check` |

## 3. Construction de la release

- [ ] `pubspec.yaml` : `version` incrémentée (nom et code).
- [ ] Bundle construit par le workflow **Release**
  (`.github/workflows/release.yml`, chantier C-11) : obfusqué, symboles à
  part, signé avec la clé d'envoi (refusé s'il l'est avec la clé de
  debug), `tool/check_apk.sh` sur les APK arm64 et armv7 de même
  configuration, bundle et symboles chiffrés avant l'artefact (dépôt
  public). Sans `PROD_SUPABASE_URL`, la version est hors ligne (invité
  seulement) : la production n'est pas créée.
- [ ] Symboles de débogage archivés hors du dépôt (jamais publiés).
- [ ] `tool/check_apk.sh` sur les APK extraites du bundle (arm64, armv7) :
  tailles réelles notées dans PERFORMANCE.md.
- [ ] Licences : l'écran des licences liste libsodium, SQLite3MultipleCiphers,
  Roboto et les paquets (vérification visuelle) ; licence sqlite3mc relue
  par un juriste (§1).
- [ ] Fiche Play : déclaration de sécurité des données conforme à
  SECURITY.md (chiffré de bout en bout, aucun partage, suppression de
  compte dans l'app), classification, captures dans les trois langues.

## 4. Sur appareils A et B (NON VÉRIFIÉ à ce jour)

Procédure : [DEVICE_TESTS.md](DEVICE_TESTS.md). Résumé de ce qui doit être
prouvé avant release (liste complète : [END_CHECKLIST.md](END_CHECKLIST.md) §2) :

- [ ] démarrage, mémoire, Argon2id dans les budgets de PERFORMANCE.md ;
- [ ] parcours complet hors ligne, puis synchronisation ;
- [ ] transfert double QR, code de secours, révocation ;
- [ ] **rotation de clé** sur deux téléphones réels (l'autre téléphone
  prévenu, rouvert avec le nouveau code, photos relisibles) ;
- [ ] **se déconnecter et effacer**, **supprimer le compte** (contre le
  projet Supabase de développement) ;
- [ ] micro, lecture des réponses orales, partage du PDF ;
- [ ] TalkBack sur les écrans principaux, texte à 200 %, mode sombre en
  extérieur ;
- [ ] mise à jour depuis la version précédente installée (migrations de
  base locales sans perte).

## 5. Exploitation

- [ ] Sauvegardes de la base de production et procédure de restauration
  testée (le contenu est chiffré : la restauration ne donne accès à rien
  de lisible).
- [ ] Surveillance de la santé technique sans contenu (taux d'erreur des
  RPC, latence) — aucun outil choisi ; analytics de production non
  commencés (D7).
- [ ] Rotation des clés de service Supabase documentée ; aucun accès
  administrateur au contenu privé (rien à ouvrir : tout est chiffré).
- [ ] Back-office : activer GitHub Pages (Settings → Pages → Source :
  GitHub Actions), lancer Actions → **Back-office**, puis créer chaque
  compte du personnel (Supabase → Authentication → Add user) et lui
  donner un rôle dans l'éditeur SQL :
  `insert into authoring.staff_roles (user_id, role) values ('<uuid>', 'content_editor');`
  La première connexion demande d'enrôler l'application TOTP.
  Contenu : Settings → Actions → General → cocher « Allow GitHub Actions
  to create and approve pull requests », puis Actions → **Content sync**
  → `import` une fois ; ensuite `export` pour proposer les modifications
  du back-office en PR (lancer la CI à la main sur sa branche).
- [ ] Back-office (§44 : contenu, traductions, statistiques agrégées,
  santé) : **non construit** — décision du porteur (édition du contenu
  hors du dépôt, D5).
