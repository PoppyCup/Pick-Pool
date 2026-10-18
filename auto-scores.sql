-- Auto-update live scores from ESPN every 2 minutes.
-- Run once in Supabase: SQL Editor > New query > paste > Run.
-- Manual entry in the Admin tab still works; the next sync just overwrites live/final games with ESPN's numbers.

create extension if not exists http with schema extensions;
create extension if not exists pg_cron;

create or replace function public.sync_espn_scores()
returns int
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  j jsonb; evs jsonb; wk int; e jsonb; c jsonb; st jsonb;
  hn text; an text; hs int; aws int; state text; per int; clk text; stat text;
  g record; n int := 0;
begin
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '15');
  select content::jsonb into j
  from extensions.http_get('https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard');

  evs := coalesce(j->'events', j->'leagues'->0->'events', '[]'::jsonb);
  wk  := coalesce(j->'week'->>'number', j->'leagues'->0->'week'->>'number')::int;

  for e in select value from jsonb_array_elements(evs) loop
    c  := e->'competitions'->0;
    st := coalesce(c->'status', e->'status');
    state := st->'type'->>'state';
    continue when state is null or state not in ('in', 'post');

    select x->'team'->>'displayName', nullif(x->>'score', '')::int into hn, hs
      from jsonb_array_elements(c->'competitors') x where x->>'homeAway' = 'home';
    select x->'team'->>'displayName', nullif(x->>'score', '')::int into an, aws
      from jsonb_array_elements(c->'competitors') x where x->>'homeAway' = 'away';

    per := nullif(st->>'period', '')::int;
    clk := st->>'displayClock';
    stat := case
      when state = 'post' then 'Final'
      when st->'type'->>'name' = 'STATUS_HALFTIME' then 'Halftime'
      when st->'type'->>'name' = 'STATUS_END_PERIOD' then 'End Q' || per
      when per > 4 then 'OT ' || clk
      else 'Q' || per || ' ' || clk
    end;

    -- Match to the pool's schedule by team names (ignores case/punctuation), preferring ESPN's week.
    select s.week, s.away, s.home into g
      from public.schedule s
     where lower(regexp_replace(s.home, '[^a-zA-Z0-9]', '', 'g')) = lower(regexp_replace(hn, '[^a-zA-Z0-9]', '', 'g'))
       and lower(regexp_replace(s.away, '[^a-zA-Z0-9]', '', 'g')) = lower(regexp_replace(an, '[^a-zA-Z0-9]', '', 'g'))
     order by (s.week = wk) desc nulls last, s.week desc
     limit 1;
    continue when not found;

    insert into public.results (week, away, home, away_score, home_score, final, status)
    values (g.week, g.away, g.home, aws, hs, state = 'post', stat)
    on conflict (week, away, home) do update
      set away_score = excluded.away_score,
          home_score = excluded.home_score,
          final      = excluded.final,
          status     = excluded.status;
    n := n + 1;
  end loop;
  return n;
end
$fn$;

-- Only the scheduler (and you, in the SQL editor) can run it; not callable from the website.
revoke execute on function public.sync_espn_scores() from public, anon, authenticated;

-- Every 2 minutes. Replaces the job if you run this script again.
select cron.unschedule(jobid) from cron.job where jobname = 'espn-scores';
select cron.schedule('espn-scores', '*/2 * * * *', 'select public.sync_espn_scores()');

-- Pull scores right now. The number returned = games updated.
select public.sync_espn_scores() as games_updated;
