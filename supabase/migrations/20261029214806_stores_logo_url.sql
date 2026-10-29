-- Logo propre à chaque magasin (sinon l'app affiche celui de la centrale).
alter table public.stores add column if not exists logo_url text
  constraint stores_logo_url_https check (logo_url is null or logo_url ~ '^https://');
grant update (logo_url) on public.stores to authenticated;
