# Paiements — configuration RevenueCat

Premium et les Boosts passent par RevenueCat (spec §10). Le serveur ne fait confiance qu'au **webhook** : l'appli ne décide jamais seule qu'un compte est Premium.

## Produits (App Store Connect et Google Play Console)

| Identifiant | Type | Prix (provisoire) |
|---|---|---|
| `premium_monthly` | Abonnement auto-renouvelable | 7,99 € / mois |
| `premium_yearly` | Abonnement auto-renouvelable | 49,99 € / an |
| `boost_single` | Consommable | 2 € |

Le même prix partout : pas de prix différencié par âge, sexe ou pays.

## RevenueCat

1. **Entitlement** : `premium` (relié aux deux abonnements). Identifiant aussi dans `app_config` → `revenuecat.entitlement`.
2. **Offerings** : `premium` (courant, avec les deux abonnements) et `boosts` (avec `boost_single`).
3. **App User ID** : l'appli appelle `Purchases.configure({ appUserID: <id du profil> })`, donc les événements arrivent avec l'identifiant Attractr.
4. **Webhook** : URL `https://<ref>.supabase.co/functions/v1/revenuecat-webhook`, en-tête *Authorization* = la valeur du secret `REVENUECAT_WEBHOOK_SECRET` (`supabase secrets set REVENUECAT_WEBHOOK_SECRET=...`).
5. **Clés publiques SDK** de l'appli : `EXPO_PUBLIC_REVENUECAT_IOS_KEY` et `EXPO_PUBLIC_REVENUECAT_ANDROID_KEY` (`apps/mobile/.env`). Sans clés, les achats sont désactivés (Expo Go, développement).

## Parrainage (à valider avec les règles des stores)

| Récompense | Où | Comment |
|---|---|---|
| Filleul : 1 mois offert (parrain abonné) | `private.entitlements` source `referral` | Accordé immédiatement côté serveur |
| Parrain abonné : 1 mois offert par filleul (6/an) | `private.referral_rewards` + `private.offer_code_pool` | Code d'offre store attribué automatiquement (option B), à utiliser au prochain renouvellement |
| Filleul : -50 % sur le 1er paiement (parrain non abonné) | `referral_rewards` kind `discount` | Offre promotionnelle store `revenuecat.referee_offer`, à afficher dans l'appli |
| Parrain non abonné : -10 % (ou 20 %, à décider) sur son abonnement | `referral_rewards` kind `discount` | Offre promotionnelle store `revenuecat.referrer_offer` |

Les offres promotionnelles (identifiants dans `app_config`) se créent dans App Store Connect (*Promotional Offers* / *Offer Codes*) et Google Play (*Offers*), puis se branchent dans RevenueCat. L'appli affiche déjà la réduction disponible ; l'achat avec l'offre est à brancher une fois les offres créées.

## Tester sans store

En développement, Réglages > Outils de développement, ou l'écran Premium : « Activer Premium (test, 30 jours) » et « Ajouter un Boost (test) » (fonction `dev-impersonate`, mêmes verrous que « tester en tant que »).

## Codes d'offre (parrainage, option B)

1. Générer des codes « 1 mois gratuit » : App Store Connect (*Abonnements > Codes d'offre*) et Google Play Console (*Monétiser > Codes promo*).
2. Les charger depuis l'éditeur SQL :
   ```sql
   select private.load_offer_codes('staff:camille', 'APP_STORE', array['CODE1', 'CODE2'], '2027-01-31');
   select private.load_offer_codes('staff:camille', 'PLAY_STORE', array['CODE3']);
   ```
3. Le job horaire les attribue aux parrains (store connu grâce aux événements RevenueCat). Surveiller le stock : `select store, count(*) from private.offer_code_pool where assigned_at is null group by store;`
