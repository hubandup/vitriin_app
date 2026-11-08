-- MOD-078 : validation par QR par défaut.
-- Une promo sans validation choisie (promos de la centrale, promos créées avant MOD-076) et sans code EAN
-- est désormais validée par le vendeur : le client voit le QR (code vendeur en secours, 'check' = 'vendor').
-- Inchangé : la centrale garde la main ('required' impose, 'off' interdit) ; une promo avec code EAN sans
-- choix explicite reste validée par la caisse, sauf réglage code vendeur existant ; les choix explicites
-- du magasin (qr, pin, ean, none) sont respectés.
-- Retour arrière : recréer la fonction telle que dans 20261108190000_promo_validation.sql.
create or replace function public.promo_pin_required(p_sp_id uuid) returns boolean
language sql stable security definer set search_path to '' as $$
  select case coalesce(n.settings->>'pin_mode', 'optional')
      when 'required' then true
      when 'off' then false
      else case when p.validation is not null then p.validation in ('qr', 'pin')
                else p.ean_code is null or p.pin_required or s.pin_scope = 'all'
                     or (s.pin_scope = 'per_promo' and sp.pin_required) end
    end
  from public.store_promotions sp
  join public.promotions p on p.id = sp.promotion_id
  join public.stores s on s.id = sp.store_id
  left join public.networks n on n.id = s.network_id
  where sp.id = p_sp_id;
$$;
revoke all on function public.promo_pin_required(uuid) from public, anon, authenticated;
