# Complete Workflow

This guide describes the complete operator workflow for creating, configuring,
using, updating, verifying, and removing the agentic Distrobox sandbox.

## 1. Host prerequisites

Use a Linux host with:

- Distrobox
- Podman, or another Distrobox-compatible container manager
- Ansible
- Network access to the Arch repositories, AUR, npm, and configured Buzz relay
- Unprivileged user namespaces and Bubblewrap support for ai-jail

Confirm the core host tools:

```bash
distrobox --version
podman --version
ansible-playbook --version
```

The default container image is Arch-based and provisioning installs `yay`,
Bubblewrap, shared development tools, enabled agent harnesses, ai-jail, Buzz,
and Buzz ACP inside the Distrobox.

## 2. Prepare local configuration

Run these commands from the repository root:

```bash
cp ansible/host_vars/localhost.yml.example ansible/host_vars/localhost.yml
chmod 600 ansible/host_vars/localhost.yml
```

The generated localhost file is ignored by Git.

### Configure localhost variables

Edit `ansible/host_vars/localhost.yml` and set the Buzz credentials, Git
identity, package pins, and hardening settings:

```yaml
ads_buzz_relay_url: https://relay.example.example
ads_buzz_private_key: nsec1_replace_me
ads_buzz_auth_tag: ""
ads_buzz_source_revision: dad5a33865fc81a2e55b3b60746632f615ec1e3a
ads_buzz_sprig_release_tag: sprig-latest

ads_git_user_name: Your Name
ads_git_user_email: you@example.com

ads_ai_jail_enabled: true
ads_ai_jail_aur_package: ai-jail-bin
ads_ai_jail_network: true
ads_ai_jail_agent_state: true
ads_container_pids_limit: 512
ads_container_memory: 8g
ads_container_cpus: 4
ads_container_allow_host_loopback: false
ads_container_network_backend: pasta
```

Buzz variables are loaded into a mode-`0600` shell fragment in the persistent
box home. The private key and authorization tag are suppressed from Ansible
output. Git identity is written only to the box user's global Git configuration.

Set both `ads_buzz_relay_url` and `ads_buzz_private_key`, or leave both empty.
Set both Git identity variables, or leave both empty. Partial pairs fail validation.

### Configure host variables

Edit `ansible/host_vars/localhost.yml`:

```yaml
---
ads_box_name: agentic
ads_image: quay.io/toolbx/arch-toolbox:latest
ads_box_home: /home/me/distrobox-agent
ads_unshare_all: true
ads_container_pids_limit: 512
ads_container_memory: 8g
ads_container_cpus: 4
ads_container_allow_host_loopback: false
ads_container_network_backend: pasta

ads_enabled_harnesses:
  - opencode
  - codex
  - claudecode
  - pi
  - omp
  - jcode

ads_repositories_mount_enabled: false
ads_repositories_host_path: /home/me/src
ads_repositories_box_path: /workspace
ads_repositories_mount_read_only: true

ads_buzz_connectivity_check: false
```

`ads_box_home` must be absolute. It persists across box recreation and is not
removed by the destroy playbook.

Repository mounting is disabled by default. When enabled, the host source must
be an existing absolute directory. Set `ads_repositories_mount_read_only: true`
if agents should not modify it.

## 3. Install Ansible requirements

```bash
cd ansible
ansible-galaxy collection install -r collections/requirements.yml
```

The requirements file is currently empty because the implementation uses
Ansible built-ins, but keeping this step in automation makes future collection
additions predictable.

## 4. Run preflight checks

From the repository root:

```bash
bash tests/static_checks.sh
```

This checks required files and security defaults, then runs syntax checks for
all playbooks when `ansible-playbook` is available.

For an explicit syntax check:

```bash
cd ansible
ansible-playbook --syntax-check site.yml
```

## 5. Provision the sandbox

From `ansible/`:

```bash
ansible-playbook site.yml
```

The playbook performs these stages:

1. Loads the untracked localhost variables and validates paired settings.
2. Validates host commands, paths, and harness selection.
3. Creates the persistent box home.
4. Creates the named Arch Distrobox if it does not already exist.
5. Installs base development packages and `yay`.
6. Installs ai-jail and Bubblewrap when enabled.
7. Creates the private Buzz environment and box-only Git configuration.
8. Installs each enabled harness from the declarative catalog.
9. Creates ai-jail wrappers for enabled harness commands.
10. Compiles the Buzz relay CLI from a pinned source revision, installs the
    checksum-pinned prebuilt Sprig/ACP bundle, removes desktop Buzz packages,
    and installs `buzz-agent-create`.
11. Runs local verification without contacting the relay by default.

Provisioning is convergent: re-run the same command after configuration changes
or to install upstream updates.

### Run a partial convergence

```bash
ansible-playbook site.yml --tags base
ansible-playbook site.yml --tags harnesses
ansible-playbook site.yml --tags harness_codex
ansible-playbook site.yml --tags ai_jail
ansible-playbook site.yml --tags buzz
ansible-playbook site.yml --tags environment
ansible-playbook site.yml --tags verify
```

### Refresh dependency pins

From the repository root, `update_deps.sh` refreshes the pinned Buzz commit,
Sprig checksums, and JCode release tag. It requires authenticated `gh` access
for GitHub API lookups and `curl` for release checksum sidecars:

```bash
./update_deps.sh --dry-run
./update_deps.sh
```

Partial runs assume the box and their prerequisite tools already exist. Use the
complete `site.yml` workflow for a fresh machine or after destroying the box.

## 6. Enter and use the sandbox

```bash
distrobox enter agentic
```

Replace `agentic` if `ads_box_name` was changed.

Interactive shells prepend `~/.local/bin` to `PATH`. The managed harness names
therefore resolve to wrappers rather than the raw npm executables:

```text
codex
  -> managed harness wrapper
  -> ai-jail
  -> raw Codex executable
```

The default wrapper grants network access and the selected harness's credential
state. It does not inherit the complete shell environment. Configured Buzz
variables are individually forwarded. Mandatory deny paths hide Distrobox's host
view, `distrobox-host-exec`, and common Docker and Podman sockets.

Disable or tighten this behavior in `ansible/host_vars/localhost.yml`, then re-run `site.yml`:

```yaml
ads_ai_jail_network: false
ads_ai_jail_agent_state: false
ads_ai_jail_enabled: false
```

Disabling ai-jail removes the managed harness wrappers, allowing the underlying
commands to resolve normally.

## 7. Use Buzz directly

Inside the sandbox, verify local CLI availability without contacting the relay:

```bash
buzz --help
buzz-acp --help
```

List channels using configured credentials:

```bash
buzz channels list
```

Buzz writes structured JSON to standard output and errors to standard error.

To make relay verification part of provisioning, set:

```yaml
ads_buzz_connectivity_check: true
```

Then run:

```bash
cd ansible
ansible-playbook site.yml --tags buzz
```

The connectivity task uses `no_log` so credentials cannot enter Ansible output.
A local Buzz installation check and a relay/authentication check are distinct:
local checks can pass even when the relay is unreachable or credentials are
invalid.

## 8. Launch a Buzz agent

Inside the sandbox, pass an installed command and optional arguments:

```bash
buzz-agent-create codex
buzz-agent-create claude --model sonnet
```

The launcher resolves the command without a shell, sets `BUZZ_ACP_AGENT_COMMAND`
and optional `BUZZ_ACP_AGENT_ARGS`, and replaces itself with `buzz-acp`.

The complete default launch path is:

```text
buzz-agent-create codex
  -> executable resolution
  -> private Buzz environment
  -> buzz-acp
  -> managed codex wrapper
  -> ai-jail
  -> raw codex executable
```

Missing executables and comma-containing arguments fail before credentials are
loaded. Managed harness names resolve through their ai-jail wrappers on `PATH`.

## 9. Verify an existing installation

```bash
cd ansible
ansible-playbook verify.yml
```

Verification checks:

