-- Une promo retirée par le magasin n'est plus visible publiquement.
drop policy if exists store_promotions_select_public on public.store_promotions;
create policy store_promotions_select_public on public.store_promotions
  for select using (status = 'active'::public.store_promotion_status and not hidden);
