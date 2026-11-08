-- Storage files must be removed through the Storage API before deleting the identity.
create or replace function public.my_account_file_batch(p_owner uuid)
returns setof text language sql stable security invoker set search_path = ''
as $$
  select name from storage.objects where p_owner = auth.uid()
    and bucket_id = 'apex-progress' and split_part(name, '/', 1) = p_owner::text
  order by name limit 100
$$;

-- Other authenticated operations cannot rewrite this append-only log.
create or replace function public.prevent_coach_audit_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  if TG_OP='DELETE' and auth.uid()::text = current_setting('fitr.erasing_owner',true)
     and (old.actor_user_id=auth.uid() or exists (
       select from public.coach_relationships r where r.id=old.relationship_id
       and auth.uid() in (r.coach_user_id,r.client_user_id))) then return old; end if;
  raise exception 'coach audit facts are append only' using errcode='42501';
end;
$$;

create or replace function public.delete_my_account(p_owner uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare account_email text;
begin
  if p_owner is null or auth.uid() is distinct from p_owner then
    raise exception 'Sign in to the account being deleted' using errcode='42501';
  end if;
  select email into account_email from auth.users where id = p_owner for update;
  if not found then return; end if;
  if exists(select from storage.objects where bucket_id='apex-progress'
      and split_part(name,'/',1)=p_owner::text) then
    raise exception 'Files remain. Retry account deletion.';
  end if;

  -- Retain the other client's performed workout facts when its coach departs.
  update public.program_days set coach_plan_version_id = null
    where coach_plan_version_id in (select v.id from public.coach_plan_versions v
      join public.coach_relationships r on r.id = v.relationship_id
      where p_owner in (r.client_user_id,r.coach_user_id));
  perform set_config('fitr.erasing_owner',p_owner::text,true);
  delete from public.coach_audit_log a where a.actor_user_id=p_owner or exists
    (select from public.coach_relationships r where r.id=a.relationship_id and p_owner in (r.client_user_id,r.coach_user_id));
  delete from public.coach_plan_installations i using public.coach_relationships r
    where r.id=i.relationship_id and p_owner in (r.client_user_id,r.coach_user_id);
  delete from public.coach_plan_acknowledgements a using public.coach_relationships r
    where r.id=a.relationship_id and p_owner in (r.client_user_id,r.coach_user_id);
  delete from public.coach_plan_versions v using public.coach_relationships r
    where r.id=v.relationship_id and p_owner in (r.client_user_id,r.coach_user_id);
  delete from public.coach_relationships where p_owner in (client_user_id,coach_user_id);
  delete from public.coach_invitations where accepted_by=p_owner or lower(invitee_email)=lower(account_email);
  delete from public.meal_preset_items where user_id=p_owner;
  delete from auth.users where id=p_owner;
end;
$$;
revoke all on function public.my_account_file_batch(uuid), public.delete_my_account(uuid) from public, anon;
grant execute on function public.my_account_file_batch(uuid), public.delete_my_account(uuid) to authenticated;
