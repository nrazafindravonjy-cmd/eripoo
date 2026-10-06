# Eripoo — Tests et mesures sur Android

Fiche de mesures prévue par DEVELOPMENT_PLAN P7. Chaque valeur indique
**où** elle a été mesurée. Les émulateurs de la CI ne remplacent pas les
appareils de référence A et B : ils tournent sur le processeur x86_64 du
serveur GitHub (bien plus rapide qu'un téléphone ARM d'entrée de gamme),
avec un rendu graphique logiciel. Leurs temps sont **indicatifs** ; seuls
les comportements (passe / échoue, plantage ou non) sont probants.

## 1. Comment mesurer

Automatique, sur émulateur, à chaque pull request : job CI « Android
emulator » (`tool/ci_emulator_run.sh`).

Sur un vrai téléphone (USB, débogage activé), **données fictives
uniquement** — le test efface les données locales d'Eripoo :

```sh
flutter build apk --release
tool/android_cold_start.sh build/app/outputs/flutter-apk/app-release.apk
flutter test integration_test/foundations_test.dart -d <id de l'appareil>
```

Chaque mesure est une ligne `MEASURE <nom> <valeur>`. Ce que couvre le test
d'intégration (`integration_test/foundations_test.dart`) :

| Domaine | Vérifié |
|---|---|
| Stockage et clés | premier démarrage (clés + base chiffrée), 5 redémarrages, base illisible sans en-tête SQLite, mauvaise clé refusée sans toucher au fichier, clés perdues → `LocalKeysLost`, base supprimée → base vide, effacement complet → premier démarrage avec nouvel identifiant |
| Argon2id | 2×32, 2×64, 3×64, 4×64 Mio, 3 essais chacun, sur isolat de fond ; retard maximal de la boucle d'interface pendant le calcul ; mémoire ; même calcul sur l'isolat principal (pour montrer le gel évité) |
| Code de récupération | création + vérification de l'enveloppe, ouverture, 5 mauvais codes successifs |
| Synchronisation (serveur simulé dans l'app) | 1 000 projets écrits, hors ligne (rien perdu), coupure réseau pendant l'envoi puis reprise, aucun doublon ni perte, retard maximal de l'interface |
| Verrou | activation du PIN, mauvais PIN, bon PIN, verrouillage au retour d'arrière-plan, redémarrage verrouillé, disponibilité de la biométrie et du verrouillage d'écran |
| Démarrage (`android_cold_start.sh`, APK release) | premier lancement, 5 démarrages à froid, mémoire (PSS), app vivante, « Effacer les données » d'Android puis relance |

## 2. Résultats sur émulateurs (CI GitHub, APK release x86_64)

⚠️ L'émulateur « 1 Go » a été porté à **1,5 Go** par l'émulateur lui-même
(« Increasing RAM size to 1536MB », MemTotal 1,53 Go) : ce n'est **pas** un
test 1 Go. Le comportement sur 1 Go reste **NON VÉRIFIÉ**.

| Mesure | Android 8.0 (API 26), « 1 Go » (1,5 Go réels), 2 cœurs | Android 14 (API 34), 2 Go (2,5 Go réels), 2 cœurs |
|---|---|---|
| Démarrage à froid, premier lancement | 599 ms | 5 570 ms |
| Démarrage à froid, médiane de 5 | 458 ms (418–520) | 2 818 ms (2 135–3 040) |
| Mémoire après démarrage (PSS) | 45 Mio | 74 Mio |
| Après « Effacer les données » d'Android | 622 ms, pas de plantage | 2 306 ms, pas de plantage |
| Premier démarrage : clés + base chiffrée | 540 ms | 733 ms |
| Redémarrage : clés + ouverture de la base (médiane) | 11 ms | 12 ms |
| Mauvaise clé de base | refus explicite, fichier intact | idem |
| Argon2id 2 × 32 Mio | 45–122 ms | 44–93 ms |
| Argon2id 2 × 64 Mio | 92–100 ms | 90–98 ms |
| **Argon2id 3 × 64 Mio (proposé)** | **129–132 ms** | **124–130 ms** |
| Argon2id 4 × 64 Mio | 177–183 ms | 163–211 ms |
| Retard maximal de l'interface pendant Argon2id (isolat de fond) | ≤ 22 ms | ≤ 53 ms |
| Pic mémoire du processus (après Argon2id 64 Mio) | 431 Mio | 444 Mio |
| Création de l'enveloppe de récupération / ouverture | 141 / 133 ms | 137 / 126 ms |
| 5 mauvais codes de récupération | ~125 ms chacun, pas d'accélération | ~125–167 ms chacun |
| 1 000 projets : écriture locale | 5,1 s | 3,3 s |
| 1 000 projets : envoi avec coupure + reprise | 4,8 s, aucun doublon ni perte | 3,1 s, idem |
| Retard maximal de l'interface pendant la sync | 22 ms | 20 ms |
| Activation du PIN | 57 ms | 59 ms |
| Biométrie disponible / verrouillage d'écran | non / non (émulateur) | non / non |

Pourquoi Android 14 démarre plus lentement : image `google_apis` plus lourde
et rendu graphique logiciel (swiftshader) sur le serveur ; ce n'est pas une
mesure d'Eripoo sur téléphone.

Défauts trouvés et corrigés grâce à ces émulateurs : voir
DEVELOPMENT_PLAN, section « Validation Phase 2 ».

## 3. Appareils de référence

| Cat. | Appareil | Android | RAM | Résultats |
|---|---|---|---|---|
| A | — | — | — | **NON VÉRIFIÉ** (aucun appareil disponible) |
| B | — | — | — | **NON VÉRIFIÉ** (aucun appareil disponible) |

Non testable sur émulateur, à faire sur A et B : biométrie réelle,
Keystore matériel, processeur ARM 32 bits (A), vrai 1 Go de RAM, autonomie,
lisibilité en extérieur, ANR sous charge.
