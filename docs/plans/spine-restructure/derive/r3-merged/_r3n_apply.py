"""Round 3n: apply the confirmed findings of r3m-convergence-sol (R3M-001..003)."""
import os

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', '..'))
L = 'docs/requirements/low-level-requirements.toml'
S = 'docs/requirements/system-requirements.toml'


def sub(path, old, new):
    s = open(path, encoding='utf-8').read()
    assert s.count(old) == 1, (path, old[:70], s.count(old))
    open(path, 'w', encoding='utf-8', newline='').write(s.replace(old, new))


# R3M-001: SR-011 states the same predicate as LLR-011 (today's comparisons, P-01).
sub(S, "a periodic schedule re-reads on the first run whose date falls in a later calendar period of its kind (day, week, month or year) than the last completed full re-read;",
       "a periodic schedule re-reads on the first run whose date falls in a calendar period of its kind other than that of the last completed full re-read, a period being a day, a week within a calendar year (so the year's end divides a week), a month or a year, and for the daily and yearly schedules a later one only, so a clock set back re-reads under a weekly or monthly schedule and not under a daily or yearly one;")
sub(S, 'permutations = """schedule=set{every-run,periodic,never}; period=set{same,next,later}; last_reread_interrupted=bool; @pairwise"""',
       'permutations = """schedule=set{every-run,periodic,never}; period=set{same,next,later,earlier}; week_split_by_year_end=bool; last_reread_interrupted=bool; @pairwise"""')

# R3M-002: LLR-035 leaves the re-read decision to LLR-011, so a never schedule stays never.
sub(L, "the last full re-read is treated as never completed (so a re-read is due)",
       "the last full re-read is treated as never completed (so a periodic or every-run schedule re-reads, while a never schedule still does not, LLR-011)")
sub(L, "The accepted costs: one full re-read, and",
       "The accepted costs: one full re-read under any schedule but never, and")

# R3M-003: the dry run tests the claim the way a reader does, so it predicts a busy refusal.
sub(L, "It reads published records as a reader does (LLR-123), takes no claim,",
       "It first tests the claim the way a reader does (LLR-159): opening the claim file in a way its holder's open excludes and closing it at once, never creating it; a claim found held, or a test that fails, is reported for every named saved state as the removal reports a claim it cannot take (LLR-092). It reads published records as a reader does (LLR-123), takes no lasting claim,")
sub(L, "Because it takes no claim it cannot see a writer that holds one: a removal it reports as proceeding may still be refused as busy when it runs.",
       "What it cannot predict is a changing operation that starts after the preview, or a store changed between the preview and the removal.")
sub(L, "Taking the claim lost: a preview that waits for or blocks a running backup is worse than one that cannot predict a busy refusal, which the real removal reports anyway.",
       "Holding the claim for the preview lost: a preview that waits for or blocks a running backup is worse than a momentary test, which predicts an existing holder without holding anything.")
print('round 3n applied')
