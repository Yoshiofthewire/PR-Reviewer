# PR Reviewer

## Purpose

- Review open pull requests across owned and organization repositories from a
  local machine, through the `security` persona reviewer.
- Resolve each finding over time as the author pushes fixes or replies.

## Ownership

- `lib/review-core.sh` owns pure logic: filtering, state codec, re-review
  decision, rendering, redaction. No network, no writes.
- `pr-reviewer.sh` owns GitHub I/O, checkout lifecycle, and persona dispatch.
- `test_pr_reviewer.sh` owns dependency-free checks. It stubs `gh`, `git`, and
  `claude` on `PATH`; it never reaches the network.
- `verify_isolation.sh` owns proof that the sandboxing still holds. It costs
  tokens and is never run by the tick or the test suite.
- `systemd/` (Linux) and `launchd/` (macOS) own the unit definitions;
  `install.sh` branches on `uname -s` and owns installing whichever applies.
- `README.md` owns operator setup.

## Local Contracts

- The persona invocation is load-bearing and must stay exactly
  `--no-session-persistence --strict-mcp-config --setting-sources user --tools "Skill,Read,Grep,Glob"`.
  Dropping `--strict-mcp-config` restores Gmail, Firebase, and Playwright code
  execution, which `--tools` does not filter. Dropping `--setting-sources user`
  lets a `CLAUDE.md` in the checkout issue instructions. Adding `--safe-mode`
  removes the skills. Change any of these only with a fresh
  `./verify_isolation.sh` run as evidence.
- Never call `gh pr review --approve`. Comments only.
- Review state lives in the comment body; GitHub is the only source of truth.
  Add no local state file.
- Keep exactly one comment per persona per pull request, plus one summary.
- Findings carry severity, a changed-file location, failure mode, fix direction,
  and verification.
- Sign every comment `<model> using <skill> on behalf of Yoshi`.
- On public repositories the `security` persona publishes severity and file only.
- Never review archived repositories or draft pull requests.
- The tick needs bash 4+ (`mapfile`, associative arrays) and `flock`. macOS has
  neither by default, so `pr-reviewer.sh` re-execs under a Homebrew bash and
  refuses to run unserialised if `flock` is absent. Keep both guards ahead of
  the `source` and the lock respectively, or macOS fails obscurely instead of
  loudly.
- Keep the test suite free of GNU-only invocations. BSD `wc -l` pads its count
  and BSD `stat` takes different flags, so both go through the `lines` and
  `mode` helpers.
- `WORK_DIR` basename must be exactly `pr-reviewer`; the reaper refuses to delete
  from directories it cannot confirm are its own, because earlier versions would
  happily wipe operator files if pointed anywhere broad.

## Work Guidance

- Reach for `gh`, `jq`, `git`, and `claude`. Add no other dependencies.
- Run without `set -e`; propagate errors with explicit `|| return 1`.
- Isolate failures per pull request. One bad pull request must not end the tick.
- Ticks must be idempotent. Reap stale checkouts rather than assuming the last
  run finished.
- Never silently truncate. A capped tick logs what it deferred; a truncated diff
  says so in the comment.

## Verification

- `./test_pr_reviewer.sh`
- `shellcheck -S warning` on each of `pr-reviewer.sh`, `lib/review-core.sh`,
  `test_pr_reviewer.sh`, `install.sh`, and `verify_isolation.sh` individually.
  Linting them together previously masked a real SC2034 warning.
- `bash -n pr-reviewer.sh lib/review-core.sh install.sh verify_isolation.sh`
- `./verify_isolation.sh` after any change to the persona invocation.
- `DRY_RUN=1 ./pr-reviewer.sh` before any behaviour change goes live.

## Child DOX Index

- None.
