#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

required=(
  "$repo_root/ansible/host_vars/localhost.yml.example"
  "$repo_root/ansible/site.yml"
  "$repo_root/ansible/verify.yml"
  "$repo_root/ansible/destroy.yml"
  "$repo_root/ansible/roles/podman_runtime/tasks/main.yml"
  "$repo_root/ansible/roles/runtime_image/tasks/main.yml"
  "$repo_root/ansible/group_vars/all/harnesses.yml"
  "$repo_root/update_deps.sh"
  "$repo_root/buzz-agent-draft-create.sh"
  "$repo_root/buzz-agent-run.sh"
)
for path in "${required[@]}"; do
  test -f "$path" || { echo "missing required file: $path" >&2; exit 1; }
done

grep -qxF 'ansible/host_vars/localhost.yml' "$repo_root/.gitignore"
grep -q "ads_localhost_vars_file.stat.mode == '0600'" "$repo_root/ansible/roles/prerequisites/tasks/main.yml"
grep -q 'no_log: true' "$repo_root/ansible/roles/environment/tasks/main.yml"
grep -q 'ads_workspace_mount_enabled: false' "$repo_root/ansible/group_vars/all/main.yml"
grep -q -- '--read-only' "$repo_root/ansible/roles/runtime_image/tasks/main.yml"
grep -q -- '--cap-drop=ALL' "$repo_root/ansible/roles/runtime_image/tasks/main.yml"
grep -q -- '--security-opt=no-new-privileges' "$repo_root/ansible/roles/runtime_image/tasks/main.yml"
grep -q -- '--network=pasta' "$repo_root/ansible/roles/podman_runtime/tasks/main.yml"
grep -q 'exec ai-jail' "$repo_root/ansible/roles/harnesses/templates/harness-wrapper.sh.j2"
grep -q 'Usage: buzz-agent-create AGENT_COMMAND' "$repo_root/ansible/roles/buzz/templates/buzz-agent-create.sh.j2"
grep -q 'wss://' "$repo_root/ansible/roles/buzz/templates/buzz-agent-create.sh.j2"
grep -q 'package: "@oh-my-pi/pi-coding-agent"' "$repo_root/ansible/group_vars/all/harnesses.yml"
grep -q 'repository: 1jehuang/jcode' "$repo_root/ansible/group_vars/all/harnesses.yml"
grep -q 'sha256sum --check' "$repo_root/ansible/roles/buzz/tasks/main.yml"
grep -q 'sha256sum --check' "$repo_root/ansible/roles/harnesses/tasks/install_github_release.yml"
grep -q 'exec /usr/local/libexec/ads/buzz' "$repo_root/ansible/roles/buzz/templates/buzz-wrapper.sh.j2"
grep -q 'container exists' "$repo_root/buzz-agent-draft-create.sh"
grep -q 'buzz-agent-create' "$repo_root/buzz-agent-run.sh"
test -x "$repo_root/update_deps.sh"
test -x "$repo_root/buzz-agent-draft-create.sh"
test -x "$repo_root/buzz-agent-run.sh"
grep -q -- '--check' "$repo_root/update_deps.sh"

if rg -n 'distrobox|ads_box_|ads_repositories_' "$repo_root/ansible" "$repo_root/README.md" "$repo_root/WORKFLOW.md" "$repo_root/SPEC.md"; then
  echo 'obsolete Distrobox configuration remains' >&2
  exit 1
fi

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
