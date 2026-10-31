-- MOD-052 : fiche publique du magasin (vitrine particulier).
-- Les coordonnées du gérant (contact_*) restent privées ; le magasin renseigne à part ce que ses clients voient.
alter table public.stores
  add column if not exists description text check (description is null or length(description) <= 800),
  add column if not exists cover_url text check (cover_url is null or cover_url ~ '^https://'),
  add column if not exists public_phone text check (public_phone is null or public_phone ~ '^[0-9 +().-]{6,25}$'),
  add column if not exists public_email text check (public_email is null or public_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');

create or replace function public.vitrine_store_json(p_store_id uuid)
returns jsonb language sql stable security definer set search_path to '' as $$
  select jsonb_build_object('id', s.id, 'slug', s.slug, 'name', s.name, 'address', s.address,
    'city', s.city, 'postal_code', s.postal_code, 'lat', s.lat, 'lng', s.lng, 'category', s.category,
    'logo_url', s.logo_url, 'website', s.website, 'network', n.name, 'network_logo', n.logo_url,
    'description', s.description, 'cover_url', s.cover_url, 'phone', s.public_phone, 'email', s.public_email,
    'demo', coalesce(n.is_demo, false))
  from public.stores s left join public.networks n on n.id = s.network_id where s.id = p_store_id;
$$;

-- Le gérant (policy de mise à jour des magasins inchangée) peut modifier ces champs.
grant update (description, cover_url, public_phone, public_email) on public.stores to authenticated;
