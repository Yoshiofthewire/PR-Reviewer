# PR Reviewer

Reviews every open, non-draft pull request in repositories you own or that
belong to an organization you are in. Each pull request is reviewed by the
`security` and `code-review` personas, each maintaining its own comment.

| Persona | Skill | Looks for |
| --- | --- | --- |
| `security` | `security-audit` | Exploitable defects the change introduces |
| `code-review` | `code-review` | Repository standards, code smells, and conformance to the PR spec |

The `simplicity` (`ponytail-review`) and `hostile` (`hostile-review`) personas
were removed: they never cleared, so the gate was never passable.

The persona re-reviews when the head SHA changes or when anyone replies after
its last comment. A reply is any of the three places GitHub keeps them — an
issue comment, an inline comment on the diff, or a submitted review — because
answering a finding in the Files-changed tab has to count as answering it. An
inline reply reaches the persona with the `path:line` it hangs off; a review
reaches it with its state; a bodiless approval is not a reply. Still not
triggers: editing the pull request description or title, and anything at all on
a closed pull request.

It marks each prior finding RESOLVED, UNRESOLVED, or WITHDRAWN, so a correct
rebuttal can clear a finding without a commit. When nothing actionable remains
it reports CLEARED. A summary comment tracks the tally across both personas.

Code review keeps Standards and Spec findings separate. It uses the supplied PR
diff against the base, the PR title/description, and repository spec files.
Referenced external issues are unavailable in the isolated runner; the review
states that limitation, or "no spec available" when there is no spec. Both axes
run sequentially in one session because delegation is disabled. Repository
standards are read as data, including quarantined instruction files.

The reviewer posts comments only and never approves a pull request.

For separate, explicit approval of all open, non-draft Dependabot PRs, use
`approve-dependabot.sh` with an authenticated `gh` account that can review the
repository. It defaults to the current repository, skips archived repositories,
and continues after individual approval failures. It does not merge PRs.

```sh
DRY_RUN=1 ./approve-dependabot.sh owner/repo  # preview
./approve-dependabot.sh owner/repo           # approve
```

## Setup

Requires bash 4+, `gh`, `jq`, `git`, and the `codex` CLI. Keep `claude`
installed and authenticated for automatic fallback. `curl` is needed for the
isolation check and to post findings to a hand-off board. macOS ships bash 3.2, which cannot run this;
`brew install bash` is enough, and the script re-execs itself under it wherever
your PATH happens to put it. `gh` must be logged in with `repo` and `read:org`:

```sh
gh auth login
codex login
./verify_isolation.sh   # proves the sandboxing still holds; costs a few tokens
DRY_RUN=1 ./pr-reviewer.sh
./install.sh
```

`install.sh` enables a systemd user timer that runs a tick every five minutes.
Run one on demand with `systemctl --user start pr-reviewer.service`, and read the
logs with `journalctl --user -u pr-reviewer.service`.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `REPOSITORIES` | empty | Comma-separated allowlist; empty means all |
| `EXCLUDE_REPOSITORIES` | empty | Comma-separated denylist; wins over the allowlist |
| `MAX_PRS_PER_TICK` | 5 | Pull requests reviewed per tick; already-reviewed ones do not count, the rest are logged and deferred |
| `MAX_DIFF_BYTES` | 180000 | Diff truncation threshold in bytes; truncation is stated in the comment |
| `DRY_RUN` | unset | Print comment bodies instead of posting them |
| `HANDOFF_URL` | empty | Hand-off board base URL; unset means deliver full findings to a local file instead |
| `HANDOFF_TOKEN` | empty | Bearer token for that board; both must be set for board delivery |
| `REVIEW_BACKEND` | `codex` | `codex` (Claude fallback) or `claude` (Claude only); `--backend codex\|claude` overrides it. For the timer, set it in `~/.config/pr-reviewer/env`, which overrides the unit |
| `CODEX_MODEL` | `gpt-6.1-sol` | Primary review model |
| `CLAUDE_MODEL` | `claude-opus-5-5` | Claude fallback model |
| `SECURITY_SKILL_FILE` | `$CODEX_HOME/skills/security-audit/SKILL.md` (home defaults to `~/.codex`) | Trusted local skill supplied to Codex; install its companion files alongside it |
| `CODE_REVIEW_SKILL_FILE` | `$CODEX_HOME/skills/code-review/SKILL.md` (home defaults to `~/.codex`) | Trusted code-review skill supplied to Codex; install `code-review` in Claude's user skills for fallback too |
| `REASONING_EFFORT` | `high` | Effort for every persona |
| `WORK_DIR` | `$XDG_RUNTIME_DIR/pr-reviewer`, or `/tmp/pr-reviewer` | Throwaway checkout directory; basename must be `pr-reviewer` because the reaper refuses to delete from directories it cannot confirm are its own |

