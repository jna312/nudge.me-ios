# nudge.me

## Always run the verifier

The **verifier** is a subagent pass that checks whether a plan or change is architecturally sound and fits the existing code. Run it at every checkpoint, always:

1. **After planning, before writing code.** Hand the plan to the verifier and wait for its read before touching files.
2. **After writing code, before reporting done.** Verifier reviews the diff against the surrounding architecture.
3. **After implementation is complete** (end of a task / before handing back).
4. **After `git push`** (and after opening/updating a PR).
5. Any other clear lifecycle boundary — err on the side of running it.

### How to run the verifier

Spawn a general-purpose subagent with a prompt shaped like:

> You are the verifier. Read the relevant files in this repo and assess whether [the plan / this diff / this implementation] is architecturally sound and fits the existing code. Look for: mismatches with existing patterns, duplicated responsibility, broken invariants, layering violations, dead paths, concurrency/ownership issues, things that will rot. Report: (1) verdict — sound / needs changes / wrong approach, (2) specific concerns with file:line references, (3) concrete fixes. Be blunt; surface problems, do not rubber-stamp.

Give the verifier the plan text or the diff (`git diff`, `git diff --staged`, or `git diff <base>...HEAD`) plus pointers to the files it should read.

### Responding to verifier output

- Sound → proceed.
- Needs changes → fix the specific concerns, then re-run the verifier on the updated state.
- Wrong approach → stop, surface it, re-plan with the user before continuing.

Do not skip the verifier to save time. Do not self-verify in the main conversation — it must be a separate subagent call so the review is independent.

## Build pipeline

Xcode Cloud workflow `Default` (configured in App Store Connect) archives the `nudge.me` scheme and uploads to App Store Connect. Triggered **manually** via App Store Connect → Xcode Cloud → Builds → **Start Build**. Auto-trigger on push is not wired up — Apple's webhook provisioning for this repo is broken and not worth fixing. Post-Actions currently empty; builds land in App Store Connect but aren't auto-distributed to a TestFlight group.

To ship a build: push to `main`, then click Start Build in App Store Connect. After ~10–15 min processing it appears in the TestFlight tab.
