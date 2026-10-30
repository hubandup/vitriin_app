-- Emails du support : chaque message n'est notifié qu'une fois (support-notify le marque).
alter table public.support_messages add column if not exists notified_at timestamptz;
-- Les messages déjà présents ne déclenchent pas d'email.
update public.support_messages set notified_at = created_at where notified_at is null;
