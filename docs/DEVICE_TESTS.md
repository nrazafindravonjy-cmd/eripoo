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

Deux exécutions complètes : run 11 (4/5 tests, le test du verrou attendait
mal la vérification du PIN — corrigé) et **run 12 (5/5 tests réussis sur
les deux émulateurs)**. Valeurs du run 12, avec entre crochets celles du
run 11 quand elles diffèrent nettement : la variation entre deux runs
(jusqu'à ×1,7) vient des machines partagées de la CI.

| Mesure | Android 8.0 (API 26), « 1 Go » (1,5 Go réels), 2 cœurs | Android 14 (API 34), 2 Go (2,5 Go réels), 2 cœurs |
|---|---|---|
| Démarrage à froid, premier lancement | 917 ms [599] | 6 546 ms [5 570] |
| Démarrage à froid, médiane de 5 | 576 ms [458] | 4 018 ms [2 818] |
| Mémoire après démarrage (PSS) | 45 Mio | 69 Mio [74] |
| Après « Effacer les données » d'Android | 799 ms, pas de plantage | 3 750 ms, pas de plantage |
| Premier démarrage : clés + base chiffrée | 730 ms [540] | 1 092 ms [733] |
| Redémarrage : clés + ouverture de la base (médiane) | 23 ms [11] | 27 ms [12] |
| Mauvaise clé de base | refus explicite, fichier intact | idem |
| Clés perdues / base supprimée / effacement complet | `LocalKeysLost` / base vide / nouveau départ | idem |
| Argon2id 2 × 32 Mio (verrou PIN) | 73–131 ms [45–122] | 70–115 ms [44–93] |
| Argon2id 2 × 64 Mio | 145–155 ms [92–100] | 136–159 ms [90–98] |
| **Argon2id 3 × 64 Mio (code de récupération, proposé)** | **207–216 ms [129–132]** | **190–430 ms [124–130]** |
| Argon2id 4 × 64 Mio | 279–283 ms [177–183] | 248–255 ms [163–211] |
| Retard maximal de l'interface pendant Argon2id (isolat de fond) | ≤ 51 ms (1ᵉʳ calcul, démarrage de l'isolat), sinon ≤ 3 ms | ≤ 23 ms |
| Variation de mémoire pendant Argon2id 64 Mio | non mesurable (≤ 0 Mio : la mémoire de l'isolat est libérée avant la mesure) | idem |
| Pic mémoire du processus de test | 429 Mio | 479 Mio |
| Création de l'enveloppe de récupération / ouverture | 215 / 248 ms | 341 / 426 ms |
| 5 mauvais codes de récupération | 187–196 ms chacun, aucun raccourci | 203–484 ms chacun |
| 1 000 projets : écriture locale | 8,9 s [5,1] | 5,8 s [3,3] |
| 1 000 projets : hors ligne | tout conservé | idem |
| 1 000 projets : envoi avec coupure + reprise | 8,8 s [4,8], aucun doublon ni perte | 5,8 s [3,1], idem |
| Retard maximal de l'interface pendant la sync | 15 ms [22] | 26 ms [20] |
| Activation du PIN | 88 ms | 86 ms |
| Vérification du PIN, de l'appui à l'écran mis à jour | 278–409 ms | 278–352 ms |
| Mauvais PIN, bon PIN, reverrouillage au retour, redémarrage verrouillé | ✅ | ✅ |
| Biométrie disponible / verrouillage d'écran | non / non (émulateur sans empreinte) | non / non |

**Run 14 (code final, 5/5 tests sur les deux émulateurs)** confirme ces
ordres de grandeur (Android 8 / Android 14) : démarrage à froid médian
507 ms / 3 722 ms ; Argon2id 3 × 64 Mio 167–171 ms / 186–229 ms ;
redémarrage clés + base 17 ms / 16 ms. Il donne aussi la mesure corrigée
du gel : **Argon2id 3 × 64 Mio exécuté sur l'isolat principal bloque
l'interface 146 ms / 184 ms**, contre ≤ 4 ms quand il tourne en arrière-plan
comme dans l'app. (Dans les runs 11 et 12 cette mesure lisait 0 ms : défaut
de la mesure, corrigé.)

Pourquoi Android 14 démarre plus lentement : image `google_apis` plus lourde
et rendu graphique logiciel (swiftshader) sur le serveur ; ce n'est pas une
mesure d'Eripoo sur téléphone.

Défauts trouvés et corrigés grâce à ces émulateurs : voir
DEVELOPMENT_PLAN, section « Validation Phase 2 ».

## 2bis. Parcours « Ma quête » sur émulateurs (Phase 3)

Test `journey offline` de `integration_test/foundations_test.dart` : base
chiffrée réelle, pack de contenu lu dans l'APK, toute connexion réseau
interdite ; bienvenue → diagnostic (2 étapes) → projet nommé → première
étape du parcours → redémarrage (base refermée puis rouverte). CI run 23
(commit 7c97b55), **réussi sur les deux émulateurs**.

| Mesure | Android 8.0 (API 26), 1,5 Go réels | Android 14 (API 34), 2,5 Go réels |
|---|---|---|
| Lecture et vérification du pack de contenu | 16 ms | 15 ms |
| Calcul du plan (planificateur) | 9 ms | 7 ms |
| « Terminer l'étape » → écran suivant affiché (3 étapes) | 411 / 320 / 286 ms | 474 / 581 / 405 ms |
| Redémarrage → Accueil affiché, parcours repris | 351 ms | 691 ms |

Défaut trouvé et corrigé : sur Android 8, le premier passage (run 22)
vérifiait l'Accueil avant que la base chiffrée (isolat de fond) ait mis à
jour l'écran ; le test attend désormais l'écran (au plus 10 s). Pas de
défaut de l'application : sur Android 14, le même parcours passait déjà.
Deuxième défaut, **de l'application** (run 24, Android 8, intermittent) :
le message « Étape terminée » de l'étape précédente restait affiché sur
l'étape suivante ; clavier ouvert sur un écran de 320 × 640, il remontait
au-dessus du bouton « Suivant » et interceptait l'appui. Corrigé : le
message est retiré à l'ouverture d'une étape (vérifié par le test de
widget du parcours). Comme au §2, ces temps sont **indicatifs** (émulateur x86_64) ; sur
appareils A et B : **NON VÉRIFIÉ**.

## 3. Appareils de référence

| Cat. | Appareil | Android | RAM | Résultats |
|---|---|---|---|---|
| A | — | — | — | **NON VÉRIFIÉ** (aucun appareil disponible) |
| B | — | — | — | **NON VÉRIFIÉ** (aucun appareil disponible) |

Non testable sur émulateur, à faire sur A et B : biométrie réelle,
Keystore matériel, processeur ARM 32 bits (A), vrai 1 Go de RAM, autonomie,
lisibilité en extérieur, ANR sous charge.
