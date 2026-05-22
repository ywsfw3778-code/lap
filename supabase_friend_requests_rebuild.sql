create extension if not exists pgcrypto;

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friend_requests_no_self check (sender_id <> receiver_id)
);

alter table public.friend_requests
  add column if not exists sender_email text,
  add column if not exists receiver_email text;

create index if not exists friend_requests_sender_email_idx on public.friend_requests (lower(sender_email));
create index if not exists friend_requests_receiver_email_idx on public.friend_requests (lower(receiver_email));
create index if not exists friend_requests_email_status_idx on public.friend_requests (lower(sender_email), lower(receiver_email), status);
create index if not exists friend_requests_pair_idx on public.friend_requests (least(sender_id, receiver_id), greatest(sender_id, receiver_id));

create table if not exists public.user_identities (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null
);

insert into public.user_identities (user_id, email)
select id, lower(email)
from auth.users
where email is not null
on conflict (user_id) do update
set email = excluded.email;

update public.friend_requests fr
set sender_email = lower(coalesce(fr.sender_email, p.email, u.email))
from auth.users u
left join public.profiles p on p.id = u.id
where u.id = fr.sender_id
  and fr.sender_email is null;

update public.friend_requests fr
set receiver_email = lower(coalesce(fr.receiver_email, p.email, u.email))
from auth.users u
left join public.profiles p on p.id = u.id
where u.id = fr.receiver_id
  and fr.receiver_email is null;

-- Ensure messages table has read_at column for read receipts
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'messages' and column_name = 'read_at'
  ) then
    alter table public.messages add column read_at timestamptz default null;
  end if;
end;
$$;

drop function if exists public.get_friend_relation_for_email(text, uuid);
drop function if exists public.get_friend_relations_for_email(text, uuid[]);
drop function if exists public.send_friend_request_for_email(text, uuid);
drop function if exists public.cancel_friend_request_for_email(text, uuid);
drop function if exists public.respond_friend_request_for_email(text, uuid, text);
drop function if exists public.get_pending_friend_requests_for_email(text);
drop function if exists public.get_inbox_contacts_for_email(text);
drop function if exists public.get_chat_messages_for_email(text, uuid, integer);
drop function if exists public.get_profiles_by_ids(uuid[]);
drop function if exists public.mark_messages_as_read(text, uuid);

