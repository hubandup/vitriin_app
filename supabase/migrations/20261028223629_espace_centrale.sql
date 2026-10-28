-- =============================================================================
-- Vitriin — Espace Centrale (28 octobre 2026)
-- =============================================================================
-- Ce qu'il manquait pour qu'une centrale pilote ses magasins :
--   1. le contenu d'une promo réseau (type, code de caisse) et le logo réseau ;
--   2. le rattachement d'un magasin à un réseau par code (lien d'invitation) ;
--   3. l'envoi d'une promo de la centrale vers ses magasins ;
--   4. la lecture, par le magasin, des promos réseau qu'il a reçues ;
--   5. un dossier de visuels pour la centrale dans le bucket promo-media.
--
-- Règle Meta, tenue ici et pas seulement dans l'écran : la centrale n'appelle
-- jamais Meta. Elle crée des store_promotions ; seule meta-publish, appelée
-- avec le JWT d'un MEMBRE DU MAGASIN, publie. Rien dans cette migration ne
-- donne à un membre de réseau l'accès à un jeton ou à meta-publish.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Contenu
-- -----------------------------------------------------------------------------

-- Les 6 types de promotion V1 de la charte.
alter table public.promotions
  add column promo_type    text,
  add column discount_code text;

alter table public.promotions
  add constraint promotions_promo_type_check check (
    promo_type is null or promo_type in (
      'percent',            -- Pourcentage (-30 %)
      'amount',             -- Montant (-20 €)
      'new_price',          -- Nouveau prix
      'x_plus_y',           -- 2+1 offert
      'cashback',           -- Cashback fidélité
      'free_with_condition' -- Gratuit sous condition
    )
  ),
  add constraint promotions_discount_code_format check (
    discount_code is null or discount_code ~ '^[A-Z0-9-]{3,24}$'
  );

comment on column public.promotions.discount_code is
  'Code de réduction en caisse. Pour une promo réseau, fourni par la centrale. '
  'Pas de code produit.';

alter table public.networks add column logo_url text;

grant update (logo_url) on public.networks to authenticated;


-- -----------------------------------------------------------------------------
-- 2. Rattachement d'un magasin à un réseau
-- -----------------------------------------------------------------------------

-- Le magasin (son propriétaire) saisit le code, ou ouvre le lien d'invitation
-- qui le contient. Un magasin appartient à un seul réseau : s'il en a déjà un,
-- on refuse plutôt que de le déplacer en silence.
create or replace function public.join_network(p_code text, p_store_id uuid)
returns table (network_id uuid, network_name text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user_id uuid := (select auth.uid());
  v_network public.networks;
  v_current uuid;
begin
  if v_user_id is null then
    raise exception 'Authentification requise.'
      using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.store_members sm
    where sm.store_id = p_store_id and sm.user_id = v_user_id and sm.role = 'owner'
  ) then
    raise exception 'Seul le propriétaire du magasin peut le rattacher à un réseau.'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_network
  from public.networks n
  where n.join_code = upper(trim(p_code));

  if v_network.id is null then
    raise exception 'Code réseau inconnu. Vérifiez-le auprès de votre centrale.'
      using errcode = 'no_data_found';
  end if;

  select s.network_id into v_current from public.stores s where s.id = p_store_id;

  if v_current is not null and v_current <> v_network.id then
    raise exception 'Ce magasin appartient déjà à un autre réseau.'
      using errcode = 'unique_violation';
  end if;

  update public.stores set network_id = v_network.id where id = p_store_id;

  return query select v_network.id, v_network.name;
end;
$$;

