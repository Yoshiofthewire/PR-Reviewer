# PR-Reviewer: gh, git, jq and the two model CLIs. Build context is the repo root.
FROM node:22-bookworm-slim@sha256:18052396bf1d0c6e0a8c58181b5c1457da19409efbd5032a3f4d86974e74d13c

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git jq util-linux bubblewrap \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g --no-fund --no-audit @openai/codex@0.167.2 @anthropic-ai/claude-code@2.1.322 \
 && npm cache clean --force

# Private repositories are fetched with gh's own login.
RUN git config --system credential.https://github.com.helper '!gh auth git-credential' \
 && install -d -o node -g node /jobs /state /status

# The node image already has uid 1000 as "node".
USER node
ENV HOME=/home/node
WORKDIR /app
COPY --chown=node:node pr-reviewer.sh verify_isolation.sh tick-loop.sh ./
COPY --chown=node:node lib ./lib
CMD ["./tick-loop.sh", "./pr-reviewer.sh"]
