-- Each player's saved game (garage, career, season, progress), private: only
-- the "st" function (service role) reads or writes it.
create table if not exists public.saves (
  player_id uuid primary key references public.players(id) on delete cascade,
  data jsonb not null,
  bytes int not null default 0,
  updated_at timestamptz not null default now()
);
alter table public.saves enable row level security;

-- One-time codes to move an account to a new phone (valid 24 hours).
create table if not exists public.transfers (
  code text primary key,
  player_id uuid not null references public.players(id) on delete cascade,
  expires_at timestamptz not null
);
alter table public.transfers enable row level security;
create index if not exists transfers_player_idx on public.transfers(player_id);

-- Streaks shown on profiles.
alter table public.players add column if not exists streak int not null default 0;

revoke all on public.saves from anon, authenticated;
revoke all on public.transfers from anon, authenticated;
grant select (streak) on public.players to anon;
