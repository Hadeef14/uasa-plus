-- ============================================================
-- UASA+ Supabase Schema
-- Every table, RPC and edge function referenced by index.html
-- ============================================================

-- ---------- TABLES ----------

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
  role text default 'student' check (role in ('student','teacher','admin')),
  year text,
  class_code text,
  recovery_email text,
  xp integer default 0,
  streak integer default 0,
  last_active date,
  streak_freezes integer default 0,
  hearts integer default 5,
  daily_xp integer default 0,
  daily_xp_date date,
  leaderboard_opt_out boolean default false,
  created_at timestamptz default now()
);

create table if not exists progress (
  id bigserial primary key,
  user_id uuid references profiles(id) on delete cascade,
  lesson_key text not null,
  score integer default 0,
  max_score integer default 0,
  bonus integer default 0,
  created_at timestamptz default now(),
  unique(user_id, lesson_key)
);

create table if not exists daily_completions (
  id bigserial primary key,
  user_id uuid references profiles(id) on delete cascade,
  day date not null,
  score integer default 0,
  total integer default 0,
  created_at timestamptz default now(),
  unique(user_id, day)
);

create table if not exists reviews (
  id bigserial primary key,
  user_id uuid references profiles(id) on delete cascade,
  lesson_key text not null,
  created_at timestamptz default now(),
  unique(user_id, lesson_key)
);

create table if not exists essays (
  id bigserial primary key,
  user_id uuid references profiles(id) on delete cascade,
  lesson_key text,
  prompt text,
  essay text,
  score integer,
  feedback text,
  improvements jsonb default '[]'::jsonb,
  word_count integer,
  created_at timestamptz default now()
);

