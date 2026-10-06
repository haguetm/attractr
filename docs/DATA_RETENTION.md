# Durées de conservation

> **Brouillon à faire valider juridiquement** (analyse d'impact RGPD). Les durées marquées « proposé » sont des propositions techniques, pas des décisions.

| Donnée | Où | Durée | Statut |
|---|---|---|---|
| Profil, boissons, réponses écrites, photos | `profiles`, `profile_drinks`, `profile_prompts`, Storage | Tant que le compte existe ; effacement réel à la suppression (cascade + Storage) | Spec §12 |
| Champs sensibles chiffrés | `private.profile_sensitive` | Tant que le compte existe **et** que le consentement « données sensibles » est actif ; effacés au retrait du consentement | Spec §12 |
| Historique des boissons | `private.drink_change_history` | Durée du compte | Proposé |
| Consentements | `consents` | Durée du compte (preuve du consentement) ; effacés avec le compte | Proposé, à valider : une preuve après suppression peut être exigée |
| Journal des accès internes | `private.access_log` | 1 an, conservé après suppression du compte (identifiant seul) | Proposé |
| Compte mineur fermé | empreinte de visage (prestataire) + hash du téléphone | `compliance.minor_trace_retention_days` (365 j par défaut) pour empêcher la réinscription | DECISIONS Q22, à valider |
| Selfie de vérification | Storage `selfies` | Supprimé dès la vérification automatique, ou après la décision humaine s'il part en revue ; le résultat (âge estimé, confiance) est conservé avec la soumission | Proposé |
| Référence de visage | `private.face_templates` | Durée du compte (règle un visage = un compte) ; référence opaque du prestataire, jamais d'image | Proposé, biométrie : validation juridique requise |
| Photos envoyées à l'analyse IA | prestataire IA | Supprimées après analyse, sans entraînement | Spec §11 |
| Résultat d'analyse IA | `ai_analyses` | Cache d'une semaine ; effacé au retrait du consentement | Spec §11 (phase 10) |
| Messages | `messages` | Tant que le match existe ; effacés avec le compte de l'un ou l'autre (cascade). Durée après un match expiré ou annulé : proposé 12 mois pour les besoins de modération, à valider | Proposé |
| Likes et « passer » | `swipes` | Durée du compte ; les « passer » ne sont plus utilisés après `feed.pass_recycle_days` | Proposé |
| Notifications envoyées | `private.notification_outbox` | Proposé : 30 jours puis purge | Proposé |
| Jetons de notification | `push_tokens` | Supprimés à la déconnexion, quand Expo les déclare invalides, ou avec le compte | Proposé |
| Signalements | `reports` | Durée des deux comptes ; supprimés avec le compte du signalant ou du signalé (cascade). Proposé : conserver une trace anonymisée des sanctions, à valider | Proposé |
| File de modération | `private.moderation_queue` | Proposé : 12 mois après résolution | Proposé |
| Avertissements | `private.user_warnings` | Durée du compte | Proposé |

## Clé de chiffrement

La clé de `private.profile_sensitive` est créée dans Supabase Vault par la migration `20261005120300_profiles.sql` et n'apparaît jamais dans le dépôt. Rotation : créer une nouvelle clé, rechiffrer les lignes dans une migration dédiée, puis supprimer l'ancienne (procédure à écrire avant la production).
