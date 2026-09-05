#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

required=(
  "$repo_root/.env.example"
  "$repo_root/ansible/site.yml"
  "$repo_root/ansible/verify.yml"
  "$repo_root/ansible/destroy.yml"
  "$repo_root/ansible/group_vars/all/harnesses.yml"
)
for path in "${required[@]}"; do
  test -f "$path" || { echo "missing required file: $path" >&2; exit 1; }
done

grep -qxF '.env' "$repo_root/.gitignore"
grep -q 'no_log: true' "$repo_root/ansible/roles/environment/tasks/main.yml"
grep -q 'ads_repositories_mount_enabled: false' "$repo_root/ansible/group_vars/all/main.yml"
grep -q 'ads_ai_jail_enabled: true' "$repo_root/ansible/group_vars/all/main.yml"
grep -q 'exec ai-jail' "$repo_root/ansible/roles/harnesses/templates/harness-wrapper.sh.j2"
grep -q 'agent is not allowlisted' "$repo_root/ansible/roles/buzz/templates/buzz-agent-create.sh.j2"
grep -q 'AI_JAIL_AGENT_STATE' "$repo_root/.env.example"
grep -q 'Apply ai-jail environment overrides' "$repo_root/ansible/roles/configuration/tasks/main.yml"
grep -q "'/run/host' in ads_ai_jail_deny_paths" "$repo_root/ansible/roles/prerequisites/tasks/main.yml"
grep -q 'ads.hardening' "$repo_root/ansible/roles/distrobox/tasks/main.yml"
grep -q -- '--network=pasta' "$repo_root/ansible/roles/distrobox/tasks/main.yml"
if grep -q 'slirp4netns' "$repo_root/ansible/roles/distrobox/tasks/main.yml"; then
  echo 'removed Podman slirp4netns backend is still configured' >&2
  exit 1
fi
grep -q 'package: "@oh-my-pi/pi-coding-agent"' "$repo_root/ansible/group_vars/all/harnesses.yml"
grep -q 'version: 18.1.10' "$repo_root/ansible/group_vars/all/harnesses.yml"
grep -q 'pi-tui@18.1.10' "$repo_root/ansible/group_vars/all/harnesses.yml"

if command -v ansible-playbook >/dev/null 2>&1; then
  (
    cd "$repo_root/ansible"
    ansible-playbook --syntax-check site.yml
    ansible-playbook --syntax-check verify.yml
    ansible-playbook --syntax-check destroy.yml
    ansible-playbook --syntax-check backup.yml
  )
else
  echo 'ansible-playbook unavailable; structural checks passed, syntax checks skipped'
fi
