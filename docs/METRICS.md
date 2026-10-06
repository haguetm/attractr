# Mesure et tableaux de suivi (phase 11)

Deux sources complémentaires :

| | Serveur (Supabase) | PostHog (UE) |
|---|---|---|
| Rôle | **Référence** pour la rétention et les chiffres clés | Parcours dans l'appli (entonnoirs, étapes d'inscription) |
| Données | Jours d'activité rattachés à un identifiant aléatoire, compteurs quotidiens | Liste fermée d'événements, sans texte libre |
| Désactivable | Non (statistiques internes, aucune donnée transmise) | Oui : Réglages > Mesure d'audience |
| Où le lire | `tools/dashboard/index.html` | Tableaux de bord PostHog |

## Définitions

- **Activation** : fin de l'inscription (le profil passe à « actif »). C'est le jour 0 de la cohorte.
- **Jour actif** : la personne a ouvert l'appli, consulté son feed, liké ou écrit ce jour-là (heure de Paris, `metrics.timezone`).
- **Rétention J1** : part de la cohorte active le lendemain de l'activation.
- **Rétention J7** : part active au moins une fois entre J7 et J13 (fenêtre `metrics.retention_window_days`, 7 jours, provisoire).
- **Rétention J30** : part active au moins une fois entre J30 et J36.
- Une cohorte n'a de valeur J7 / J30 qu'une fois sa fenêtre terminée (sinon « – »).
- **Les comptes supprimés restent comptés** dans leur cohorte (sinon la rétention serait gonflée). Ils ne sont plus rattachables à personne.
- **Exclus** : profils fictifs (seed) et profils techniques de couple.
- **Segments** : boisson principale au moment de l'activation (Vin, Café, Cocktail, Bière). Les cohortes de moins de 5 personnes sont masquées.
- **DAU / WAU / MAU** : personnes actives sur le jour, les 7 jours, les 30 jours. **DAU / MAU** = intensité d'usage.
- **Compteurs quotidiens** (figés chaque nuit pour la veille) : inscriptions, activations, likes, pass, matchs, premiers messages, messages, signalements, Premium actifs, boosts, suppressions.

## Confidentialité

- `private.metrics_links` est la seule table qui relie un compte à son identifiant de mesure ; elle est effacée avec le compte.
- `private.metrics_subjects` ne garde que le jour d'activation, la boisson principale et le jour de suppression ; `private.metrics_activity`, les jours actifs. Effacés après `metrics.raw_retention_days` (400 jours, provisoire).
- `private.metrics_daily` ne contient que des totaux.
- PostHog : identifiant aléatoire d'installation, puis `profiles.analytics_id` (aléatoire, différent de l'identifiant du compte). Pas de géolocalisation par IP (`$geoip_disable`), pas d'enregistrement d'écran, pas de capture automatique. Les événements et leurs propriétés autorisés sont dans `apps/mobile/src/lib/analyticsEvents.ts` (testés : aucune propriété de boisson, genre, orientation, âge, nom, lieu ou message).

## Tableau de bord serveur

1. Créer un jeton : `openssl rand -hex 32`, puis `supabase secrets set METRICS_DASHBOARD_TOKEN=<jeton>` (en local : dans `supabase/functions/.env`).
2. Déployer la fonction `metrics` (`npm run functions:deploy -- --project-ref <ref>`).
3. Ouvrir `tools/dashboard/index.html` dans un navigateur, saisir l'URL `https://<ref>.supabase.co/functions/v1/metrics` (en local `http://127.0.0.1:54321/functions/v1/metrics`) et le jeton. Le jeton reste dans l'onglet.
4. Bouton « Données de démo » : aperçu sans backend.

Les compteurs sont calculés par le job quotidien (`private.run_scheduled_jobs`). Pour recalculer un jour à la main (éditeur SQL) : `select private.snapshot_daily_metrics('2026-11-02');`. Rétention brute : `select * from private.metrics_retention('2026-10-01', '2026-12-31', 'week');`.

## PostHog : à configurer dans le projet (UE)

Réglages du projet : **Discard client IP data** activé, session replay et autocapture désactivés, conservation des données à 13 mois.

Événements : `app_opened`, `onboarding_step_completed` (`step`), `onboarding_completed`, `feed_viewed`, `like_sent` (`target`, `matched`), `pass_sent`, `message_sent` (`kind`), `premium_viewed`, `purchase_started` (`product`), `invitation_shared` (`kind`), `outing_created`, `ai_analysis_run`, `report_sent`.

Tableaux conseillés :
- **Rétention** (insight Retention) : événement de départ `onboarding_completed`, retour `app_opened`, par semaine. À comparer au tableau serveur (qui fait foi : PostHog ne voit pas les personnes ayant désactivé la mesure).
- **Entonnoir d'inscription** : `onboarding_step_completed` découpé par `step`, puis `onboarding_completed`.
- **Entonnoir de conversation** : `like_sent` → `like_sent` avec `matched = true` → `message_sent` (`kind = match`).
- **Monétisation** : `premium_viewed` → `purchase_started` (les achats confirmés viennent de RevenueCat).
- **Viralité** : `invitation_shared` par `kind`.
