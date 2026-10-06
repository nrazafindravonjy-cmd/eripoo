# Eripoo — Offline-first et synchronisation

Objectif : l'application fonctionne entièrement sans réseau pour le parcours,
le projet, les missions, la progression, les observations, les interviews, les
hypothèses, les expériences, les documents et les réglages ; la
synchronisation est automatique, idempotente et **ne perd jamais de données
silencieusement**.

Statut : conception. Rien de ce document n'est encore implémenté (Phase 2
pour le socle local et l'outbox, Phase 5 pour le moteur complet).

---

## 1. Principes

1. **Drift est la source de vérité de l'UI.** Le réseau ne bloque jamais une
   action utilisateur.
2. **Toute écriture produit une opération d'outbox dans la même
   transaction** que la donnée (repositories uniquement).
3. **Le serveur ne fusionne pas** (il ne peut pas lire les payloads chiffrés)
   ; il fait du *compare-and-swap* et garantit l'ordre. La fusion est faite
   côté client, de façon déterministe.
4. **Idempotence partout** : chaque opération a un `op_id` ; la rejouer
   produit le même résultat.
5. **Aucune perte silencieuse** : toute valeur écartée par une fusion est
   conservée dans `sync_conflicts` et consultable par l'utilisateur.

## 2. Horloges : HLC par champ

Les téléphones d'entrée de gamme ont souvent une date système fausse. Les
horodatages bruts ne sont donc pas fiables pour ordonner les écritures.

- Chaque appareil maintient une **horloge logique hybride** (HLC) :
  `(millis physiques, compteur, device_id)`, comparée lexicographiquement.
  À chaque écriture locale : `hlc = max(hlc, maintenant) + tick`. À chaque
  réception : `hlc = max(hlc, hlc_reçue) + tick`.
- Chaque champ modifiable d'une entité porte sa HLC (`field_clocks`).
- Garde-fou contre une horloge très en avance : une HLC distante dont la
  partie physique dépasse de plus de 24 h le `server_updated_at` de
  l'enregistrement est ramenée à cette date pour la comparaison, et
  l'anomalie est journalisée (sans contenu).
- Implémentation maison (~80 lignes, testée) : aucun paquet nécessaire.

## 3. Protocole

### 3.1 Push

```
client ──► rpc sync_push(ops[])     (≤ 50 ops ou ≤ 256 Ko par lot)
op = { op_id, id, expected_server_version | null, deleted,
       key_version, schema_version, payload (chiffré) }
```

Côté serveur, dans **une transaction** :

1. `pg_advisory_xact_lock(hash(auth.uid()))` — sérialise les écritures d'un
   même utilisateur.
2. Pour chaque op :
   - si `(owner, op_id)` existe dans `sync_applied_ops` ⇒ renvoyer le
     résultat enregistré (rejeu idempotent) ;
   - si l'enregistrement existe et appartient à un autre propriétaire ⇒
     `rejected` ;
   - si `server_version ≠ expected_server_version` ⇒ `conflict` + version
     courante (payload chiffré) ;
   - sinon upsert avec `server_version = nextval(seq)` ⇒ `applied`.
3. Validation serveur : taille maximale du payload, `schema_version` et
   `key_version` connus, quota par utilisateur, débit.

Pourquoi le verrou : avec une séquence globale, une transaction qui prend
la valeur 101 peut être validée avant une autre qui a pris 100 ; un client
qui aurait déjà lu 101 sauterait 100. En sérialisant par utilisateur (et
chaque utilisateur ne tire que ses propres lignes), le curseur
`server_version` est **sans trou** pour chaque utilisateur.

### 3.2 Pull

```
client ──► rpc sync_pull(since_server_version, limit=200)
       ◄── lignes owner = auth.uid() avec server_version > since, triées
```

Le client applique chaque page **dans une transaction Drift qui met aussi à
jour le curseur** : une interruption n'avance jamais le curseur sans les
données.

### 3.3 Ordre d'un cycle

1. Pousser l'outbox (lots), traiter les résultats.
2. Tirer jusqu'à épuisement.
3. Pour chaque `conflict` du push : fusionner (§4) puis réenfiler.
4. Envoyer les médias en attente (§6).
5. Mettre à jour `sync_state` et l'indicateur d'état dans l'UI.

Un seul cycle à la fois (verrou en mémoire + drapeau `in_flight` persistant).

## 4. Résolution des conflits

