-- Démo : un compte Instagram est rattaché à sa Page Facebook (contrainte social_accounts_instagram_needs_parent).
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.manager_build_demo(text)'::regprocedure);
  d := replace(d, '(store_id, channel, external_account_id, display_name, status, connected_at, last_error)',
                  '(store_id, channel, external_account_id, parent_external_id, display_name, status, connected_at, last_error)');
  d := replace(d, $q$values (v_store, 'instagram', 'demo-ig-' || v_store,$q$,
                  $q$values (v_store, 'instagram', 'demo-ig-' || v_store, 'demo-fb-' || v_store,$q$);
  execute d;
end
$do$;