-- La centrale retire un magasin de son réseau. Les activations passées restent
-- (historique) ; le magasin ne reçoit plus rien.
create or replace function public.remove_store_from_network(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_network_id uuid;
begin
  select s.network_id into v_network_id from public.stores s where s.id = p_store_id;

  if v_network_id is null or not public.is_network_admin(v_network_id) then
    raise exception 'Action réservée à la centrale du magasin.'
      using errcode = 'insufficient_privilege';
  end if;

  update public.stores set network_id = null where id = p_store_id;
end;
$$;

-- Nouveau code si l'ancien a trop circulé. Les magasins déjà rattachés restent.
create or replace function public.regenerate_join_code(p_network_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
begin
  if not public.is_network_admin(p_network_id) then
    raise exception 'Action réservée aux administrateurs du réseau.'
      using errcode = 'insufficient_privilege';
  end if;

  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  update public.networks set join_code = v_code where id = p_network_id;
  return v_code;
end;
$$;


-- Le magasin voit le nom de son réseau, sans accéder à la table networks
-- (qui porte le code d'invitation, réservé à la centrale).
create or replace function public.get_store_network(p_store_id uuid)
returns table (network_id uuid, network_name text, logo_url text)
language sql
stable
security definer
set search_path = ''
as $$
  select n.id, n.name, n.logo_url
  from public.stores s
  join public.networks n on n.id = s.network_id
  where s.id = p_store_id
    and public.is_store_member(p_store_id);
$$;


-- -----------------------------------------------------------------------------
-- 3. Envoi Centrale → Magasins
-- -----------------------------------------------------------------------------

-- Crée une activation par magasin ciblé. p_store_ids NULL = tout le réseau.
-- Les magasins hors réseau sont ignorés, les doublons aussi (renvoi possible
-- à de nouveaux magasins). Le trigger apply_mandatory_status fixe le statut :
-- pending, ou active si la promo est obligatoire. Dans les deux cas, AUCUNE
-- publication n'est créée ici : le magasin publie lui-même.
create or replace function public.send_promotion(
  p_promotion_id uuid,
  p_store_ids    uuid[] default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_network_id uuid;
  v_count      integer;
begin
  select p.created_by_network_id into v_network_id
  from public.promotions p where p.id = p_promotion_id;

  if v_network_id is null then
    raise exception 'Promotion introuvable ou non créée par une centrale.'
      using errcode = 'no_data_found';
  end if;

  if not public.is_network_admin(v_network_id) then
    raise exception 'Action réservée aux administrateurs du réseau.'
      using errcode = 'insufficient_privilege';
  end if;

  insert into public.store_promotions (promotion_id, store_id)
  select p_promotion_id, s.id
  from public.stores s
  where s.network_id = v_network_id
    and (p_store_ids is null or s.id = any (p_store_ids))
  on conflict (promotion_id, store_id) do nothing;

  get diagnostics v_count = row_count;

  update public.promotions
  set status = 'active'
  where id = p_promotion_id and status in ('draft', 'scheduled');

  return v_count;
end;
$$;


-- -----------------------------------------------------------------------------
-- 4. Le magasin lit les promos réseau qu'il a reçues
-- -----------------------------------------------------------------------------
-- Sans ça, il ne voit une promo réseau qu'une fois active ET dans ses dates
-- (policy publique), donc jamais une promo à venir à valider.

create or replace function public.is_promotion_recipient(p_promotion_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.store_promotions sp
    join public.store_members sm on sm.store_id = sp.store_id
    where sp.promotion_id = p_promotion_id
      and sm.user_id = (select auth.uid())
  );
$$;

create policy promotions_select_recipients on public.promotions
  for select to authenticated
  using (public.is_promotion_recipient(id));


-- -----------------------------------------------------------------------------
-- 5. Visuels de la centrale : promo-media/n/<network_id>/…
-- -----------------------------------------------------------------------------

create policy "promo_media_insert_network_member"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'promo-media'
  and (storage.foldername(name))[1] = 'n'
  and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
  and public.is_network_member(((storage.foldername(name))[2])::uuid)
);

create policy "promo_media_delete_network_member"
on storage.objects for delete to authenticated
using (
  bucket_id = 'promo-media'
  and (storage.foldername(name))[1] = 'n'
  and (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
  and public.is_network_member(((storage.foldername(name))[2])::uuid)
);


-- -----------------------------------------------------------------------------
-- 6. Droits d'exécution
-- -----------------------------------------------------------------------------
-- EXECUTE est accordé à PUBLIC par défaut : on révoque, puis on ouvre à
-- authenticated seulement.

revoke execute on function public.join_network(text, uuid)            from public;
revoke execute on function public.remove_store_from_network(uuid)     from public;
revoke execute on function public.regenerate_join_code(uuid)          from public;
revoke execute on function public.send_promotion(uuid, uuid[])        from public;
revoke execute on function public.is_promotion_recipient(uuid)        from public;
revoke execute on function public.get_store_network(uuid)             from public;

grant execute on function public.join_network(text, uuid)             to authenticated;
grant execute on function public.remove_store_from_network(uuid)      to authenticated;
grant execute on function public.regenerate_join_code(uuid)           to authenticated;
grant execute on function public.send_promotion(uuid, uuid[])         to authenticated;
grant execute on function public.is_promotion_recipient(uuid)         to authenticated;
grant execute on function public.get_store_network(uuid)              to authenticated;
