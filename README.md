# PR Reviewer

Reviews every open, non-draft pull request in repositories you own or that
belong to an organization you are in. Each pull request is reviewed by three
personas, and each persona posts and maintains its own comment.

| Persona | Skill | Looks for |
| --- | --- | --- |
| `security` | `security-audit` | Exploitable defects the change introduces |
| `simplicity` | `ponytail-review` | Over-engineering worth deleting |
| `hostile` | `hostile-review` | Whatever a reviewer who hates the change would say |

A persona re-reviews when the head SHA changes or when anyone replies after its
last comment. It marks each prior finding RESOLVED, UNRESOLVED, or WITHDRAWN, so
a correct rebuttal can clear a finding without a commit. When nothing actionable
remains it reports CLEARED. A fourth comment tracks how many personas have
cleared.

This never approves a pull request. It posts comments only, so no bot can
satisfy branch protection and merging stays your decision.

## Setup

Requires `gh`, `jq`, `git`, and the `claude` CLI. `gh` must be logged in with
`repo` and `read:org`:

```sh
gh auth login
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
| `MAX_PRS_PER_TICK` | 5 | Pull requests reviewed per tick; the rest are logged and deferred |
| `MAX_DIFF_BYTES` | 180000 | Diff truncation threshold in bytes; truncation is stated in the comment |
| `DRY_RUN` | unset | Print comment bodies instead of posting them |
| `CLAUDE_MODEL` | `opus` | Model for every persona |
| `REASONING_EFFORT` | `high` | Effort for every persona |
| `WORK_DIR` | `$XDG_RUNTIME_DIR/pr-reviewer`, or `/tmp/pr-reviewer` | Throwaway checkout directory; basename must be `pr-reviewer` because the reaper refuses to delete from directories it cannot confirm are its own |

An unchanged pull request costs nothing beyond two API calls; only a changed one
spends tokens.

## How PR code is contained

Each review runs against a throwaway shallow clone of the PR head, with the
persona invoked as:

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

Belt and braces: `CLAUDE.md`, `AGENTS.md`, `.claude/`, and `.cursor/` in the
checkout are renamed with a `.quarantined` suffix before review, so they are
readable as data but are not auto-loaded. There is no Bash, Write, or network
tool, so a successful injection can only produce misleading text; the runner, not
the model, owns the comment envelope and signature.

On public repositories the `security` persona posts severity and file only.
Posting an unfixed exploitable finding to a public comment is disclosure.

## Development

```sh
./test_pr_reviewer.sh
shellcheck -S warning pr-reviewer.sh lib/review-core.sh test_pr_reviewer.sh
```
