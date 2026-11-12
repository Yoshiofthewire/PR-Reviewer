# pr-agent plus git, which its local provider needs. Build context is the repo root.
FROM pragent/pr-agent:0.50.0@sha256:8978ae8f025883159ccc6f5bec51e6553347c77d14dbc5ca4bf3bb4a8726eb43

RUN apt-get update && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/* && install -d -o 1000 -g 1000 /jobs
COPY tick-loop.sh pr-agent-worker.sh /scripts/
ENTRYPOINT ["/scripts/tick-loop.sh", "/scripts/pr-agent-worker.sh"]
