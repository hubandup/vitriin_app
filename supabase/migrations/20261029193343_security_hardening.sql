-- =============================================================================
-- Vitriin — Durcissement sécurité (29 octobre 2026) · docs/JOURNAL.md SEC-001
-- =============================================================================

-- 1. Colonnes modifiables par les utilisateurs : seulement ce que l'app modifie.
revoke insert, update on public.store_promotions from authenticated;
grant insert (promotion_id, store_id) on public.store_promotions to authenticated;
grant update (status) on public.store_promotions to authenticated;

revoke insert, update on public.promotions from authenticated;
grant insert (created_by_store_id, created_by_network_id, title, description, mechanic, media_url,
              starts_at, ends_at, is_mandatory, status, promo_type, discount_code, details)
  on public.promotions to authenticated;
grant update (title, description, mechanic, media_url, starts_at, ends_at, is_mandatory, status,
              promo_type, discount_code, details)
  on public.promotions to authenticated;

revoke update on public.store_members from authenticated;
grant update (role) on public.store_members to authenticated;
revoke update on public.network_members from authenticated;
grant update (role) on public.network_members to authenticated;

-- 2. Un magasin ne s'abonne qu'à ses propres promos ou à celles de son réseau
--    (avant : n'importe quelle promo dont il connaissait l'identifiant).
drop policy store_promotions_insert_members on public.store_promotions;
create policy store_promotions_insert_members on public.store_promotions
  for insert to authenticated
  with check (
    public.is_store_member(store_id)
    and exists (
      select 1 from public.promotions p
      join public.stores s on s.id = store_id
      where p.id = promotion_id
        and (p.created_by_store_id = s.id
             or (p.created_by_network_id is not null and p.created_by_network_id = s.network_id))
    )
  );

-- 3. Fonctions : rien d'appelable sans connexion, triggers non appelables.
revoke execute on function public.apply_mandatory_status()          from public, anon, authenticated;
revoke execute on function public.guard_mandatory_decline()         from public, anon, authenticated;
revoke execute on function public.handle_new_user()                 from public, anon, authenticated;
revoke execute on function public.rls_auto_enable()                 from public, anon, authenticated;
revoke execute on function public.set_updated_at()                  from public, anon, authenticated;
revoke execute on function public.is_network_admin(uuid)            from public, anon;
revoke execute on function public.is_network_member(uuid)           from public, anon;
revoke execute on function public.is_promotion_mandatory(uuid)      from public, anon;
revoke execute on function public.is_store_member(uuid)             from public, anon;
revoke execute on function public.is_store_network_member(uuid)     from public, anon;
revoke execute on function public.is_store_owner(uuid)              from public, anon;
grant  execute on function public.is_network_admin(uuid)            to authenticated;
grant  execute on function public.is_network_member(uuid)           to authenticated;
grant  execute on function public.is_promotion_mandatory(uuid)      to authenticated;
grant  execute on function public.is_store_member(uuid)             to authenticated;
grant  execute on function public.is_store_network_member(uuid)     to authenticated;
grant  execute on function public.is_store_owner(uuid)              to authenticated;

-- Les fonctions créées à l'avenir ne sont plus exécutables par défaut :
-- chaque migration doit accorder explicitement EXECUTE à authenticated.
alter default privileges in schema public revoke execute on functions from public, anon;

-- 4. search_path figé (avertissement Supabase).
alter function public.set_updated_at() set search_path = '';
