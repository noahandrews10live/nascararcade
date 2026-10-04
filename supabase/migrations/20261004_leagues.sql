-- Private leagues: a name, a join code, a schedule of rounds (one track each),
-- members, and each member's result in each round. Private: only the "st"
-- function (service role) reads or writes them; players see their own leagues
-- through it.
create table if not exists public.leagues (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  owner_id uuid not null references public.players(id) on delete cascade,
  rounds int[] not null,           -- track index per round
  length int not null default 1,   -- race length setting
  weekly boolean not null default true, -- a round a week (else all open now)
  created_at timestamptz not null default now()
);
alter table public.leagues enable row level security;

create table if not exists public.league_members (
  league_id uuid not null references public.leagues(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (league_id, player_id)
);
alter table public.league_members enable row level security;
create index if not exists league_members_player_idx on public.league_members(player_id);

create table if not exists public.league_results (
  league_id uuid not null references public.leagues(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  round int not null,
  place int not null,
  field int not null,
  points int not null,
  race_ms int,
  best_lap_ms int,
  updated_at timestamptz not null default now(),
  primary key (league_id, player_id, round)
);
alter table public.league_results enable row level security;

revoke all on public.leagues from anon, authenticated;
revoke all on public.league_members from anon, authenticated;
revoke all on public.league_results from anon, authenticated;
