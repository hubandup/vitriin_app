-- =============================================================================
-- Vitriin — Policies d'auteur de promotions sur les colonnes (29 octobre 2026)
-- =============================================================================
-- Bug : les policies passaient par can_write_promotion(id), qui relit la table.
-- Une ligne tout juste insérée n'y est pas encore visible : INSERT ... RETURNING
-- échouait (« new row violates row-level security policy ») pour toute promo
-- hors de la policy publique (brouillon, à venir). Cas réel : création d'une
-- promo depuis l'Espace Centrale.
-- Correction : tester les colonnes de la ligne elle-même.
-- Retour arrière : voir docs/JOURNAL.md (entrée du 29/10, BUG-001).
-- =============================================================================

drop policy promotions_select_authors on public.promotions;
drop policy promotions_update_authors on public.promotions;
drop policy promotions_delete_authors on public.promotions;

create policy promotions_select_authors on public.promotions
  for select to authenticated
  using (
    (created_by_store_id is not null and public.is_store_member(created_by_store_id))
    or (created_by_network_id is not null and public.is_network_member(created_by_network_id))
  );

create policy promotions_update_authors on public.promotions
  for update to authenticated
  using (
    (created_by_store_id is not null and public.is_store_member(created_by_store_id))
    or (created_by_network_id is not null and public.is_network_member(created_by_network_id))
  )
  with check (
    (created_by_store_id is not null and public.is_store_member(created_by_store_id))
    or (created_by_network_id is not null and public.is_network_member(created_by_network_id))
  );

create policy promotions_delete_authors on public.promotions
  for delete to authenticated
  using (
    (created_by_store_id is not null and public.is_store_member(created_by_store_id))
    or (created_by_network_id is not null and public.is_network_member(created_by_network_id))
  );

-- Plus utilisée nulle part.
drop function public.can_write_promotion(uuid);
