-- Lab Members security hardening migration
-- Run this once, AFTER FULL_DATABASE_SETUP.sql and supabase_friend_requests_rebuild.sql.
-- It is safe to run again after future deployments.

begin;

-- Never grant database access to unauthenticated clients. RLS alone is not a
-- substitute for revoking broad table and function privileges.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all tables in schema public from public;
revoke all on all sequences in schema public from public;
revoke all on all functions in schema public from public;

grant usage on schema public to authenticated, anon;

-- Keep ordinary client access narrowly scoped; RLS remains the final check.
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update, delete on public.friend_requests to authenticated;
grant select, insert, delete on public.admin_message_blocks to authenticated;
grant select, insert, update on public.user_identities to authenticated;
grant select on public.admin_broadcasts to authenticated;
grant select on public.admin_user_moderation to authenticated;
grant select on public.admin_roles to authenticated;
grant select, insert, update on public.user_known_devices to authenticated;
grant select, insert on public.user_login_logs to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Regrant only RPCs used by the web app. SECURITY DEFINER admin functions
-- still enforce public.assert_admin_caller() before changing data.
do $$
declare
  signature text;
begin
  foreach signature in array array[
    'public.is_admin_caller()',
    'public.get_chat_messages(uuid,integer)',
    'public.get_inbox_contacts()',
    'public.admin_get_dashboard_stats()',
    'public.admin_get_all_users()',
    'public.admin_set_user_ban(uuid,boolean,text)',
    'public.admin_update_user_profile(uuid,text,integer,text)',
    'public.admin_create_broadcast(text,text,text)',
    'public.admin_purge_all_messages()',
    'public.admin_set_user_admin(uuid,boolean)',
    'public.admin_delete_user(uuid)',
    'public.register_device_and_check_is_new(text,text,text,text,text,text)',
    'public.friend_assert_current_email(text)',
    'public.get_friend_relation_for_email(text,uuid)',
    'public.get_friend_relations_for_email(text,uuid[])',
    'public.send_friend_request_for_email(text,uuid)',
    'public.cancel_friend_request_for_email(text,uuid)',
    'public.respond_friend_request_for_email(text,uuid,text)',
    'public.get_pending_friend_requests_for_email(text)',
    'public.get_inbox_contacts_for_email(text)',
    'public.get_chat_messages_for_email(text,uuid,integer)',
    'public.mark_messages_as_read(text,uuid)',
    'public.get_profiles_by_ids(uuid[])'
  ] loop
    if to_regprocedure(signature) is not null then
      execute format('grant execute on function %s to authenticated', signature);
    end if;
  end loop;
end;
$$;

-- The role must come from the protected admin_roles table, never user_metadata.
alter table public.admin_roles enable row level security;
drop policy if exists admin_roles_read on public.admin_roles;
create policy admin_roles_read on public.admin_roles for select to authenticated
  using (auth.uid() = user_id or public.is_admin_caller());
drop policy if exists admin_roles_modify on public.admin_roles;
create policy admin_roles_modify on public.admin_roles for all to authenticated
  using (public.is_admin_caller())
  with check (public.is_admin_caller());

-- Identity e-mails and moderation data are private except to their owner/admin.
alter table public.user_identities enable row level security;
drop policy if exists user_identities_all on public.user_identities;
drop policy if exists user_identities_select_authenticated on public.user_identities;
drop policy if exists user_identities_policy on public.user_identities;
create policy user_identities_read_own_or_admin on public.user_identities for select to authenticated
  using (auth.uid() = user_id or public.is_admin_caller());

alter table public.admin_user_moderation enable row level security;
drop policy if exists admin_user_moderation_read_all on public.admin_user_moderation;
drop policy if exists admin_user_moderation_read on public.admin_user_moderation;
create policy admin_user_moderation_read_own_or_admin on public.admin_user_moderation for select to authenticated
  using (auth.uid() = user_id or public.is_admin_caller());

-- Only an actual administrator can create a message block on behalf of admin_id.
alter table public.admin_message_blocks enable row level security;
drop policy if exists admin_message_blocks_insert_admin on public.admin_message_blocks;
drop policy if exists admin_message_blocks_delete_admin on public.admin_message_blocks;
create policy admin_message_blocks_insert_admin on public.admin_message_blocks for insert to authenticated
  with check (public.is_admin_caller() and auth.uid() = admin_id);
create policy admin_message_blocks_delete_admin on public.admin_message_blocks for delete to authenticated
  using (public.is_admin_caller() and auth.uid() = admin_id);

-- Public reads are retained for existing getPublicUrl() media links. Writes are
-- restricted to the caller's <uid>/ folder; administrators may manage a user's folder.
alter table storage.objects enable row level security;
drop policy if exists "Public Access for avatars" on storage.objects;
drop policy if exists "Authenticated Upload for avatars" on storage.objects;
drop policy if exists "Authenticated Update for avatars" on storage.objects;
drop policy if exists "Authenticated Delete for avatars" on storage.objects;
drop policy if exists "Public Access for voices" on storage.objects;
drop policy if exists "Authenticated Upload for voices" on storage.objects;
drop policy if exists "Authenticated Update for voices" on storage.objects;
drop policy if exists "Authenticated Delete for voices" on storage.objects;
drop policy if exists storage_public_media_read on storage.objects;
drop policy if exists storage_owner_media_insert on storage.objects;
drop policy if exists storage_owner_or_admin_media_update on storage.objects;
drop policy if exists storage_owner_or_admin_media_delete on storage.objects;

create policy storage_public_media_read on storage.objects for select
  using (bucket_id in ('avatars', 'voices'));
create policy storage_owner_media_insert on storage.objects for insert to authenticated
  with check (
    bucket_id in ('avatars', 'voices')
    and split_part(name, '/', 1) = auth.uid()::text
  );
create policy storage_owner_or_admin_media_update on storage.objects for update to authenticated
  using (
    bucket_id in ('avatars', 'voices')
    and (split_part(name, '/', 1) = auth.uid()::text or public.is_admin_caller())
  )
  with check (
    bucket_id in ('avatars', 'voices')
    and (split_part(name, '/', 1) = auth.uid()::text or public.is_admin_caller())
  );
create policy storage_owner_or_admin_media_delete on storage.objects for delete to authenticated
  using (
    bucket_id in ('avatars', 'voices')
    and (split_part(name, '/', 1) = auth.uid()::text or public.is_admin_caller())
  );

commit;
