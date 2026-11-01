-- MOD-066 : aperçu commerçant. Le vrai code de la promo, sans enregistrer d'affichage,
-- réservé aux membres du magasin, de sa centrale, ou à l'équipe Vitriin.
create or replace function public.vitrine_preview_code(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v record;
begin
  select p.discount_code, p.ean_code, s.id store_id, s.network_id into v
  from public.store_promotions sp
  join public.promotions p on p.id = sp.promotion_id
  join public.stores s on s.id = sp.store_id
  where sp.id = p_id;
  if not found then raise exception 'Promo introuvable.'; end if;
  if not (public.is_store_member(v.store_id) or (v.network_id is not null and public.is_network_member(v.network_id)) or public.is_platform_admin()) then
    raise exception 'Accès réservé au commerce.';
  end if;
  return jsonb_build_object('code', v.discount_code, 'ean', v.ean_code);
end;
$$;
revoke all on function public.vitrine_preview_code(uuid) from public, anon;
grant execute on function public.vitrine_preview_code(uuid) to authenticated;
