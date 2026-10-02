-- Problem reports from the game's pause screen: a note, the race and settings
-- as JSON, and a small JPEG screenshot (base64). Private: only the "st"
-- function (service role) writes them; read them from the dashboard.
create table if not exists public.reports (
  id bigserial primary key,
  player_id uuid references public.players(id) on delete set null,
  created_at timestamptz not null default now(),
  version text,
  note text,
  tags text[] not null default '{}',
  state jsonb not null default '{}'::jsonb,
  image text,
  bytes int not null default 0
);
alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;
create index if not exists reports_player_time_idx on public.reports(player_id, created_at desc);
