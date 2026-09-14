-- Our Little World: run this once in Supabase Dashboard -> SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.couples (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Our Little World',
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 8)),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.couple_members (
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'partner' check (role in ('owner', 'partner')),
  joined_at timestamptz not null default now(),
  primary key (couple_id, user_id)
);

create table if not exists public.couple_state (
  couple_id uuid primary key references public.couples(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  storage_path text not null unique,
  caption text not null default '',
  taken_on date not null default current_date,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_couple_member(target_couple uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (
  select 1 from public.couple_members
  where couple_id = target_couple and user_id = auth.uid()
) $$;

create or replace function public.create_couple(space_name text default 'Our Little World')
returns uuid language plpgsql security definer set search_path = public
as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if exists (select 1 from public.couple_members where user_id = auth.uid()) then
    raise exception 'You already belong to a shared space';
  end if;
  insert into public.couples (name, created_by)
  values (coalesce(nullif(trim(space_name), ''), 'Our Little World'), auth.uid())
  returning id into new_id;
  insert into public.couple_members (couple_id, user_id, role)
  values (new_id, auth.uid(), 'owner');
  insert into public.couple_state (couple_id, data, updated_by)
  values (new_id, '{}'::jsonb, auth.uid());
  return new_id;
end;
$$;

create or replace function public.join_couple(code text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare target_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if exists (select 1 from public.couple_members where user_id = auth.uid()) then
    raise exception 'You already belong to a shared space';
  end if;
  select id into target_id from public.couples where invite_code = upper(trim(code));
  if target_id is null then raise exception 'Invite code not found'; end if;
  if (select count(*) from public.couple_members where couple_id = target_id) >= 2 then
    raise exception 'This shared space already has two members';
  end if;
  insert into public.couple_members (couple_id, user_id, role)
  values (target_id, auth.uid(), 'partner');
  return target_id;
end;
$$;

alter table public.profiles enable row level security;
alter table public.couples enable row level security;
alter table public.couple_members enable row level security;
alter table public.couple_state enable row level security;
alter table public.photos enable row level security;

drop policy if exists "profiles read own" on public.profiles;
create policy "profiles read own" on public.profiles for select using (id = auth.uid());
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles for update using (id = auth.uid());
drop policy if exists "members read couple" on public.couple_members;
create policy "members read couple" on public.couple_members for select using (public.is_couple_member(couple_id));
drop policy if exists "couples read member" on public.couples;
create policy "couples read member" on public.couples for select using (public.is_couple_member(id));
drop policy if exists "state read member" on public.couple_state;
create policy "state read member" on public.couple_state for select using (public.is_couple_member(couple_id));
drop policy if exists "state insert member" on public.couple_state;
create policy "state insert member" on public.couple_state for insert with check (public.is_couple_member(couple_id));
drop policy if exists "state update member" on public.couple_state;
create policy "state update member" on public.couple_state for update using (public.is_couple_member(couple_id)) with check (public.is_couple_member(couple_id));
drop policy if exists "photos read member" on public.photos;
create policy "photos read member" on public.photos for select using (public.is_couple_member(couple_id));
drop policy if exists "photos insert member" on public.photos;
create policy "photos insert member" on public.photos for insert with check (public.is_couple_member(couple_id) and created_by = auth.uid());
drop policy if exists "photos delete member" on public.photos;
create policy "photos delete member" on public.photos for delete using (public.is_couple_member(couple_id));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('couple-photos', 'couple-photos', false, 26214400, array['image/jpeg','image/png','image/gif','image/webp','image/heic','image/heif'])
on conflict (id) do update set public = false;

drop policy if exists "couple photos read" on storage.objects;
create policy "couple photos read" on storage.objects for select to authenticated
using (bucket_id = 'couple-photos' and public.is_couple_member(((storage.foldername(name))[1])::uuid));
drop policy if exists "couple photos upload" on storage.objects;
create policy "couple photos upload" on storage.objects for insert to authenticated
with check (bucket_id = 'couple-photos' and public.is_couple_member(((storage.foldername(name))[1])::uuid));
drop policy if exists "couple photos delete" on storage.objects;
create policy "couple photos delete" on storage.objects for delete to authenticated
using (bucket_id = 'couple-photos' and public.is_couple_member(((storage.foldername(name))[1])::uuid));

grant execute on function public.create_couple(text) to authenticated;
grant execute on function public.join_couple(text) to authenticated;
grant execute on function public.is_couple_member(uuid) to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.couple_state;
exception when duplicate_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.photos;
exception when duplicate_object then null;
end $$;
