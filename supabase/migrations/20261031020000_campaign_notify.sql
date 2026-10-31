-- Email « Nouvelle campagne » aux magasins : chaque envoi aux magasins n'est notifié qu'une fois.
alter table public.store_promotions add column if not exists notified_at timestamptz;
-- Les campagnes déjà envoyées ne déclenchent pas d'email.
update public.store_promotions set notified_at = created_at where notified_at is null;

-- Réserve les magasins à prévenir pour une campagne et renvoie leurs gérants.
-- Appelée uniquement par la fonction campaign-notify (service_role), après vérification de l'appelant.
-- Fenêtre d'une heure : rappeler la fonction ne renvoie rien, et un vieil envoi ne repart pas.
create or replace function public.campaign_notify_claim(p_promotion_id uuid)
returns table (sp_id uuid, status text, store_name text, emails text[])
language sql security definer set search_path to '' as $$
  with claimed as (
    update public.store_promotions sp set notified_at = now()
    where sp.promotion_id = p_promotion_id and sp.notified_at is null
      and sp.created_at > now() - interval '1 hour' and not sp.hidden and not sp.suspended
    returning sp.id, sp.status::text, sp.store_id
  )
  select c.id, c.status, s.name,
    array(select u.email::text from public.store_members m join auth.users u on u.id = m.user_id
          where m.store_id = c.store_id and u.email is not null
            and (u.banned_until is null or u.banned_until < now()) order by u.email limit 5)
  from claimed c join public.stores s on s.id = c.store_id;
$$;
revoke all on function public.campaign_notify_claim(uuid) from public, anon, authenticated;
grant execute on function public.campaign_notify_claim(uuid) to service_role;

-- Libère les magasins si l'envoi a échoué (nouvel essai possible).
create or replace function public.campaign_notify_release(p_ids uuid[])
returns void language sql security definer set search_path to '' as $$
  update public.store_promotions set notified_at = null where id = any (p_ids);
$$;
revoke all on function public.campaign_notify_release(uuid[]) from public, anon, authenticated;
grant execute on function public.campaign_notify_release(uuid[]) to service_role;
