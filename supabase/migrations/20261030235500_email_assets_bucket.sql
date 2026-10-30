-- Bucket public pour les images des emails (logo). Lecture publique (URL), écriture réservée à l'équipe Vitriin.
insert into storage.buckets (id, name, public, allowed_mime_types, file_size_limit)
values ('email-assets', 'email-assets', true, array['image/png','image/jpeg'], 1048576)
on conflict (id) do nothing;
create policy email_assets_insert_platform_admin on storage.objects for insert to authenticated
  with check (bucket_id = 'email-assets' and public.is_platform_admin());
create policy email_assets_update_platform_admin on storage.objects for update to authenticated
  using (bucket_id = 'email-assets' and public.is_platform_admin()) with check (bucket_id = 'email-assets' and public.is_platform_admin());
create policy email_assets_select_platform_admin on storage.objects for select to authenticated
  using (bucket_id = 'email-assets' and public.is_platform_admin());
