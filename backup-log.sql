-- Never lose a submission: every new, replaced or deleted submission is copied
-- into submissions_log first. Run once in Supabase: SQL Editor > New query > paste > Run.

create table if not exists public.submissions_log (
  id         bigint generated always as identity primary key,
  logged_at  timestamptz not null default now(),
  action     text not null,          -- insert, update, delete, or snapshot
  week       int,
  name       text,
  row_data   jsonb not null          -- the full submission (PIN removed)
);

-- Nobody can read or change the log from the website. Only you (SQL editor) and the backup job can.
alter table public.submissions_log enable row level security;
revoke all on public.submissions_log from anon, authenticated;

create or replace function public.log_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare r jsonb;
begin
  r := to_jsonb(case when tg_op = 'DELETE' then old else new end) - 'pin' - 'pin_hash';
  insert into public.submissions_log (action, week, name, row_data)
  values (lower(tg_op), (r->>'week')::int, r->>'name', r);
  return null;
end
$fn$;

drop trigger if exists submissions_log_trg on public.submissions;
create trigger submissions_log_trg
after insert or update or delete on public.submissions
for each row execute function public.log_submission();

-- Save a copy of everything already submitted (only the first time).
insert into public.submissions_log (action, week, name, row_data)
select 'snapshot', s.week, s.name, to_jsonb(s) - 'pin' - 'pin_hash'
  from public.submissions s
 where not exists (select 1 from public.submissions_log where action = 'snapshot');

-- How many submissions are now protected:
select count(*) as submissions_logged from public.submissions_log;