Le cas typique : un téléphone et une tablette (ou un téléphone réinstallé)
modifient le même élément hors ligne.

### 4.1 Stratégie par famille d'entités

| Famille | Entités | Stratégie |
|---|---|---|
| **Éditables** | `projects`, `project_sections`, `hypotheses` (brouillon), `experiments` (avant verrouillage), `observations`, `interviews`, `competitors`, `finance_items`, `price_scenarios`, `user_profile`, `answers` | Fusion **à trois voies par champ** (§4.2). |
| **Append-only** | `project_revisions`, `decisions`, `evidences`, `results`, `conclusions`, `badges_earned`, `consents_local` | Pas de conflit possible : identifiants uniques, jamais modifiées ; seules les suppressions logiques sont autorisées. |
| **Monotones** | `step_progress`, `mission_instances`, `tool_unlocks`, `facts` d'origine `rule` | Fusion par treillis : le statut le plus avancé gagne (`locked < available < in_progress < completed`), `started_at = min`, `completed_at = max`, ensembles unis. `abandoned` / `deferred` ne l'emportent que s'ils sont plus récents (HLC). |
| **Champs verrouillés** | `experiments.success_criterion` après `criterion_locked_at`, hypothèses testées | Immuables : une divergence crée un conflit visible, jamais d'écrasement. |

### 4.2 Fusion à trois voies par champ

Pour chaque champ `f`, avec `B` = horloge au dernier état synchronisé
(`synced_clocks`), `L` = local, `R` = distant :

| Cas | Résultat |
|---|---|
| seul `L[f] > B[f]` | valeur locale |
| seul `R[f] > B[f]` | valeur distante |
| les deux ont changé, valeurs identiques | aucune action |
| les deux ont changé, valeurs différentes | la HLC la plus grande gagne ; **la valeur perdante est enregistrée dans `sync_conflicts`** et signalée (« Une autre version de ce texte existe — voir ») |

Le résultat fusionné reçoit de nouvelles horloges et repart en push avec
`expected_server_version` = version distante. La fusion est une fonction
pure (`merge(base, local, remote) → (merged, conflicts)`), testée de façon
exhaustive, y compris par tests de propriétés (commutativité des cas sans
conflit, idempotence).

### 4.3 Suppressions

- Suppression = tombstone (`deleted_at` + HLC de suppression) ; jamais de
  suppression physique tant que le serveur ne l'a pas confirmée.
- Suppression concurrente d'une modification :
  - si la modification est **postérieure** (HLC) à la suppression ⇒
    l'élément est restauré (l'utilisateur a agi après) ;
  - sinon la suppression l'emporte et la version modifiée est placée dans
    « Éléments récupérables » (30 jours) ;
  - dans les deux cas, rien n'est perdu sans trace.
- Suppression d'un projet : cascade logique sur ses entités (chacune reçoit
  sa tombstone, ce qui garde la sync simple).
- Côté serveur, les tombstones sont conservées (payload vidé) ; elles pèsent
  quelques dizaines d'octets.

### 4.4 Interface des conflits

Badge discret sur l'élément concerné ; écran « Versions » listant la valeur
actuelle et la ou les valeurs alternatives, avec « Garder celle-ci » ou
« Copier dans le texte ». Aucune boîte de dialogue bloquante pendant la
sync.

## 5. Déclenchement, réessais, erreurs

**Déclencheurs** : démarrage, retour au premier plan, changement de
connectivité (`connectivity_plus` sert seulement de signal ; une requête
légère confirme la joignabilité), après écriture locale (anti-rebond 5 s),
toutes les 5 min au premier plan, et en arrière-plan via WorkManager
(contrainte « réseau disponible », Phase 5).

**Réessais** : backoff exponentiel avec gigue (5 s, 15 s, 1 min, 5 min,
15 min, plafond 1 h), par opération (`attempts`, `next_attempt_at`).

| Classe d'erreur | Exemples | Traitement |
|---|---|---|
| Transitoire | pas de réseau, timeout, 5xx, 429 | réessai avec backoff |
| Authentification | 401 / jeton expiré | rafraîchir la session puis réessayer ; si impossible, sync suspendue + invitation à se reconnecter ; données locales intactes |
| Permanente | 400 validation, payload trop gros, quota | opération marquée en échec, **donnée conservée localement**, visible dans « Problèmes de synchronisation », rapport d'erreur sans contenu |
| Version future | `schema_version` inconnu reçu | payload conservé brut, non écrasé, invitation à mettre à jour |

