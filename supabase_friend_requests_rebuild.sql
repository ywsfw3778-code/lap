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

create unique index if not exists friend_requests_pair_unique
on public.friend_requests (least(sender_id, receiver_id), greatest(sender_id, receiver_id));

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

create or replace function public.friend_current_ids(current_email text)
returns table(user_id uuid)
language sql
security definer
set search_path = public, auth
as $$
  select ui.user_id
  from public.user_identities ui
  where lower(ui.email) = lower(current_email)
$$;

create or replace function public.get_friend_relation_for_email(current_email text, target_user_id uuid)
returns table(id uuid, sender_id uuid, receiver_id uuid, status text)
language sql
security definer
set search_path = public
as $$
  with me as (select user_id from public.friend_current_ids(current_email))
  select fr.id, fr.sender_id, fr.receiver_id, fr.status
  from public.friend_requests fr
  where
    (fr.sender_id in (select user_id from me) and fr.receiver_id = target_user_id)
    or
    (fr.sender_id = target_user_id and fr.receiver_id in (select user_id from me))
  order by fr.created_at desc
  limit 1
$$;

create or replace function public.get_friend_relations_for_email(current_email text, target_user_ids uuid[])
returns table(other_id uuid, id uuid, sender_id uuid, receiver_id uuid, status text)
language sql
security definer
set search_path = public
as $$
  with me as (select user_id from public.friend_current_ids(current_email)),
  rel as (
    select
      case when fr.sender_id in (select user_id from me) then fr.receiver_id else fr.sender_id end as other_id,
      fr.id,
      fr.sender_id,
      fr.receiver_id,
      fr.status,
      fr.created_at,
      row_number() over (
        partition by case when fr.sender_id in (select user_id from me) then fr.receiver_id else fr.sender_id end
        order by fr.created_at desc
      ) as rn
    from public.friend_requests fr
    where
      (fr.sender_id in (select user_id from me) and fr.receiver_id = any(coalesce(target_user_ids, '{}')))
      or
      (fr.receiver_id in (select user_id from me) and fr.sender_id = any(coalesce(target_user_ids, '{}')))
  )
  select other_id, id, sender_id, receiver_id, status
  from rel
  where rn = 1
$$;

