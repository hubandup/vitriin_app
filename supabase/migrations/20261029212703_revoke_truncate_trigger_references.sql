-- TRUNCATE contourne la RLS : aucun rôle client ne doit l'avoir.
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;
alter default privileges in schema public revoke truncate, trigger, references on tables from anon, authenticated;
