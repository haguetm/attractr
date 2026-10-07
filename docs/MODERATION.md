# Modération — guide de l'équipe

En V1, la modération se fait depuis l'éditeur SQL de Supabase (Studio), avec des fonctions dédiées. Chaque fonction prend en premier argument le **nom du modérateur** (ex. `'moderateur:camille'`) et écrit dans le journal des accès (`private.access_log`). Un back-office web viendra plus tard.

> Règle : ne jamais lire ni modifier les tables directement. Toujours passer par les fonctions ci-dessous.

## 1. Voir la file

```sql
select * from private.mod_queue('moderateur:camille');
```

Priorité 1 = urgent (suspicion de mineur), à traiter en premier. Colonnes utiles : `kind`, `reason`, `subject_user_id` (compte concerné), `ref_id` (élément à examiner).

| kind | reason possibles | Ce qu'il faut examiner |
|---|---|---|
| `selfie_review` | `possible_minor`, `duplicate_face`, `age_mismatch`, `incomplete_result` (réponse du prestataire incomplète) | Le selfie (bucket `selfies`, chemin dans `private.selfie_submissions`) et l'âge déclaré |
| `photo_review` | `nudity`, `violence` | La photo (`public.photos`, `ref_id` = id de la photo) |
| `report` | motif du signalement | Le signalement (`public.reports`, `ref_id` = id) et, si besoin, la conversation |
| `message_review` | `money_request` | Le message (`public.messages`, `ref_id` = id) |

## 2. Décider

### Selfie
```sql
select private.mod_resolve_selfie('moderateur:camille', <id>, 'verified'); -- vrai visage, majeur
select private.mod_resolve_selfie('moderateur:camille', <id>, 'retake');   -- selfie inexploitable : en reprendre un
select private.mod_resolve_selfie('moderateur:camille', <id>, 'minor');    -- personne mineure
```
`minor` ferme le compte, programme l'effacement des données (fonction `process-deletions`) et conserve uniquement le hash du téléphone et la référence de visage pendant `compliance.minor_trace_retention_days` jours pour empêcher la réinscription. Le selfie est supprimé après chaque décision.

### Photo
```sql
select private.mod_resolve_photo('moderateur:camille', <id>, 'approved');
select private.mod_resolve_photo('moderateur:camille', <id>, 'rejected');
```

### Signalement
```sql
select private.mod_resolve_report('moderateur:camille', <id>, 'validated');
select private.mod_resolve_report('moderateur:camille', <id>, 'dismissed');
```
Effets d'un signalement validé :
- **Intention trompeuse** : avertissement au 3ᵉ signalement validé (de personnes différentes), suspension au 4ᵉ (`moderation.misleading_*_threshold`).
- **Suspicion de mineur** : fermeture du compte comme pour `minor` ci-dessus.
- **Arnaque, harcèlement, faux profil, pression d'un couple** : suspension.
- **Photo inappropriée, autre** : aucune sanction automatique ; agir sur la photo ou suspendre à la main si nécessaire.

La personne concernée reçoit une notification générique (« Information sur ton compte »).

### Message (demande d'argent)
```sql
select private.mod_resolve_message('moderateur:camille', <id>, 'ok');    -- faux positif
select private.mod_resolve_message('moderateur:camille', <id>, 'scam');  -- suspension de l'expéditeur
```

## 3. Consulter des données sensibles

Uniquement si c'est nécessaire au traitement d'un dossier :
```sql
select private.admin_read_sensitive('moderateur:camille', '<user_id>', 'signalement #42 : intention trompeuse');
```
La raison est obligatoire et journalisée.

## 4. Lever une suspension

Pas de fonction dédiée en V1 :
```sql
select private.log_access('moderateur:camille', '<user_id>', 'account', 'levée de suspension : <raison>');
update public.profiles set status = 'active' where id = '<user_id>' and status = 'suspended';
```

## Réglages utiles (`app_config`)

`verification.*` (seuils d'âge et de confiance), `moderation.photo_*_score`, `moderation.misleading_*_threshold`, `reports.daily_limit`, `chat.scam_check_first_messages`, `contacts.block_cooldown_hours`. En développement : `providers.mock_selfie_outcome` et `providers.mock_photo_outcome` pour simuler chaque cas. En bêta (`APP_ENV=beta`), chaque selfie et chaque photo part en revue humaine, quel que soit ce réglage.
