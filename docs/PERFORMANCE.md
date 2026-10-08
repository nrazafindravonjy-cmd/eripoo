# Eripoo — Budgets de performance

Cible (CLAUDE.md §31) : téléphones Android d'entrée de gamme. Les valeurs
ci-dessous sont des **budgets** : un dépassement est un défaut à corriger,
pas une mesure à commenter. Les mesures de référence se font sur les
appareils A et B ([DEVICE_TESTS.md](DEVICE_TESTS.md)) ; **ils ne sont pas
encore disponibles**, donc aucun budget n'est encore vérifié sur un vrai
téléphone (NON VÉRIFIÉ).

## 1. Budgets et où ils sont vérifiés

| Budget | Valeur | Vérifié par | État |
|---|---|---|---|
| Taille de l'APK release, une architecture | ≤ 40 Mio | CI, `tool/check_apk.sh` (x86_64) à chaque PR | ✅ automatique — mesuré **31,1 Mo** (x86_64, 2026-10-08) |
| Démarrage à froid, médiane de 5 — appareil A | ≤ 2,5 s | appareil A | NON VÉRIFIÉ |
| Démarrage à froid — émulateur Android 8 (CI) | ≤ 2,5 s | CI, `tool/android_cold_start.sh` | ✅ automatique (mesuré ≈ 0,5–0,9 s) |
| Démarrage à froid — émulateur Android 14 (CI, rendu logiciel) | ≤ 12 s | CI | ✅ automatique (mesuré ≈ 3,7–6,5 s) |
| Mémoire après démarrage (PSS) | ≤ 150 Mio (Android 8), ≤ 200 Mio (Android 14) | CI | ✅ automatique (mesuré 45 / 69–74 Mio) |
| Ouverture des clés + base chiffrée au redémarrage | ≤ 100 ms | intégration sur émulateur (DEVICE_TESTS §2) | mesuré 11–27 ms, non bloquant en CI |
| Argon2id du code de récupération (3 × 64 Mio) | ≤ 3 s sur A, toujours hors du fil de l'interface | émulateurs ; appareil A | émulateurs 0,13–0,43 s ; A NON VÉRIFIÉ |
| Retard maximal de l'interface pendant Argon2id ou la synchronisation | ≤ 60 ms | intégration sur émulateur | mesuré ≤ 51 ms (1ᵉʳ calcul), sinon ≤ 26 ms |
| Chiffrement d'un fichier ≥ 1 Mio | hors du fil de l'interface | code (`MediaStore.backgroundThreshold`) et tests | ✅ |
| Photo enregistrée | ≤ 1 600 px de côté (≈ 300 Ko) | code et tests | ✅ |
| Réponse orale | 3 min au plus, AAC 32 kbit/s (≈ 750 Ko) | code et tests | ✅ |
| 5 000 éléments : écriture, synchronisation par lots, reprise | sans perte, sans doublon, interface fluide | `test/sync/volume_test.dart` | ✅ (mesures dans DEVICE_TESTS) |

Les marges sur émulateur sont larges exprès : les machines partagées de
la CI varient jusqu'à × 1,7 d'un run à l'autre. Ces seuils attrapent une
régression grossière (un démarrage qui double), pas une lenteur fine.

## 2. Distribution

- Publier un **Android App Bundle** (`flutter build appbundle`) : Google
  Play ne livre à chaque téléphone que son architecture et sa densité.
- Construire avec `--obfuscate --split-debug-info=<dossier hors Git>` ;
  garder les symboles pour lire les traces d'erreur (jamais publiés).
- R8 (réduction du code Java/Kotlin) est actif par défaut en release.

## 3. Ce qui reste à mesurer sur appareils

Voir [END_CHECKLIST.md](END_CHECKLIST.md) §2 : démarrage, mémoire,
Argon2id sur A (1 Go de RAM réel), défilement des listes longues,
taille réelle des APK arm64 et armv7, consommation de données d'une
synchronisation, autonomie.
