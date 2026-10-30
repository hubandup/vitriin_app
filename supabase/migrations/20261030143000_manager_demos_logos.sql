-- Logos des enseignes de démo (fichiers servis par app.vitriin.co/demo/).
alter table public.demo_sectors add column if not exists logo_url text;
update public.demo_sectors set logo_url = 'https://app.vitriin.co/demo/flamme-foyer.svg' where key = 'cheminees';
update public.demo_sectors set logo_url = 'https://app.vitriin.co/demo/jardins-saisons.svg' where key = 'jardinerie';
update public.networks n set logo_url = d.logo_url
from public.demo_sectors d where n.is_demo and n.demo_sector = d.key and d.generated and d.logo_url is not null;

do $do$
declare d text;
begin
  d := pg_get_functiondef('public.manager_build_demo(text)'::regprocedure);
  d := replace(d, '  for i in 0 .. jsonb_array_length(cities) - 1 loop',
    E'  update public.networks set logo_url = sec.logo_url where id = v_net;\n\n  for i in 0 .. jsonb_array_length(cities) - 1 loop');
  execute d;
end
$do$;
