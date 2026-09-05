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
cp .env.example .env
chmod 600 .env
cp ansible/host_vars/localhost.yml.example ansible/host_vars/localhost.yml
```

Both generated files are ignored by Git.

### Configure `.env`

Edit `.env` and set the Buzz credentials and Git identity:

```dotenv
BUZZ_RELAY_URL=https://relay.example.example
BUZZ_PRIVATE_KEY=nsec1_replace_me
# BUZZ_AUTH_TAG=optional_owner_attestation

GIT_USER_NAME="Your Name"
GIT_USER_EMAIL="you@example.com"

AI_JAIL_ENABLED=true
AI_JAIL_AUR_PACKAGE=ai-jail-bin
AI_JAIL_NETWORK=true
AI_JAIL_AGENT_STATE=true
AI_JAIL_DENY_PATHS=/run/host:/usr/bin/distrobox-host-exec:/run/podman:/var/run/docker.sock:/run/docker.sock

DISTROBOX_PIDS_LIMIT=512
DISTROBOX_MEMORY=8g
DISTROBOX_CPUS=4
DISTROBOX_ALLOW_HOST_LOOPBACK=false
```

Buzz variables are loaded into a mode-`0600` shell fragment in the persistent
box home. The private key and authorization tag are suppressed from Ansible
output. Git identity is written only to the box user's global Git configuration.

The ai-jail variables override matching Ansible settings. Boolean values are
true for `1`, `true`, `yes`, or `on`, case-insensitively; other values are false.

Set both `BUZZ_RELAY_URL` and `BUZZ_PRIVATE_KEY`, or omit both. Set both Git
identity variables, or omit both. Partial pairs fail validation.

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

### Configure the Buzz agent allowlist

The allowlist controls which harness configurations `buzz-agent-create` may
launch:

```yaml
ads_buzz_agent_allowlist:
  codex:
    command: codex
    args: []
  claudecode:
    command: claude
    args: []
```

Each allowlist key must also be present in `ads_enabled_harnesses`. Commands are
bare executable names. Arguments are fixed by the operator and cannot contain
commas because `BUZZ_ACP_AGENT_ARGS` is comma-delimited. A caller cannot replace
the command or append arbitrary arguments.

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

1. Loads `.env` and applies supported environment overrides.
2. Validates host commands, paths, harness selection, and agent allowlist.
3. Creates the persistent box home.
4. Creates the named Arch Distrobox if it does not already exist.
5. Installs base development packages and `yay`.
6. Installs ai-jail and Bubblewrap when enabled.
7. Creates the private Buzz environment and box-only Git configuration.
8. Installs each enabled harness from the declarative catalog.
9. Creates ai-jail wrappers for enabled harness commands.
10. Installs Buzz CLI, Buzz ACP, and `buzz-agent-create`.
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

Disable or tighten this behavior in `.env`, then re-run `site.yml`:

```dotenv
AI_JAIL_NETWORK=false
AI_JAIL_AGENT_STATE=false
AI_JAIL_ENABLED=false
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

## 8. Launch an allowlisted Buzz agent

Inside the sandbox, inspect the permissible agent names:

```bash
buzz-agent-create --list
```

Launch one permitted configuration:

```bash
buzz-agent-create codex
```

The launcher validates the logical name before reading credentials. It then sets
the fixed `BUZZ_ACP_AGENT_COMMAND` and optional `BUZZ_ACP_AGENT_ARGS`, and replaces
itself with `buzz-acp`.

The complete default launch path is:

```text
buzz-agent-create codex
  -> allowlist validation
  -> private Buzz environment
  -> buzz-acp
  -> managed codex wrapper
  -> ai-jail
  -> raw codex executable
```

An unknown name fails closed and prints the permissible names. The command does
not accept caller-provided executable names or extra agent arguments.
When ai-jail is enabled, the generated Buzz configuration uses the wrapper's
absolute path rather than relying on `PATH`, so Buzz ACP cannot accidentally
select the raw harness binary.

## 9. Verify an existing installation

```bash
cd ansible
ansible-playbook verify.yml
```

Verification checks:

- Distrobox availability and box entry
- Shared development commands
- ai-jail when enabled
- The Buzz agent launcher and every allowlist entry
- Each enabled harness's catalog verification command
- Buzz CLI availability

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

### ai-jail cannot start Bubblewrap

Confirm Bubblewrap exists inside the box:

```bash
distrobox enter agentic -- bwrap --version
```

If the host blocks unprivileged user namespaces, follow the host distribution's
guidance for enabling them. Do not disable ai-jail security mechanisms merely to
hide an unexplained host-policy failure.

### Buzz agent creation reports missing credentials

Ensure `.env` contains both Buzz variables, has mode `0600`, and provisioning
has been rerun:

```bash
chmod 600 .env
cd ansible
ansible-playbook site.yml --tags environment,buzz
```

Never print or paste `BUZZ_PRIVATE_KEY` into diagnostic output.

### An allowlisted agent is rejected

Confirm its key appears in both `ads_enabled_harnesses` and
`ads_buzz_agent_allowlist`, then run:

```bash
cd ansible
ansible-playbook site.yml --tags harnesses,buzz
```

### Provisioning fails on an AUR or npm package

Upstream package names and release channels can change. Review:

- `ads_ai_jail_aur_package`
- `ads_buzz_aur_package`
- `ads_buzz_acp_aur_package`
- `ansible/group_vars/all/harnesses.yml`

Override a package only after confirming the new source and executable. Then
converge the affected role and run `verify.yml`.

## 13. Security checklist

Before launching agents:

- Keep `.env` mode `0600` and outside Git.
- Keep the Buzz allowlist limited to required agent configurations.
- Review every enabled harness and its upstream package source.
- Keep `ads_unshare_all: true` unless broader Distrobox integration is required.
- Enable repository mounts only for explicit source directories.
- Prefer read-only repository mounts when write access is unnecessary.
- Understand that `AI_JAIL_NETWORK=true` permits network access.
- Understand that `AI_JAIL_AGENT_STATE=true` exposes that harness's login state.
- Do not use `--inherit-env` in ai-jail wrappers.
- Treat Distrobox and ai-jail as useful layers, not complete isolation from
  hostile code or kernel vulnerabilities.
- Use a disposable virtual machine for genuinely hostile workloads.
