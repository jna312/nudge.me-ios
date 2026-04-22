# Backlog

Ideas parked for later. Not prioritized. Each entry should have enough context that future-you remembers why it matters and what the shape of the solution would be.

---

## AI cleanup pass for voice dictation

**Problem:** Speech recognition often produces messy transcripts — mishears names, drops punctuation, mangles times ("tomorrow at four" → "tomorrow for"). `ReminderParser` works well on clean input but struggles with these.

**Idea:** After dictation completes, optionally send the raw transcript through an LLM to clean it up before parsing.

**Design choice to make when picking this up:**
- **Always run** the cleanup (simple UX, but pays latency + API cost on every capture, even clean ones) vs
- **Fallback only** when `ReminderParser` returns low-confidence results (no time detected, ambiguous title) — zero cost on the happy path, LLM only steps in when it'd actually help.

Leaning toward fallback-only.

**Open questions:**
- Which provider? (no AI client wired up in the app yet as of 2026-04-22)
- Scope: just fix transcription errors, or also restructure casual input ("tell mom happy birthday tomorrow" → title + due time)?
- Offline behavior — fall back to raw transcript if no network.
- Privacy: voice transcripts contain personal data; consider on-device options (Apple Intelligence) before reaching for cloud LLMs.
