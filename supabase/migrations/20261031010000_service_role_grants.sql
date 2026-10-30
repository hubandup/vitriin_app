-- BUG-008 : les fonctions serveur (clé service_role) n'avaient pas les droits sur ces tables.
-- service_role contourne la RLS mais pas les GRANT : on donne le strict nécessaire, colonne par colonne
-- pour les mises à jour. Ni anon ni authenticated ne sont concernés.

-- support-notify
grant select on public.support_tickets to service_role;
grant select on public.support_messages to service_role;
grant update (notified_at) on public.support_messages to service_role;

-- manager-invite, network-stores-invite, support-notify
grant select on public.stores, public.networks, public.platform_admins to service_role;
grant update (contact_email, invited_at) on public.stores to service_role;
grant insert on public.store_members to service_role;
-- upsert PostgREST : ON CONFLICT DO UPDATE réécrit toutes les colonnes envoyées.
grant update (network_id, user_id, role) on public.network_members to service_role;