create or replace function public.friend_assert_current_email(current_email text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized text;
  token_email text;
begin
  normalized := lower(trim(coalesce(current_email, '')));
  token_email := lower(trim(coalesce(auth.jwt()->>'email', '')));
  if normalized = '' or token_email = '' or normalized <> token_email then
    raise exception 'email_mismatch';
  end if;
  return normalized;
end;
$$;

create or replace function public.friend_target_email(target_user_id uuid)
returns text
language sql
security definer
set search_path = public, auth
as $$
  select lower(coalesce(p.email, u.email))
  from auth.users u
  left join public.profiles p on p.id = u.id
  where u.id = target_user_id
  limit 1
$$;

create or replace function public.friend_current_ids(current_email text)
returns table(user_id uuid)
language sql
security definer
set search_path = public, auth
as $$
  select distinct x.user_id
  from (
    select ui.user_id, lower(ui.email) as email
    from public.user_identities ui
    union all
    select u.id, lower(u.email)
    from auth.users u
    where u.email is not null
    union all
    select p.id, lower(p.email)
    from public.profiles p
    where p.email is not null
  ) x
  where x.email = lower(trim(current_email))
$$;

create or replace function public.get_friend_relation_for_email(current_email text, target_user_id uuid)
returns table(
  id uuid,
  sender_id uuid,
  receiver_id uuid,
  status text,
  sender_email text,
  receiver_email text
)
language sql
security definer
set search_path = public, auth
as $$
  with me as (select public.friend_assert_current_email(current_email) as email),
       target as (select public.friend_target_email(target_user_id) as email)
  select fr.id, fr.sender_id, fr.receiver_id, fr.status, fr.sender_email, fr.receiver_email
  from public.friend_requests fr
  where (
      lower(fr.sender_email) = (select email from me)
      and lower(fr.receiver_email) = (select email from target)
    ) or (
      lower(fr.sender_email) = (select email from target)
      and lower(fr.receiver_email) = (select email from me)
    ) or (
      fr.sender_id in (select user_id from public.friend_current_ids((select email from me)))
      and fr.receiver_id = target_user_id
    ) or (
      fr.sender_id = target_user_id
      and fr.receiver_id in (select user_id from public.friend_current_ids((select email from me)))
    )
  order by fr.created_at desc
  limit 1
$$;

create or replace function public.get_friend_relations_for_email(current_email text, target_user_ids uuid[])
returns table(
  other_id uuid,
  id uuid,
  sender_id uuid,
  receiver_id uuid,
  status text,
  sender_email text,
  receiver_email text
)
language sql
security definer
set search_path = public, auth
as $$
  with me as (select public.friend_assert_current_email(current_email) as email),
       targets as (
         select u.id as target_id, lower(coalesce(p.email, u.email)) as email
         from auth.users u
         left join public.profiles p on p.id = u.id
         where u.id = any(coalesce(target_user_ids, '{}'::uuid[]))
       ),
       rel as (
         select
           coalesce(t.target_id, case when lower(fr.sender_email) = (select email from me) then fr.receiver_id else fr.sender_id end) as other_id,
           fr.id,
           fr.sender_id,
           fr.receiver_id,
           fr.status,
           fr.sender_email,
           fr.receiver_email,
           fr.created_at,
           row_number() over (
             partition by coalesce(t.target_id, case when lower(fr.sender_email) = (select email from me) then fr.receiver_id else fr.sender_id end)
             order by fr.created_at desc
           ) as rn
         from public.friend_requests fr
         left join targets t
           on lower(fr.sender_email) = t.email or lower(fr.receiver_email) = t.email
         where (
             (lower(fr.sender_email) = (select email from me) and lower(fr.receiver_email) in (select email from targets))
             or (lower(fr.receiver_email) = (select email from me) and lower(fr.sender_email) in (select email from targets))
             or (fr.sender_id in (select user_id from public.friend_current_ids((select email from me))) and fr.receiver_id = any(coalesce(target_user_ids, '{}'::uuid[])))
             or (fr.receiver_id in (select user_id from public.friend_current_ids((select email from me))) and fr.sender_id = any(coalesce(target_user_ids, '{}'::uuid[])))
           )
       )
  select rel.other_id, rel.id, rel.sender_id, rel.receiver_id, rel.status, rel.sender_email, rel.receiver_email
  from rel
  where rel.rn = 1
$$;

create or replace function public.send_friend_request_for_email(current_email text, target_user_id uuid)
returns table(
  id uuid,
  sender_id uuid,
  receiver_id uuid,
  status text,
  sender_email text,
  receiver_email text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_me_email text;
  v_target_email text;
  v_existing public.friend_requests%rowtype;
begin
  v_me_email := public.friend_assert_current_email(current_email);
  v_target_email := public.friend_target_email(target_user_id);

  if v_target_email is null then
    raise exception 'target_not_found';
  end if;

  if v_target_email = v_me_email then
    raise exception 'invalid_target';
  end if;

  select * into v_existing
  from public.friend_requests fr
  where (
      lower(fr.sender_email) = v_me_email and lower(fr.receiver_email) = v_target_email
    ) or (
      lower(fr.sender_email) = v_target_email and lower(fr.receiver_email) = v_me_email
    ) or (
      fr.sender_id in (select user_id from public.friend_current_ids(v_me_email)) and fr.receiver_id = target_user_id
    ) or (
      fr.sender_id = target_user_id and fr.receiver_id in (select user_id from public.friend_current_ids(v_me_email))
    )
  order by fr.created_at desc
  limit 1;

  if found then
    update public.friend_requests fr
    set sender_email = coalesce(fr.sender_email, lower(coalesce(sp.email, su.email))),
        receiver_email = coalesce(fr.receiver_email, lower(coalesce(rp.email, ru.email))),
        updated_at = now()
    from auth.users su
    left join public.profiles sp on sp.id = su.id,
         auth.users ru
    left join public.profiles rp on rp.id = ru.id
    where fr.id = v_existing.id
      and su.id = fr.sender_id
      and ru.id = fr.receiver_id
    returning fr.* into v_existing;

    return query select v_existing.id, v_existing.sender_id, v_existing.receiver_id, v_existing.status, v_existing.sender_email, v_existing.receiver_email;
    return;
  end if;

  insert into public.friend_requests(sender_id, receiver_id, sender_email, receiver_email, status)
  values (auth.uid(), target_user_id, v_me_email, v_target_email, 'pending')
  returning * into v_existing;

  return query select v_existing.id, v_existing.sender_id, v_existing.receiver_id, v_existing.status, v_existing.sender_email, v_existing.receiver_email;
end;
$$;

create or replace function public.cancel_friend_request_for_email(current_email text, target_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_me_email text;
  v_target_email text;
begin
  v_me_email := public.friend_assert_current_email(current_email);
  v_target_email := public.friend_target_email(target_user_id);

  delete from public.friend_requests fr
  where fr.status = 'pending'
    and (
      (lower(fr.sender_email) = v_me_email and lower(fr.receiver_email) = v_target_email)
      or (fr.sender_id in (select user_id from public.friend_current_ids(v_me_email)) and fr.receiver_id = target_user_id)
    );

  return true;
end;
$$;

create or replace function public.respond_friend_request_for_email(current_email text, request_id uuid, new_status text)
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_me_email text;
begin
  v_me_email := public.friend_assert_current_email(current_email);

  if new_status not in ('accepted', 'declined') then
    raise exception 'invalid_status';
  end if;

  update public.friend_requests fr
  set status = new_status,
      receiver_email = coalesce(fr.receiver_email, v_me_email),
      updated_at = now()
  where fr.id = request_id
    and (
      lower(fr.receiver_email) = v_me_email
      or fr.receiver_id in (select user_id from public.friend_current_ids(v_me_email))
    );

  return true;
end;
$$;

create or replace function public.get_pending_friend_requests_for_email(current_email text)
returns table(
  id uuid,
  sender_id uuid,
  sender_name text,
  sender_username text,
  sender_email text,
  sender_avatar text,
  sender_member_code integer,
  created_at timestamptz
)
language sql
security definer
set search_path = public, auth
as $$
  with me as (select public.friend_assert_current_email(current_email) as email)
  select
    fr.id,
    fr.sender_id,
    coalesce(p.full_name, p.username, split_part(coalesce(fr.sender_email, p.email, ''), '@', 1), 'User') as sender_name,
    p.username as sender_username,
    coalesce(fr.sender_email, p.email) as sender_email,
    p.avatar_url as sender_avatar,
    p.member_code as sender_member_code,
    fr.created_at
  from public.friend_requests fr
  left join public.profiles p on p.id = fr.sender_id
  where fr.status = 'pending'
    and (
      lower(fr.receiver_email) = (select email from me)
      or fr.receiver_id in (select user_id from public.friend_current_ids((select email from me)))
    )
  order by fr.created_at desc
$$;

create or replace function public.get_inbox_contacts_for_email(current_email text)
returns table(
  partner_id uuid,
  name text,
  username text,
  email text,
  avatar_url text,
  member_code integer,
  last_seen_at timestamptz,
  last_content text,
  last_created_at timestamptz,
  unread_count integer
)
language sql
security definer
set search_path = public, auth
as $$
  with me as (select public.friend_assert_current_email(current_email) as email),
  my_ids as (select user_id from public.friend_current_ids((select email from me))),
  combined as (
    select
      case when m.sender_id in (select user_id from my_ids) then m.receiver_id else m.sender_id end as partner_id,
      m.content,
      m.created_at as activity_at
    from public.messages m
    where m.sender_id in (select user_id from my_ids)
       or m.receiver_id in (select user_id from my_ids)
    union all
    select
      case when fr.sender_id in (select user_id from my_ids) then fr.receiver_id else fr.sender_id end as partner_id,
      null::text as content,
      fr.updated_at as activity_at
    from public.friend_requests fr
    where fr.status = 'accepted'
      and (
        fr.sender_id in (select user_id from my_ids)
        or fr.receiver_id in (select user_id from my_ids)
        or lower(fr.sender_email) = (select email from me)
        or lower(fr.receiver_email) = (select email from me)
      )
  ),
  ranked as (
    select
      partner_id,
      content,
      activity_at,
      row_number() over (
        partition by partner_id
        order by activity_at desc
      ) as rn
    from combined
  ),
  partner_emails as (
    select id as user_id, lower(email) as email from public.profiles where email is not null
    union
    select user_id as user_id, lower(email) as email from public.user_identities where email is not null
  ),
  max_activity as (
    select lower(email) as email, max(last_seen_at) as max_last_seen
    from public.profiles
    where last_seen_at is not null
    group by lower(email)
  )
  select
    r.partner_id,
    coalesce(p.full_name, p.username, split_part(coalesce(p.email, ''), '@', 1), 'User') as name,
    p.username,
    p.email,
    p.avatar_url,
    p.member_code,
    coalesce(ma.max_last_seen, p.last_seen_at) as last_seen_at,
    r.content as last_content,
    r.activity_at as last_created_at,
    (
      select count(*)::integer
      from public.messages m2
      where m2.sender_id = r.partner_id
        and m2.receiver_id in (select user_id from my_ids)
        and m2.read_at is null
    ) as unread_count
  from ranked r
  left join public.profiles p on p.id = r.partner_id
  left join partner_emails pe on pe.user_id = r.partner_id
  left join max_activity ma on ma.email = pe.email
  where r.rn = 1
  order by r.activity_at desc
$$;

create or replace function public.get_chat_messages_for_email(
  current_email text,
  partner_user_id uuid,
  result_limit integer default 200
)
returns table(
  id bigint,
  sender_id uuid,
  receiver_id uuid,
  content text,
  created_at timestamptz,
  read_at timestamptz
)
language sql
security definer
set search_path = public, auth
as $$
  with me as (select public.friend_assert_current_email(current_email) as email),
  my_ids as (select user_id from public.friend_current_ids((select email from me)))
  select
    m.id::bigint,
    m.sender_id,
    m.receiver_id,
    m.content,
    m.created_at,
    m.read_at
  from public.messages m
  where
    (m.sender_id in (select user_id from my_ids) and m.receiver_id = partner_user_id)
    or
    (m.sender_id = partner_user_id and m.receiver_id in (select user_id from my_ids))
  order by m.created_at asc
  limit greatest(1, least(coalesce(result_limit, 200), 500))
$$;

-- Mark incoming messages as read when the receiver opens the chat
create or replace function public.mark_messages_as_read(
  current_email text,
  partner_user_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  updated_count integer;
begin
  with me as (select public.friend_assert_current_email(current_email) as email),
  my_ids as (select user_id from public.friend_current_ids((select email from me)))
  update public.messages
  set read_at = now()
  where sender_id = partner_user_id
    and receiver_id in (select user_id from my_ids)
    and read_at is null;
  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;

alter table public.friend_requests enable row level security;
alter table public.user_identities enable row level security;
alter table public.messages enable row level security;

create table if not exists public.admin_message_blocks (
  admin_id uuid not null references auth.users(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (admin_id, user_id),
  constraint admin_message_blocks_no_self check (admin_id <> user_id)
);

alter table public.admin_message_blocks enable row level security;

drop policy if exists "user_identities_select_authenticated" on public.user_identities;
create policy "user_identities_select_authenticated"
on public.user_identities
for select
to authenticated
using (true);

do $$
declare pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'friend_requests'
  loop
    execute format('drop policy if exists %I on public.friend_requests', pol.policyname);
  end loop;

  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'messages'
  loop
    execute format('drop policy if exists %I on public.messages', pol.policyname);
  end loop;

  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'admin_message_blocks'
  loop
    execute format('drop policy if exists %I on public.admin_message_blocks', pol.policyname);
  end loop;
end $$;

create policy "friend_requests_select_same_email"
on public.friend_requests
for select
to authenticated
using (
  auth.uid() = sender_id
  or auth.uid() = receiver_id
  or exists (
    select 1
    from public.user_identities ui_my
    where ui_my.user_id = auth.uid()
      and (
        lower(ui_my.email) = lower(friend_requests.sender_email)
        or lower(ui_my.email) = lower(friend_requests.receiver_email)
      )
  )
);

create policy "friend_requests_insert_self_email"
on public.friend_requests
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and sender_id <> receiver_id
  and status = 'pending'
  and (
    sender_email is null
    or exists (
      select 1
      from public.user_identities ui
      where ui.user_id = auth.uid()
        and lower(ui.email) = lower(sender_email)
    )
  )
);

create policy "friend_requests_delete_sender_same_email"
on public.friend_requests
for delete
to authenticated
using (
  auth.uid() = sender_id
  or exists (
    select 1
    from public.user_identities ui_my
    where ui_my.user_id = auth.uid()
      and lower(ui_my.email) = lower(friend_requests.sender_email)
  )
);

create policy "friend_requests_update_receiver_same_email"
on public.friend_requests
for update
to authenticated
using (
  auth.uid() = receiver_id
  or exists (
    select 1
    from public.user_identities ui_my
    where ui_my.user_id = auth.uid()
      and lower(ui_my.email) = lower(friend_requests.receiver_email)
  )
)
with check (
  status in ('accepted', 'declined')
);

create policy "messages_select_same_email"
on public.messages
for select
to authenticated
using (
  auth.uid() = sender_id
  or auth.uid() = receiver_id
  or exists (
    select 1
    from public.user_identities ui_my
    where ui_my.user_id = auth.uid()
      and exists (
        select 1
        from public.user_identities ui_msg
        where lower(ui_msg.email) = lower(ui_my.email)
          and (ui_msg.user_id = messages.sender_id or ui_msg.user_id = messages.receiver_id)
      )
  )
);

create policy "messages_insert_self"
on public.messages
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and not exists (
    select 1
    from public.admin_message_blocks amb
    where amb.admin_id = messages.receiver_id
      and amb.user_id = auth.uid()
  )
);

create policy "messages_update_sender"
on public.messages
for update
to authenticated
using (
  auth.uid() = sender_id
  or exists (
    select 1
    from public.user_identities ui_my
    where ui_my.user_id = auth.uid()
      and exists (
        select 1
        from public.user_identities ui_sender
        where ui_sender.user_id = messages.sender_id
          and lower(ui_sender.email) = lower(ui_my.email)
      )
  )
)
with check (
  auth.uid() = sender_id
  or exists (
    select 1
    from public.user_identities ui_my
    where ui_my.user_id = auth.uid()
      and exists (
        select 1
        from public.user_identities ui_sender
        where ui_sender.user_id = messages.sender_id
          and lower(ui_sender.email) = lower(ui_my.email)
      )
  )
);

create policy "messages_delete_sender"
on public.messages
for delete
to authenticated
using (
  auth.uid() = sender_id
  or exists (
    select 1
    from public.user_identities ui_my
    where ui_my.user_id = auth.uid()
      and exists (
        select 1
        from public.user_identities ui_sender
        where ui_sender.user_id = messages.sender_id
          and lower(ui_sender.email) = lower(ui_my.email)
      )
  )
);

create policy "admin_message_blocks_select_related"
on public.admin_message_blocks
for select
to authenticated
using (auth.uid() = admin_id or auth.uid() = user_id);

create policy "admin_message_blocks_insert_admin"
on public.admin_message_blocks
for insert
to authenticated
with check (auth.uid() = admin_id);

create policy "admin_message_blocks_delete_admin"
on public.admin_message_blocks
for delete
to authenticated
using (auth.uid() = admin_id);

grant select on public.user_identities to authenticated;
grant select, insert, update, delete on public.friend_requests to authenticated;
grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, delete on public.admin_message_blocks to authenticated;
grant execute on function public.friend_assert_current_email(text) to authenticated;
grant execute on function public.friend_target_email(uuid) to authenticated;
grant execute on function public.friend_current_ids(text) to authenticated;
grant execute on function public.get_friend_relation_for_email(text, uuid) to authenticated;
grant execute on function public.get_friend_relations_for_email(text, uuid[]) to authenticated;
grant execute on function public.send_friend_request_for_email(text, uuid) to authenticated;
grant execute on function public.cancel_friend_request_for_email(text, uuid) to authenticated;
grant execute on function public.respond_friend_request_for_email(text, uuid, text) to authenticated;
grant execute on function public.get_pending_friend_requests_for_email(text) to authenticated;
grant execute on function public.get_inbox_contacts_for_email(text) to authenticated;
grant execute on function public.get_chat_messages_for_email(text, uuid, integer) to authenticated;
grant execute on function public.mark_messages_as_read(text, uuid) to authenticated;

-- profiles RLS Setup
alter table public.profiles enable row level security;

do $$
declare
  pol record;
begin
  for pol in (
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'profiles'
  ) loop
    execute format('drop policy if exists %I on public.profiles', pol.policyname);
  end loop;
end;
$$;

create policy "profiles_select_authenticated" on public.profiles for select to authenticated using (true);
create policy "profiles_insert_self" on public.profiles for insert to authenticated with check (auth.uid() = id);
create policy "profiles_update_self" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

grant select, insert, update on public.profiles to authenticated;

-- get_profiles_by_ids RPC definition
create or replace function public.get_profiles_by_ids(user_ids uuid[])
returns table(
  id uuid,
  username text,
  full_name text,
  email text,
  avatar_url text,
  member_code integer,
  last_seen_at timestamptz
)
language sql
security definer
set search_path = public, auth
as $$
  with target_emails as (
    select p.id as target_user_id, lower(p.email) as email from public.profiles p where p.id = any(user_ids) and p.email is not null
    union
    select ui.user_id as target_user_id, lower(ui.email) as email from public.user_identities ui where ui.user_id = any(user_ids) and ui.email is not null
  ),
  max_activity as (
    select lower(email) as email, max(last_seen_at) as max_last_seen
    from public.profiles
    where email is not null
    group by lower(email)
  )
  select
    p.id,
    p.username,
    p.full_name,
    p.email,
    p.avatar_url,
    p.member_code,
    coalesce(ma.max_last_seen, p.last_seen_at) as last_seen_at
  from public.profiles p
  left join target_emails te on te.target_user_id = p.id
  left join max_activity ma on ma.email = te.email
  where p.id = any(user_ids)
$$;

grant execute on function public.get_profiles_by_ids(uuid[]) to authenticated;

-- Configure Supabase Realtime Publication for real-time messages and notifications
do $$
begin
  -- Ensure the supabase_realtime publication exists
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  -- Add tables to the publication if they are not already members
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'friend_requests'
  ) then
    alter publication supabase_realtime add table public.friend_requests;
  end if;

  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;

exception
  when others then
    raise notice 'Could not configure supabase_realtime publication: %', sqlerrm;
end;
$$;

notify pgrst, 'reload schema';
notify pgrst, 'reload config';
