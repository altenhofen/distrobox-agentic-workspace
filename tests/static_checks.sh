#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

required=(
  "$repo_root/ansible/host_vars/localhost.yml.example"
  "$repo_root/ansible/site.yml"
  "$repo_root/ansible/verify.yml"
  "$repo_root/ansible/destroy.yml"
  "$repo_root/ansible/group_vars/all/harnesses.yml"
)
for path in "${required[@]}"; do
  test -f "$path" || { echo "missing required file: $path" >&2; exit 1; }
done

grep -qxF 'ansible/host_vars/localhost.yml' "$repo_root/.gitignore"
grep -q "ads_localhost_vars_file.stat.mode == '0600'" "$repo_root/ansible/roles/prerequisites/tasks/main.yml"
grep -q 'no_log: true' "$repo_root/ansible/roles/environment/tasks/main.yml"
grep -q 'ads_repositories_mount_enabled: false' "$repo_root/ansible/group_vars/all/main.yml"
grep -q 'ads_ai_jail_enabled: true' "$repo_root/ansible/group_vars/all/main.yml"
grep -q 'exec ai-jail' "$repo_root/ansible/roles/harnesses/templates/harness-wrapper.sh.j2"
grep -q 'agent is not allowlisted' "$repo_root/ansible/roles/buzz/templates/buzz-agent-create.sh.j2"
grep -q 'ads_ai_jail_agent_state: true' "$repo_root/ansible/host_vars/localhost.yml.example"
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
grep -q 'repository: 1jehuang/jcode' "$repo_root/ansible/group_vars/all/harnesses.yml"
grep -q 'version: v0.81.7' "$repo_root/ansible/group_vars/all/harnesses.yml"
grep -q 'sha256sum --check' "$repo_root/ansible/roles/harnesses/tasks/install_github_release.yml"
grep -q 'archive_companion' "$repo_root/ansible/roles/harnesses/tasks/install_github_release.yml"
grep -q 'JCODE_NO_TELEMETRY: "1"' "$repo_root/ansible/group_vars/all/harnesses.yml"
grep -q 'exec /usr/bin/buzz' "$repo_root/ansible/roles/buzz/templates/buzz-wrapper.sh.j2"
grep -q 'ads_buzz_appimage_aur_package: buzz-appimage' "$repo_root/ansible/group_vars/all/main.yml"
grep -q 'ads_buzz_appimage_aur_package: buzz-appimage' "$repo_root/ansible/host_vars/localhost.yml.example"
grep -q 'pacman, -Q, "{{ ads_buzz_appimage_aur_package }}"' "$repo_root/ansible/roles/buzz/tasks/main.yml"
grep -q 'ads_ai_jail_deny_host_home: true' "$repo_root/ansible/host_vars/localhost.yml.example"
grep -q 'ads_buzz_relay_url: ""' "$repo_root/ansible/host_vars/localhost.yml.example"
grep -q 'ads_buzz_private_key: ""' "$repo_root/ansible/host_vars/localhost.yml.example"
grep -q 'ads_git_user_name: ""' "$repo_root/ansible/host_vars/localhost.yml.example"
grep -q 'Remove stale Buzz environment' "$repo_root/ansible/roles/environment/tasks/main.yml"
if rg -q 'Build and install Buzz CLI|ads_buzz_source_revision' "$repo_root/ansible"; then
  echo 'separately built Buzz CLI configuration remains' >&2
  exit 1
fi
grep -q 'sha256sum --check' "$repo_root/ansible/roles/buzz/tasks/main.yml"
if rg -q 'ads_buzz_(aur|acp_aur)_package' "$repo_root/ansible"; then
  echo 'nonexistent Buzz AUR package configuration remains' >&2
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
