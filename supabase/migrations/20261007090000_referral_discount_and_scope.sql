-- Q24: discount on the future subscription of a non-subscribed referrer (provisoire).
update public.app_config
   set value = '10',
       description = 'Discount (%) on the future subscription of a non-subscribed referrer (provisoire, Q24).',
       updated_at = now()
 where key = 'referral.non_subscriber_referrer_discount_pct';

-- Q25: France only for now; no country has sensitive fields disabled yet.
update public.country_config
   set note = 'Default. V1 targets France only; revisit the list of countries to restrict before opening elsewhere (Q25).'
 where country_code = '*';
