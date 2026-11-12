-- Installed builds retry any refusal without a 22/23/42 SQLSTATE forever and hold back the rest of
-- their outbox. These two functions are replayed from that outbox, so their bad-input refusals
-- get a code every build files away. The sign-in refusal keeps P0001: waiting is right there.
do $$
declare
  definition text;
  pair text[];
begin
  select pg_get_functiondef(p.oid) into strict definition from pg_proc p
    where p.oid = 'public.record_fitness_brain_shadow_observation(date,text,integer,integer,text,text,text,text,text,jsonb,text[],text[])'::regprocedure;
  definition := replace(definition, $a$raise exception 'An owned profile is required';$a$, $a$raise exception 'An owned profile is required' using errcode = '22023';$a$);
  execute definition;

  select pg_get_functiondef(p.oid) into strict definition from pg_proc p
    where p.oid = 'public.record_user_fitness_evidence(text,double precision,text,timestamptz,text,text,text,text,jsonb,uuid)'::regprocedure;
  foreach pair slice 1 in array array[
    array['This evidence source requires a trusted ingestion path', '22023'],
    array['An idempotency key is required', '22023'],
    array['Evidence metadata must be a JSON object', '22023'],
    array['The idempotency key is already associated with different evidence', '23505']
  ] loop
    definition := replace(definition, format('raise exception %L;', pair[1]), format('raise exception %L using errcode = %L;', pair[1], pair[2]));
  end loop;
  execute definition;
end $$;
notify pgrst, 'reload schema';