An unchanged pull request costs nothing beyond four API calls; only a changed
one spends tokens.

Codex is tried first for each review. If it is missing, fails, or returns no
final message, the runner retries once with Claude. If both fail, no persona
comment is replaced and the tick continues with other PRs. Findings do not
trigger fallback. Comments and delivered reports identify the model that
actually produced the review. Both runners use `REASONING_EFFORT`.

## How PR code is contained

Each review reads a throwaway shallow clone of the PR head. Codex starts in
a separate empty directory so checkout configuration cannot load. It ignores
user configuration and execution rules, suppresses automatic instruction and
skill discovery, and receives only the active persona's trusted skill explicitly. Plugins,
apps, hooks, browser/computer tools, web search, and delegation are disabled.
The command environment inherits no operator variables or login-shell setup.

Codex uses the OS read-only sandbox with approval set to `never`: it can run
commands to read context, but cannot write files or access the network through
those commands. This differs from Claude's tool allowlist, which exposes no
shell at all. `verify_isolation.sh` exercises the production Codex invocation
against hostile instruction/config files and attempts actual writes and
network access. Run it on every operator machine; sandbox support is required.

Claude retains this invocation:

```
claude -p --no-session-persistence --strict-mcp-config --setting-sources user \
       --tools "Skill,Read,Grep,Glob" --model <m> --effort <e> --system-prompt <sp>
```

Three properties this relies on were measured, not assumed, and are re-checked by
`./verify_isolation.sh`:

- `--safe-mode` strips user skills, so it cannot be used here.
- Without `--setting-sources user`, a `CLAUDE.md` inside the checkout is obeyed
  as instructions.
- `--tools` alone does not restrict MCP tools; without `--strict-mcp-config` a
  reviewer is offered Gmail, Firebase deploy, and Playwright code execution.

Belt and braces: `CLAUDE.md`, `AGENTS.md`, `.claude/`, `.codex/`, and `.agents/` in the
checkout are renamed with a `.quarantined` suffix before review, so they are
readable as data but are not auto-loaded. The runner owns the comment envelope
and model signature; neither reviewer receives GitHub write tools.

On public repositories the `security` persona posts severity and file only.
Posting an unfixed exploitable finding to a public comment is disclosure. The
full finding is delivered out of band instead, and the comment names wherever it
actually went — never an empty promise that something exists.

Delivery order:

1. **The hand-off board (MySlop)**, when `HANDOFF_URL` and `HANDOFF_TOKEN` are
   set. One folder per pull request (`pr-reviewer-<owner>-<repo>-<number>`); each
   review appends a post to it, so the folder reads as that pull request's
   history. The comment links to the folder. The board is login-gated for the
   human, and its content **expires seven days after the last post** — it is a
   delivery channel, not the record.
2. **A local file**, when the board is unconfigured, when a board call fails, or
   under `DRY_RUN` (posting is an outward-facing write, so a dry run never makes
   one). Written to
   `${XDG_STATE_HOME:-$HOME/.local/state}/pr-reviewer/<owner>-<repo>-<number>-<sha>.md`,
   mode 600, before redaction. A dry run says on stderr where the post would have
   gone.

If both routes fail, the comment says the report could not be delivered and the
tick reports a failure.

Set the board credentials where the timer can read them but other users cannot:

```sh
mkdir -p ~/.config/pr-reviewer
cat >~/.config/pr-reviewer/env <<'EOF'
HANDOFF_URL=https://myslop.example
HANDOFF_TOKEN=<the UUID minted for this machine>
EOF
chmod 600 ~/.config/pr-reviewer/env
```

`systemd/pr-reviewer.service` reads that file if it exists and starts fine
without it.

Every invocation takes an flock at `${XDG_STATE_HOME:-$HOME/.local/state}/pr-reviewer.lock`
before doing any work, whether started by the timer or run directly, so a slow
tick cannot have its checkout deleted out from under it by a concurrent one. A
second concurrent run exits quietly.

## Development

```sh
./test_pr_reviewer.sh
for f in pr-reviewer.sh lib/review-core.sh test_pr_reviewer.sh install.sh verify_isolation.sh; do
  shellcheck -S warning "$f"
done
```
