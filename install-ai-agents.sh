#!/usr/bin/env bash
set -Eeuo pipefail

# Install AI agent tooling on Ubuntu:
# - Hermes Agent + built-in Hermes Web Dashboard
# - OpenAI Codex CLI
# - Claude Code
# - OpenCode
# - Herdr
#
# This script installs software only.
# It does NOT configure API keys, Ollama Cloud, LINE, Slack, domains,
# firewall rules, or always-on systemd services.
#
# Usage:
#   sudo bash install-ai-agents.sh
#
# Optional:
#   sudo AGENT_USER=agent CLAUDE_CHANNEL=stable bash install-ai-agents.sh

AGENT_USER="${AGENT_USER:-agent}"
CLAUDE_CHANNEL="${CLAUDE_CHANNEL:-stable}"
AGENT_HOME="/home/${AGENT_USER}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32mOK:\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

trap 'die "Installation failed at line ${LINENO}. Review the error above."' ERR

[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo bash $0"
[[ -r /etc/os-release ]] || die "Cannot detect operating system."

# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID}" == "ubuntu" ]] || die "This script supports Ubuntu only. Detected: ${ID:-unknown}"

export DEBIAN_FRONTEND=noninteractive

run_agent() {
  runuser -u "${AGENT_USER}" -- env \
    HOME="${AGENT_HOME}" \
    USER="${AGENT_USER}" \
    LOGNAME="${AGENT_USER}" \
    SHELL=/bin/bash \
    PATH="${AGENT_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    bash -lc "$1"
}

log "1/9 — Installing system dependencies"
apt-get update
apt-get install -y \
  bash \
  ca-certificates \
  curl \
  ffmpeg \
  git \
  jq \
  openssl \
  python3 \
  python3-venv \
  ripgrep \
  tmux \
  unzip \
  xz-utils

log "2/9 — Creating dedicated user: ${AGENT_USER}"
if id "${AGENT_USER}" >/dev/null 2>&1; then
  ok "User ${AGENT_USER} already exists"
else
  useradd --create-home --shell /bin/bash "${AGENT_USER}"
  ok "Created user ${AGENT_USER}"
fi

install -d -o "${AGENT_USER}" -g "${AGENT_USER}" -m 0755 \
  "${AGENT_HOME}/.local/bin" \
  "${AGENT_HOME}/workspaces"

touch "${AGENT_HOME}/.bashrc"
chown "${AGENT_USER}:${AGENT_USER}" "${AGENT_HOME}/.bashrc"

if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "${AGENT_HOME}/.bashrc"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${AGENT_HOME}/.bashrc"
fi

log "3/9 — Installing Hermes Agent"
run_agent '
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
    | bash -s -- --skip-browser
'
ok "Hermes installed; the Web Dashboard is included in Hermes"

log "4/9 — Installing OpenAI Codex CLI"
run_agent '
  curl -fsSL https://chatgpt.com/codex/install.sh | sh
'
ok "Codex installed"

log "5/9 — Installing Claude Code (${CLAUDE_CHANNEL})"
run_agent "
  curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_CHANNEL}
"
ok "Claude Code installed"

log "6/9 — Installing OpenCode"
run_agent '
  curl -fsSL https://opencode.ai/install | bash
'
ok "OpenCode installed"

log "7/9 — Installing Herdr"
run_agent '
  curl -fsSL https://herdr.dev/install.sh | sh
'
ok "Herdr installed"

log "8/9 — Verifying commands"
COMMANDS=(hermes codex claude opencode herdr)
FAILED=0

for command_name in "${COMMANDS[@]}"; do
  if run_agent "command -v ${command_name}" >/dev/null 2>&1; then
    path="$(run_agent "command -v ${command_name}")"
    ok "${command_name}: ${path}"
  else
    warn "${command_name} was not found in ${AGENT_USER}'s PATH"
    FAILED=1
  fi
done

log "9/9 — Writing setup guide"
cat > "${AGENT_HOME}/AI-AGENT-NEXT-STEPS.md" <<'EOF'
# AI Agent — Next steps

Log in as the dedicated agent user:

```bash
sudo -iu agent
```

## 1. Verify installations

```bash
hermes doctor
codex --version
claude --version
opencode --version
herdr --version
```

## 2. Configure Hermes with Ollama Cloud

Run the interactive provider setup:

```bash
hermes model
```

Use your Ollama Cloud API key and select the required cloud model.

You can also run the full setup wizard:

```bash
hermes setup
```

## 3. Start the Hermes Web Dashboard privately

The dashboard contains credentials and administrative controls. Bind it to localhost:

```bash
hermes dashboard --host 127.0.0.1 --port 9119 --no-open
```

Access it from your computer through SSH forwarding:

```bash
ssh -p 22022 -L 9119:127.0.0.1:9119 root@VPS_IP
```

Then open:

```text
http://127.0.0.1:9119
```

## 4. Configure LINE and Slack

Run:

```bash
hermes gateway setup
```

Prepare these credentials first:

### LINE Messaging API

- Channel access token
- Channel secret
- Allowed LINE user/group IDs
- Public HTTPS webhook URL

### Slack bot

- Bot token
- App-level token
- Signing secret where required
- Allowed Slack user/channel IDs

## 5. Authenticate coding agents

```bash
codex
claude
opencode
```

Each command starts its own authentication or provider setup.

## 6. Start Herdr

```bash
cd ~/workspaces
herdr
```

Use Herdr to run and retain Codex, Claude Code, and OpenCode terminal sessions.

## Security

- Do not run agents as root.
- Do not expose port 9119 directly to the internet.
- Do not give the agent access to `/root`, Dokploy data, or the Docker socket.
- Configure LINE and Slack allowlists before enabling shell-capable tools.
EOF

# Replace the default username in the generated guide when customized.
sed -i "s/sudo -iu agent/sudo -iu ${AGENT_USER}/g" \
  "${AGENT_HOME}/AI-AGENT-NEXT-STEPS.md"

chown "${AGENT_USER}:${AGENT_USER}" \
  "${AGENT_HOME}/AI-AGENT-NEXT-STEPS.md"

printf '\n============================================================\n'
printf 'AI agent software installation completed\n\n'
printf 'Dedicated user: %s\n' "${AGENT_USER}"
printf 'Workspace:      %s/workspaces\n' "${AGENT_HOME}"
printf 'Setup guide:    %s/AI-AGENT-NEXT-STEPS.md\n\n' "${AGENT_HOME}"
printf 'Continue with:\n'
printf '  sudo -iu %s\n' "${AGENT_USER}"
printf '  cat ~/AI-AGENT-NEXT-STEPS.md\n'
printf '============================================================\n'

if (( FAILED != 0 )); then
  warn "One or more verification checks failed. Re-login as ${AGENT_USER} and inspect PATH before configuration."
  exit 1
fi
