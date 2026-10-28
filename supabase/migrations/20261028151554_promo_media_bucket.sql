-- Visuels des promotions. Bucket public en lecture : Meta doit pouvoir
-- télécharger l'image par son URL au moment de la publication.
-- Écriture réservée aux membres du magasin, dans le dossier <store_id>/.
-- JPEG uniquement : Instagram n'accepte que ce format. L'app convertit
-- l'image avant l'envoi.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('promo-media', 'promo-media', true, 8388608, array['image/jpeg'])
on conflict (id) do nothing;

create policy "promo_media_insert_store_member"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'promo-media'
  and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
  and public.is_store_member(((storage.foldername(name))[1])::uuid)
);

create policy "promo_media_delete_store_member"
on storage.objects for delete to authenticated
using (
  bucket_id = 'promo-media'
  and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
  and public.is_store_member(((storage.foldername(name))[1])::uuid)
);