- Distrobox availability and box entry
- Shared development commands
- ai-jail when enabled
- The Buzz agent launcher
- Each enabled harness's catalog verification command
- Buzz AppImage package and Buzz CLI availability

Relay access remains skipped unless `ads_buzz_connectivity_check` is true.

## 10. Update the sandbox

Pull or edit the desired repository changes, review configuration, and converge:

```bash
cd ansible
ansible-playbook site.yml
ansible-playbook verify.yml
```

Harness package sources, versions, install methods, executable names, and
verification commands are centralized in:

```text
ansible/group_vars/all/harnesses.yml
```

Override machine-specific choices in `host_vars/localhost.yml`; do not put
secrets there.

## 11. Destroy and rebuild

Review the configured target first:

```bash
cd ansible
ansible-playbook destroy.yml --check
```

Remove the named Distrobox:

```bash
ansible-playbook destroy.yml
```

The playbook validates and displays the concrete box name before removal. It
does not delete the persistent box home or a mounted repository directory.

Rebuild with:

```bash
ansible-playbook site.yml
```

Backup and restore remain intentionally deferred. `backup.yml` exits without
copying state or secrets:

```bash
ansible-playbook backup.yml
```

## 12. Troubleshooting

### A harness bypasses ai-jail

Check command resolution inside an interactive box shell:

```bash
type -a codex
printf '%s\n' "$PATH"
```

The first result should be under `~/.local/bin`. Re-run the environment,
ai-jail, and harness roles, or run the full playbook:

```bash
cd ansible
ansible-playbook site.yml
```

### A raw Distrobox shell can access the host home

This is inherent to Distrobox and is not disabled by `--home` or
`--unshare-all`. Podman rejects overlaying the automatic home bind with a masking
mount. Managed harnesses deny the host home through ai-jail and should access
code only through the explicit `/workspace` mount. Do not provide raw
`distrobox enter` access to untrusted users; use a dedicated host account or VM
when the interactive shell itself must be confined.

### ai-jail cannot start Bubblewrap

Confirm Bubblewrap exists inside the box:

```bash
distrobox enter agentic -- bwrap --version
```

If the host blocks unprivileged user namespaces, follow the host distribution's
guidance for enabling them. Do not disable ai-jail security mechanisms merely to
hide an unexplained host-policy failure.

### Buzz agent creation reports missing credentials

Ensure `ansible/host_vars/localhost.yml` contains both Buzz variables, has mode
`0600`, and provisioning has been rerun:

```bash
chmod 600 ansible/host_vars/localhost.yml
cd ansible
ansible-playbook site.yml --tags environment,buzz
```

Never print or paste `BUZZ_PRIVATE_KEY` into diagnostic output.

### Provisioning fails on an upstream package or source build

Upstream package names and release channels can change. Review:

- `ads_ai_jail_aur_package`
- `ads_buzz_source_revision`
- `ads_buzz_sprig_release_tag`
- `ads_buzz_sprig_assets`
- `ansible/group_vars/all/harnesses.yml`

Override a package only after confirming the new source and executable. Then
converge the affected role and run `verify.yml`.

## 13. Security checklist

Before launching agents:

- Keep `ansible/host_vars/localhost.yml` mode `0600` and outside Git.
- Restrict access to `buzz-agent-create`; it accepts any installed executable.
- Review every enabled harness and its upstream package source.
- Keep `ads_unshare_all: true` unless broader Distrobox integration is required.
- Enable repository mounts only for explicit source directories.
- Prefer read-only repository mounts when write access is unnecessary.
- Understand that `ads_ai_jail_network: true` permits network access.
- Understand that `ads_ai_jail_agent_state: true` exposes that harness's login state.
- Keep `ads_ai_jail_deny_host_home: true` for every Buzz-managed harness.
- Do not use `--inherit-env` in ai-jail wrappers.
- Treat Distrobox and ai-jail as useful layers, not complete isolation from
  hostile code or kernel vulnerabilities.
- Use a disposable virtual machine for genuinely hostile workloads.