create or replace function public.send_friend_request_for_email(current_email text, target_user_id uuid)
returns table(id uuid, sender_id uuid, receiver_id uuid, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  me_id uuid;
  existing public.friend_requests%rowtype;
begin
  if lower(coalesce(current_email, '')) <> lower(coalesce(auth.jwt()->>'email', '')) then
    raise exception 'email_mismatch';
  end if;

  select auth.uid() into me_id
  where auth.uid() in (select user_id from public.friend_current_ids(current_email));

  if me_id is null then
    select user_id into me_id
    from public.friend_current_ids(current_email)
    order by user_id
    limit 1;
  end if;

  if me_id is null then
    raise exception 'not_authenticated';
  end if;

  if target_user_id is null or target_user_id = me_id then
    raise exception 'invalid_target';
  end if;

  select * into existing
  from public.friend_requests fr
  where
    (fr.sender_id in (select user_id from public.friend_current_ids(current_email)) and fr.receiver_id = target_user_id)
    or
    (fr.sender_id = target_user_id and fr.receiver_id in (select user_id from public.friend_current_ids(current_email)))
  order by fr.created_at desc
  limit 1;

  if found then
    return query select existing.id, existing.sender_id, existing.receiver_id, existing.status;
    return;
  end if;

  insert into public.friend_requests(sender_id, receiver_id, status)
  values (me_id, target_user_id, 'pending')
  returning friend_requests.* into existing;

  return query select existing.id, existing.sender_id, existing.receiver_id, existing.status;
end;
$$;

create or replace function public.cancel_friend_request_for_email(current_email text, target_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  delete from public.friend_requests fr
  where fr.status = 'pending'
    and fr.receiver_id = target_user_id
    and fr.sender_id in (select user_id from public.friend_current_ids(current_email));
  select true
$$;

create or replace function public.respond_friend_request_for_email(current_email text, request_id uuid, new_status text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if new_status not in ('accepted', 'declined') then
    raise exception 'invalid_status';
  end if;

  update public.friend_requests fr
  set status = new_status, updated_at = now()
  where fr.id = request_id
    and fr.receiver_id in (select user_id from public.friend_current_ids(current_email));

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
set search_path = public
as $$
  with me as (select user_id from public.friend_current_ids(current_email))
  select
    fr.id,
    fr.sender_id,
    coalesce(p.full_name, p.username, split_part(coalesce(p.email, ''), '@', 1), 'مستخدم') as sender_name,
    p.username as sender_username,
    p.email as sender_email,
    p.avatar_url as sender_avatar,
    p.member_code as sender_member_code,
    fr.created_at
  from public.friend_requests fr
  left join public.profiles p on p.id = fr.sender_id
  where fr.receiver_id in (select user_id from me)
    and fr.status = 'pending'
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
  last_created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  with me as (select user_id from public.friend_current_ids(current_email)),
  ranked as (
    select
      case
        when m.sender_id in (select user_id from me) then m.receiver_id
        else m.sender_id
      end as partner_id,
      m.content,
      m.created_at,
      row_number() over (
        partition by case
          when m.sender_id in (select user_id from me) then m.receiver_id
          else m.sender_id
        end
        order by m.created_at desc
      ) as rn
    from public.messages m
    where m.sender_id in (select user_id from me)
       or m.receiver_id in (select user_id from me)
  )
  select
    r.partner_id,
    coalesce(p.full_name, p.username, split_part(coalesce(p.email, ''), '@', 1), 'User') as name,
    p.username,
    p.email,
    p.avatar_url,
    p.member_code,
    p.last_seen_at,
    r.content as last_content,
    r.created_at as last_created_at
  from ranked r
  left join public.profiles p on p.id = r.partner_id
  where r.rn = 1
  order by r.created_at desc
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
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  with me as (select user_id from public.friend_current_ids(current_email))
  select
    m.id,
    m.sender_id,
    m.receiver_id,
    m.content,
    m.created_at
  from public.messages m
  where
    (m.sender_id in (select user_id from me) and m.receiver_id = partner_user_id)
    or
    (m.sender_id = partner_user_id and m.receiver_id in (select user_id from me))
  order by m.created_at asc
  limit greatest(1, least(coalesce(result_limit, 200), 500))
$$;

alter table public.friend_requests enable row level security;
alter table public.user_identities enable row level security;
alter table public.messages enable row level security;

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
end $$;

create policy "friend_requests_select_same_email"
on public.friend_requests
for select
to authenticated
using (
  exists (
    select 1
    from public.user_identities ui
    where lower(ui.email) = lower(coalesce(auth.jwt()->>'email', ''))
      and (ui.user_id = friend_requests.sender_id or ui.user_id = friend_requests.receiver_id)
  )
);

create policy "friend_requests_insert_self"
on public.friend_requests
for insert
to authenticated
with check (auth.uid() = sender_id and sender_id <> receiver_id and status = 'pending');

create policy "friend_requests_update_same_email"
on public.friend_requests
for update
to authenticated
using (
  exists (
    select 1
    from public.user_identities ui
    where lower(ui.email) = lower(coalesce(auth.jwt()->>'email', ''))
      and (ui.user_id = friend_requests.sender_id or ui.user_id = friend_requests.receiver_id)
  )
)
with check (
  exists (
    select 1
    from public.user_identities ui
    where lower(ui.email) = lower(coalesce(auth.jwt()->>'email', ''))
      and (ui.user_id = friend_requests.sender_id or ui.user_id = friend_requests.receiver_id)
  )
);

create policy "friend_requests_delete_sender_same_email"
on public.friend_requests
for delete
to authenticated
using (
  exists (
    select 1
    from public.user_identities ui
    where lower(ui.email) = lower(coalesce(auth.jwt()->>'email', ''))
      and ui.user_id = friend_requests.sender_id
  )
);

create policy "messages_select_same_email"
on public.messages
for select
to authenticated
using (
  exists (
    select 1
    from public.user_identities ui
    where lower(ui.email) = lower(coalesce(auth.jwt()->>'email', ''))
      and (ui.user_id = messages.sender_id or ui.user_id = messages.receiver_id)
  )
);

create policy "messages_insert_self"
on public.messages
for insert
to authenticated
with check (auth.uid() = sender_id);

create policy "messages_update_sender"
on public.messages
for update
to authenticated
using (auth.uid() = sender_id)
with check (auth.uid() = sender_id);

create policy "messages_delete_sender"
on public.messages
for delete
to authenticated
using (auth.uid() = sender_id);

grant select on public.user_identities to authenticated;
grant select, insert, update, delete on public.friend_requests to authenticated;
grant select, insert, update, delete on public.messages to authenticated;
grant execute on function public.friend_current_ids(text) to authenticated;
grant execute on function public.get_friend_relation_for_email(text, uuid) to authenticated;
grant execute on function public.get_friend_relations_for_email(text, uuid[]) to authenticated;
grant execute on function public.send_friend_request_for_email(text, uuid) to authenticated;
grant execute on function public.cancel_friend_request_for_email(text, uuid) to authenticated;
grant execute on function public.respond_friend_request_for_email(text, uuid, text) to authenticated;
grant execute on function public.get_pending_friend_requests_for_email(text) to authenticated;
grant execute on function public.get_inbox_contacts_for_email(text) to authenticated;
grant execute on function public.get_chat_messages_for_email(text, uuid, integer) to authenticated;

notify pgrst, 'reload schema';
notify pgrst, 'reload config';
