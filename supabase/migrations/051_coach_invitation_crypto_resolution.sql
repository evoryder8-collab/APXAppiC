-- Keep the SECURITY DEFINER search path restricted. Resolve pgcrypto explicitly
-- in all three invitation RPCs without changing their grants or business rules.
do $repair$
declare
  target regprocedure;
  definition text;
begin
  if to_regprocedure('extensions.gen_random_bytes(integer)') is null
     or to_regprocedure('extensions.digest(text,text)') is null then
    raise exception 'Required pgcrypto functions are missing from extensions';
  end if;
  foreach target in array array[
    'public.coach_create_invitation(text,text[],boolean)'::regprocedure,
    'public.coach_preview_invitation(text)'::regprocedure,
    'public.coach_accept_invitation(text,text[],boolean)'::regprocedure
  ] loop
    definition := pg_get_functiondef(target);
    definition := replace(definition, 'encode(gen_random_bytes(', 'encode(extensions.gen_random_bytes(');
    definition := replace(definition, 'encode(digest(', 'encode(extensions.digest(');
    execute definition;
  end loop;
end;
$repair$;

notify pgrst, 'reload schema';
