---
name: capture-preference
description: Record a new standing preference in CLAUDE.md. Use when the user states a durable rule about how they want work done — phrased as "from now on", "always", "never", "going forward", "stop doing X", "in future", or a correction they clearly mean to apply beyond the current task. Handles branching off master mid-task, choosing the right subsection, merging with an existing bullet instead of appending, and opening the separate PR.
---

# Capture a standing preference

A standing preference is a durable instruction about *how work is done*, not
about the current task. It lands in `CLAUDE.md` § Working With This User, in its
own commit and its own PR against `master` — never bundled into whatever feature
branch happens to be checked out.

## 1. Confirm it is actually a standing preference

It is, if it would still apply on an unrelated task next month.

It is not, if it is scoped to the current change ("use port 3001 here"). Those
belong in the code or the owning `docs/` file. If it is a repo convention rather
than a working preference — a placement rule, a naming rule, a service
invariant — it belongs in the owning doc under `docs/`, not here. Say so and
stop.

## 2. Branch off master without disturbing in-flight work

This normally fires mid-task, with a feature branch checked out and possibly
dirty. Do not commit onto that branch.

```bash
git -C <repo> stash push -u -m capture-preference   # only if the tree is dirty
git -C <repo> fetch origin master
git -C <repo> checkout -B docs/claude-<short-slug> origin/master
```

Record which branch you came from and whether you stashed — step 6 returns
there.

## 3. Find the right home, and prefer merging over appending

`CLAUDE.md` § Working With This User has four subsections:

| Subsection | Covers |
| --- | --- |
| Communication | Response style, timestamps, verification, when to confirm or ask |
| Shell and commands | What is safe to run, shell syntax constraints, where commands go |
| Git and PRs | Branching, commits, PR content, merging, review follow-through |
| Repo conventions | File organization and repo-wide engineering rules |

**Read the whole section before writing anything.** If an existing bullet
already covers the ground, extend or reword that bullet rather than adding a
new one. The list reached 21 bullets with two redundant pairs — "don't guess
when a check is one call away" alongside "don't assert unchecked facts", and
"confirm before acting" alongside "ask before assuming" — precisely because
each was appended without checking the others. A merge is the better outcome
and keeps the diff one line either way.

If it genuinely belongs in no existing subsection, say so rather than forcing
it; a fifth subsection is a reasonable outcome, silently misfiling is not.

## 4. Match the established voice

- Open with a bolded lead clause naming the rule, then the reasoning.
- Second person, imperative. "Never merge PRs." not "PRs should not be merged."
- Give the *why* when it is not self-evident, and the concrete failure it
  prevents when there is one.
- One bullet. If it needs three, it is probably a doc, not a preference.

## 5. Commit

One file, one insertion — this is what every previous preference commit looks
like.

```bash
git -C <repo> add CLAUDE.md
git -C <repo> commit -F /tmp/msg    # never a heredoc; this shell is fish
```

Subject line: `docs(claude): standing preference <on|to|against> <thing>`.

Add a body only when the rule needs justification that does not fit the bullet.

Confirm the shape before pushing:

```bash
git -C <repo> show --stat HEAD      # expect: CLAUDE.md | 1 +
```

## 6. Open the PR and go back

```bash
git -C <repo> push -u origin docs/claude-<short-slug>
```

Open a PR against `master`. It is docs-only, so it needs no test steps — that is
the one standing exemption. Subscribe to its activity. Do not merge it.

Then restore the original context:

```bash
git -C <repo> checkout <original-branch>
git -C <repo> stash pop             # only if step 2 stashed
```

Tell the user the preference PR is open and separate, and carry on with the task
that was interrupted.
