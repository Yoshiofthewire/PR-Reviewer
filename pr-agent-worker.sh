#!/usr/bin/env bash
# Runs inside the pr-agent container: review every job pr-reviewer.sh has marked
# ready. The container holds the model key and nothing else; no GitHub token.
set -uo pipefail
for ready in "${PR_AGENT_JOBS:-/jobs}"/job.*/ready; do
  job=${ready%/ready}
  [[ -e $ready && ! -e $job/done ]] || continue
  (cd "$job/repo" && LOCAL__REVIEW_PATH="$job/review.md" \
    timeout "${PR_AGENT_RUN_TIMEOUT:-540}" python /app/pr_agent/cli.py --pr_url base review) \
    >"$job/log" 2>&1
  touch "$job/done"
done
exit 0