create table if not exists teacher_lessons (
  id bigserial primary key,
  teacher_id uuid references profiles(id) on delete cascade,
  class_code text,
  subject text not null,
  unit_title text not null,
  lesson_title text not null,
  learn_text text,
  questions jsonb default '[]'::jsonb,
  published boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists classes (
  id bigserial primary key,
  code text unique not null,
  teacher_id uuid references profiles(id) on delete cascade,
  name text,
  created_at timestamptz default now()
);

create table if not exists class_challenges (
  id bigserial primary key,
  teacher_id uuid references profiles(id) on delete cascade,
  class_code text,
  title text not null,
  description text,
  target_lessons integer default 5,
  xp_reward integer default 100,
  created_at timestamptz default now()
);

create table if not exists app_settings (
  id integer primary key default 1,
  leaderboard_enabled boolean default true,
  updated_at timestamptz default now()
);
insert into app_settings (id, leaderboard_enabled) values (1, true)
  on conflict (id) do nothing;

create table if not exists admin_audit (
  id bigserial primary key,
  actor_id uuid,
  action text,
  target_id uuid,
  created_at timestamptz default now()
);

create table if not exists valid_class_codes (
  code text primary key,
  created_at timestamptz default now()
);

-- ---------- RPC FUNCTIONS ----------

-- Refill hearts to 5 (called on load)
create or replace function refill_hearts()
returns integer language plpgsql security definer as $$
declare new_hearts integer;
begin
  update profiles set hearts = 5 where id = auth.uid() returning hearts into new_hearts;
  return new_hearts;
end;
$$;

-- Deduct one heart, floor at 0
create or replace function deduct_heart()
returns integer language plpgsql security definer as $$
declare new_hearts integer;
begin
  update profiles
    set hearts = greatest(0, coalesce(hearts,5) - 1)
    where id = auth.uid()
    returning hearts into new_hearts;
  return new_hearts;
end;
$$;

-- Add XP to today's daily counter and lifetime total
create or replace function bump_daily_xp(amount integer)
returns void language plpgsql security definer as $$
begin
  update profiles
    set xp = coalesce(xp,0) + amount,
        daily_xp = case when daily_xp_date = current_date then coalesce(daily_xp,0) + amount else amount end,
        daily_xp_date = current_date,
        last_active = current_date
    where id = auth.uid();
end;
$$;

-- Get leaderboard with optional hidden users
create or replace function get_leaderboard(p_limit integer default 100, p_include_hidden boolean default false)
returns table(username text, display_name text, xp integer, role text, leaderboard_opt_out boolean)
language sql security definer as $$
  select username, display_name, xp, role, leaderboard_opt_out
  from profiles
  where p_include_hidden or leaderboard_opt_out = false
  order by xp desc nulls last
  limit p_limit;
$$;

-- Get app settings
create or replace function get_app_settings()
returns table(leaderboard_enabled boolean)
language sql security definer as $$
  select leaderboard_enabled from app_settings where id = 1;
$$;

-- Admin: set leaderboard enabled
create or replace function admin_set_leaderboard_enabled(p_enabled boolean)
returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Admin only';
  end if;
  update app_settings set leaderboard_enabled = p_enabled, updated_at = now() where id = 1;
  insert into admin_audit (actor_id, action) values (auth.uid(), 'leaderboard_' || p_enabled::text);
end;
$$;

-- Admin: update any profile field
create or replace function admin_update_profile(
  p_user_id uuid,
  p_role text default null,
  p_xp integer default null,
  p_hearts integer default null,
  p_streak integer default null,
  p_freezes integer default null,
  p_leaderboard_hidden boolean default null
) returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Admin only';
  end if;
  update profiles set
    role = coalesce(p_role, role),
    xp = coalesce(p_xp, xp),
    hearts = coalesce(p_hearts, hearts),
    streak = coalesce(p_streak, streak),
    streak_freezes = coalesce(p_freezes, streak_freezes),
    leaderboard_opt_out = coalesce(p_leaderboard_hidden, leaderboard_opt_out)
    where id = p_user_id;
  insert into admin_audit (actor_id, action, target_id) values (auth.uid(), 'update_profile', p_user_id);
end;
$$;

-- Admin: reset progress
create or replace function admin_reset_progress(p_user_id uuid)
returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Admin only';
  end if;
  delete from progress where user_id = p_user_id;
  delete from daily_completions where user_id = p_user_id;
  delete from reviews where user_id = p_user_id;
  update profiles set xp=0, streak=0, daily_xp=0, daily_xp_date=null, hearts=5, last_active=null
    where id = p_user_id;
  insert into admin_audit (actor_id, action, target_id) values (auth.uid(), 'reset_progress', p_user_id);
end;
$$;

-- Teacher: reset a student in their class
create or replace function teacher_reset_student(p_student_id uuid)
returns void language plpgsql security definer as $$
declare my_code text;
begin
  select code into my_code from classes where teacher_id = auth.uid() limit 1;
  if my_code is null then raise exception 'No class'; end if;
  if not exists (select 1 from profiles where id = p_student_id and class_code = my_code) then
    raise exception 'Student not in your class';
  end if;
  delete from progress where user_id = p_student_id;
  delete from daily_completions where user_id = p_student_id;
  delete from reviews where user_id = p_student_id;
  update profiles set xp=0, streak=0, daily_xp=0, daily_xp_date=null, hearts=5, last_active=null
    where id = p_student_id;
end;
$$;

-- ---------- ROW LEVEL SECURITY ----------

alter table profiles enable row level security;
alter table progress enable row level security;
alter table daily_completions enable row level security;
alter table reviews enable row level security;
alter table essays enable row level security;
alter table teacher_lessons enable row level security;
alter table classes enable row level security;
alter table class_challenges enable row level security;

-- Profiles: everyone can read, only self can update (admins bypass via service role)
create policy "profiles_read" on profiles for select using (true);
create policy "profiles_update_self" on profiles for update using (auth.uid() = id);

-- Progress: owner only
create policy "progress_own" on progress for all using (auth.uid() = user_id);

-- Daily completions: owner only
create policy "daily_own" on daily_completions for all using (auth.uid() = user_id);

-- Reviews: owner only
create policy "reviews_own" on reviews for all using (auth.uid() = user_id);

-- Essays: owner + teachers of their class
create policy "essays_own" on essays for all using (auth.uid() = user_id);

-- Teacher lessons: public read of published, teachers manage their own
create policy "teacher_lessons_read" on teacher_lessons for select using (
  published = true or teacher_id = auth.uid()
);
create policy "teacher_lessons_write" on teacher_lessons for insert
  with check (teacher_id = auth.uid());
create policy "teacher_lessons_update" on teacher_lessons for update
  using (teacher_id = auth.uid());
create policy "teacher_lessons_delete" on teacher_lessons for delete
  using (teacher_id = auth.uid());

-- Classes: public read by code, teachers manage their own
create policy "classes_read" on classes for select using (true);
create policy "classes_write" on classes for insert with check (teacher_id = auth.uid());

-- Challenges: public read, teachers manage their own
create policy "challenges_read" on class_challenges for select using (true);
create policy "challenges_write" on class_challenges for insert with check (teacher_id = auth.uid());

-- ---------- STORAGE ----------
-- No storage buckets needed — all content is text/JSON.

-- ---------- EDGE FUNCTIONS (deploy separately) ----------
-- These live in supabase/functions/<name>/index.ts
--
-- explain-answer        → POST { question, correct, chosen } → { why }
-- grade-essay           → POST { essay, prompt, min, max } → { score, feedback, improvements[] }
-- request-password-reset→ POST { username } → { ok } or { error }
-- confirm-password-reset→ POST { username, code, new_password } → { ok } or { error }