**Reprise après fermeture** : au démarrage, toutes les opérations
`in_flight` repassent `pending` ; le rejeu est sûr grâce à `op_id`.

## 6. Médias (photos, audio)

- Capture et stockage locaux immédiats (fonctionne offline), fichier chiffré
  par une clé propre, par segments de 64 Ko (mémoire constante, même sur
  1 Go de RAM).
- L'entité `media` (métadonnées) se synchronise comme les autres ; le
  fichier part ensuite via `media_upload_queue`, par défaut **en Wi-Fi
  uniquement** (réglable), chemin déterministe `user-media/{uid}/{media_id}`
  (upsert idempotent).
- Sur un autre appareil, le média apparaît « pas encore téléchargé » et
  n'est récupéré qu'à l'ouverture (ou en Wi-Fi).
- Quota par utilisateur et durée maximale d'enregistrement (valeurs à
  définir, risque de coût R9).

## 7. Invité, compte et appareils

### 7.1 Invité → compte

1. Hors compte, tout est écrit localement avec `owner_id = local:<uuid>` ;
   l'outbox s'accumule (statut `local_only`, pas d'envoi).
2. À l'inscription : génération de la clé de chiffrement si absente, envoi
   de la clé enveloppée (`user_keys`), puis **dans une transaction locale**
   réattribution `owner_id → auth.uid()` et passage de l'outbox en `pending`.
3. Push normal. Aucune donnée locale n'est supprimée.
4. ⚠️ Si l'utilisateur se connecte à un **compte existant** qui contient
   déjà un projet : les deux jeux de données sont conservés (deux projets
   distincts), l'utilisateur choisit ensuite lequel est actif. Jamais de
   fusion automatique de deux projets.

### 7.2 Nouvel appareil

Connexion ⇒ récupération de la clé enveloppée ⇒ déverrouillage par code de
récupération **ou** transfert par QR depuis un appareil déjà connecté ⇒ pull
complet. Tant que la clé n'est pas déverrouillée, rien n'est déchiffré ni
écrit.

### 7.3 Déconnexion

Si l'outbox n'est pas vide : avertissement explicite (« X éléments ne sont
pas encore sauvegardés ») avec possibilité d'attendre la sync. Les données
locales sont ensuite effacées de l'appareil (appareils partagés), après
confirmation.

## 8. Contenu pédagogique

Distinct de la sync utilisateur : manifeste distant comparé au local,
téléchargement des packs modifiés, vérification `sha256`, installation
atomique, ancienne version conservée en cas d'échec
([PRODUCT_ARCHITECTURE §6.3](PRODUCT_ARCHITECTURE.md#63-mise-à-jour-du-contenu-sur-lappareil)).

## 9. Indicateur d'état

États visibles (icône discrète + texte accessible) : « Enregistré sur
l'appareil », « Synchronisation… », « Tout est sauvegardé », « Hors ligne —
tes données sont en sécurité sur l'appareil », « Action requise ». Jamais de
message alarmant pour un simple mode hors ligne.

## 10. Plan de tests de la sync

Faux serveur en mémoire implémentant la même interface que le client RPC
(doublure de test explicitement documentée), avec injection de fautes ; puis
les mêmes scénarios contre Supabase local en CI.

| # | Scénario | Attendu |
|---|---|---|
| 1 | Utilisateur offline pendant N jours, 500 écritures | tout fonctionne ; outbox cohérente |
| 2 | Retour online | outbox vidée, curseur à jour, état « sauvegardé » |
| 3 | Conflit (2 appareils, même champ) | HLC la plus grande gagne, perdante dans `sync_conflicts` |
| 3b | Conflit sur champs différents | fusion sans conflit |
| 4 | Suppression locale vs modification distante | règles §4.3, aucune perte |
| 5 | Coupure réseau au milieu d'un push / d'un pull | rejeu idempotent, curseur jamais en avance |
| 6 | Fermeture de l'app pendant la sync | reprise propre au démarrage |
| 7 | Réponse dupliquée / rejeu d'un lot | aucun doublon |
| 8 | Horloge de l'appareil fausse (± 2 ans) | ordre correct, garde-fou §2 |
| 9 | Invité → compte avec 3 mois de données | tout migré, rien supprimé |
| 10 | `schema_version` futur reçu | payload conservé, non écrasé |
| 11 | Appareil lent (1 Go RAM) avec 5 000 enregistrements | sync complète sans gel de l'UI (isolat) |
