-- =============================================================================
-- Vitriin — Mode démo (29 octobre 2026)
-- =============================================================================
-- Pour montrer le flux complet Centrale -> App magasin -> Facebook/Instagram
-- avant que la publication réelle soit ouverte (examen Meta en cours).
--
--   1. networks.is_demo : seuls les réseaux marqués démo acceptent les
--      publications simulées. Un vrai réseau ne peut jamais en recevoir.
--   2. promotions.details : le détail chiffré d'une promo (prix d'origine,
--      valeur, X+Y, condition), utilisé par l'app pour afficher le prix barré.
--   3. demo_publish / demo_reconnect / demo_tick : RPC appelées par l'app
--      magasin de démo. Elles écrivent dans publications exactement comme le
--      ferait meta-publish, sans jamais appeler Meta : external_post_id reste
--      NULL et metrics porte "demo": true.
-- =============================================================================

alter table public.networks
  add column is_demo boolean not null default false;

comment on column public.networks.is_demo is
  'Réseau de démonstration : publications simulées autorisées (demo_publish). '
  'Jamais vrai pour un client.';

alter table public.promotions
  add column details jsonb;

comment on column public.promotions.details is
  'Détail chiffré facultatif : {orig, val, xy:[x,y], sub}. Le texte affiché '
  'reste mechanic ; details sert au prix barré dans l''app magasin.';


-- Le magasin appartient-il à un réseau de démo ?
create or replace function public.is_demo_store(p_store_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select n.is_demo
    from public.stores s
    join public.networks n on n.id = s.network_id
    where s.id = p_store_id
  ), false);
$$;


-- Garde commune : membre du magasin ET magasin de démo.
create or replace function public.demo_guard(p_store_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_store_member(p_store_id) then
    raise exception 'Action réservée aux membres du magasin.'
      using errcode = 'insufficient_privilege';
  end if;
  if not public.is_demo_store(p_store_id) then
    raise exception 'Publication simulée réservée aux réseaux de démonstration.'
      using errcode = 'insufficient_privilege';
  end if;
end;
$$;


-- Publication simulée.
--   p_at NULL ou passé : publiée maintenant (Instagram échoue si le compte
--   Instagram du magasin n'est pas actif, comme en vrai).
--   p_at futur : programmée (publication pending datée).
-- L'activation passe à active, comme lorsqu'un magasin publie.
create or replace function public.demo_publish(
  p_store_promotion_id uuid,
  p_channels           text[],
  p_at                 timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_store_id uuid;
  v_ch       text;
  v_ok       boolean;
  v_future   boolean := p_at is not null and p_at > now();
begin
  select sp.store_id into v_store_id
  from public.store_promotions sp where sp.id = p_store_promotion_id;
  if v_store_id is null then
    raise exception 'Activation introuvable.' using errcode = 'no_data_found';
  end if;
  perform public.demo_guard(v_store_id);

  update public.store_promotions
  set status = 'active'
  where id = p_store_promotion_id and status <> 'active';

  foreach v_ch in array p_channels loop
    if v_ch not in ('facebook', 'instagram') then continue; end if;

    v_ok := exists (
      select 1 from public.social_accounts a
      where a.store_id = v_store_id and a.channel = v_ch::public.publication_channel
        and a.status = 'active'
    );

    insert into public.publications
      (store_promotion_id, channel, status, error_message, published_at, metrics, metrics_fetched_at)
    values (
      p_store_promotion_id,
      v_ch::public.publication_channel,
      case when v_future then 'pending'::public.publication_status
           when v_ok then 'published'::public.publication_status
           else 'failed'::public.publication_status end,
      case when not v_future and not v_ok then 'Compte déconnecté : reconnectez-le.' end,
      coalesce(p_at, now()),
      jsonb_build_object(
        'demo', true, 'live', true,
        'target_reach', 300 + floor(random() * 700)::int,
        'target_views', 600 + floor(random() * 900)::int,
        'target_reactions', 15 + floor(random() * 40)::int,
        'target_comments', floor(random() * 8)::int,
        'reach', 0, 'views', 0, 'reactions', 0, 'comments', 0
      ),
      now()
    )
    on conflict (store_promotion_id, channel) do update
      set status = excluded.status,
          error_message = excluded.error_message,
          published_at = excluded.published_at,
          metrics = excluded.metrics,
          metrics_fetched_at = excluded.metrics_fetched_at;
  end loop;
end;
$$;


-- Reconnexion simulée d'un compte : le compte repasse actif et les
-- publications en échec sur ce canal sont republiées.
create or replace function public.demo_reconnect(p_store_id uuid, p_channel text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  perform public.demo_guard(p_store_id);

  update public.social_accounts
  set status = 'active', last_error = null, last_error_at = null, last_checked_at = now()
  where store_id = p_store_id and channel = p_channel::public.publication_channel;

  update public.publications p
  set status = 'published', error_message = null, published_at = now()
  from public.store_promotions sp
  where sp.id = p.store_promotion_id and sp.store_id = p_store_id
    and p.channel = p_channel::public.publication_channel and p.status = 'failed';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;


-- Fait avancer la démo : les publications programmées dont l'heure est passée
-- sont publiées, et les statistiques des publications simulées montent sur
-- 24 heures jusqu'à leur valeur cible.
create or replace function public.demo_tick(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.demo_guard(p_store_id);

  update public.publications p
  set status = 'published', published_at = p.published_at
  from public.store_promotions sp
  where sp.id = p.store_promotion_id and sp.store_id = p_store_id
    and p.status = 'pending' and p.published_at <= now();

  update public.publications p
  set metrics = p.metrics || jsonb_build_object(
        'reach',     round((p.metrics->>'target_reach')::numeric     * least(1, extract(epoch from now() - p.published_at) / 86400)),
        'views',     round((p.metrics->>'target_views')::numeric     * least(1, extract(epoch from now() - p.published_at) / 86400)),
        'reactions', round((p.metrics->>'target_reactions')::numeric * least(1, extract(epoch from now() - p.published_at) / 86400)),
        'comments',  round((p.metrics->>'target_comments')::numeric  * least(1, extract(epoch from now() - p.published_at) / 86400))
      ),
      metrics_fetched_at = now()
  from public.store_promotions sp
  where sp.id = p.store_promotion_id and sp.store_id = p_store_id
    and p.status = 'published' and (p.metrics->>'live')::boolean is true;
end;
$$;


revoke execute on function public.is_demo_store(uuid)                     from public;
revoke execute on function public.demo_guard(uuid)                        from public;
revoke execute on function public.demo_publish(uuid, text[], timestamptz) from public;
revoke execute on function public.demo_reconnect(uuid, text)              from public;
revoke execute on function public.demo_tick(uuid)                         from public;

grant execute on function public.is_demo_store(uuid)                      to authenticated;
grant execute on function public.demo_publish(uuid, text[], timestamptz)  to authenticated;
grant execute on function public.demo_reconnect(uuid, text)               to authenticated;
grant execute on function public.demo_tick(uuid)                          to authenticated;
