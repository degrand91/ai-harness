# Pattern: when generated ids are positional, regeneration is a migration

**Seen in:** a mission on a private project (an upstream data update)

## The shape

A build script derives stable-looking ids from data — record `c01`…`c20`, ordered by distance from a reference point. Other records reference those ids. The upstream data changes; you re-run the script; every id still exists, every reference still resolves, every test still passes.

And the meaning has moved. An upstream version bump added three records and shifted all sixteen existing ids. A record written for beginners, which pointed at an easy entry by id, silently pointed at a **much harder** entry instead. No error, no warning, no failing test, and a beginner just gets the hard version.

## Why nothing caught it

Referential integrity held: `c05` existed before and after. Only the *semantics* changed. Existence checks cannot see that, and the codebase's one guard (a "written for vX, catalogue is vY" banner) was skipped because the affected record had no version field at all — the field was optional, so its absence looked like "no opinion" rather than "unverified".

## Do this instead

1. **Diff old against new by identity, not by id.** For each old id, find the nearest new record and compare its substance (here: the record's contents). Matching substance at a small distance is a safe re-point; anything else needs a human.
2. **Make the version field required wherever a guard depends on it.** An optional field that disables a safety warning when omitted is worse than no field. A test now fails if any referencing record lacks a version or disagrees with its catalogue.
3. **Treat "all tests still pass" after a data regeneration as no signal at all.** The tests were written against the old semantics. Regeneration needs its own before/after comparison, run deliberately.
4. **Prefer ids anchored to something stable.** This project already orders ids from a fixed anchor rather than from bounds that can change, precisely so an unrelated bounds change cannot reshuffle them. That instinct was right; it just does not survive upstream adding records.

## Cheap version

Before copying regenerated data in, dump `id → one-line summary` for old and new, and diff the two files. Thirty seconds, and it is the only thing that would have caught this.
