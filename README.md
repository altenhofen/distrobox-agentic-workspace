# Agentic Distrobox Sandbox

An Ansible-managed Distrobox that provides an isolated, repeatable Linux workspace for running several agent harnesses and Block's Buzz CLI. It is intended to keep agent tooling, their dependencies, and relay credentials out of the host while retaining Distrobox's normal terminal integration.

> Provisioning is implemented under `ansible/`. Review and override the harness
> catalog before production use because upstream package names and release channels
> can change independently of this repository.

## Goals

- Create a named, reproducible Distrobox for agent-oriented work.
- Install a curated set of agent harnesses and their shared developer tooling.
- Install the `buzz` CLI for machine-readable collaboration with a Buzz relay.
- Keep every operator setting, including secrets, in the untracked
  `ansible/host_vars/localhost.yml` file.
- Support repeatable create, update, verification, backup, and removal workflows.

## What gets installed

### Base environment

- An Arch-based Distrobox, created with Podman or another Distrobox-supported container manager.
- Shell, Git, build tools, Python, Node.js, Rust/Cargo, and common CLI utilities.
- `yay` for AUR packages.
- A configured non-root user matching the host user.

### Agent tooling

- The first supported harness set: OpenCode, Codex, Claude Code, Pi, OMP, and JCode. Each is installed by its own Ansible role.
- Shared configuration directories, wrapper commands, and optional host integrations.
- `ai-jail`, with harness commands routed through it by default.
- `buzz`, compiled from an immutable Block source revision, plus the
  checksum-pinned official Sprig bundle containing `buzz-acp`.

The exact harness list, versions, and installation sources belong in `ansible/group_vars/all/harnesses.yml` (or an equivalent catalog) once implementation starts.

## Prerequisites

- Linux host with Distrobox and a supported container manager (normally Podman).
- Ansible and the collections listed in `ansible/collections/requirements.yml`.
- Network access for package and harness installation.
- A Buzz relay URL and private key if Buzz access is required.

## Quick start

```bash
git clone <repository-url> agentic-distrobox
cd agentic-distrobox
cd ansible
ansible-galaxy collection install -r collections/requirements.yml
cp host_vars/localhost.yml.example host_vars/localhost.yml
chmod 600 host_vars/localhost.yml
$EDITOR host_vars/localhost.yml
ansible-playbook site.yml
```

Enter the sandbox after provisioning:

```bash
distrobox enter agentic
```

## Configuration

### Host variables

`ansible/host_vars/localhost.yml` is intentionally untracked and is the single
source for machine settings, credentials, Git identity, and security options:

```yaml
ads_box_name: agentic
ads_box_home: /home/me/distrobox-agent
ads_image: quay.io/toolbx/arch-toolbox:latest
ads_unshare_all: true
ads_container_pids_limit: 512
ads_container_memory: 8g
ads_container_cpus: 4
ads_container_allow_host_loopback: false
ads_container_network_backend: pasta
ads_ai_jail_enabled: true
ads_ai_jail_network: true
ads_ai_jail_agent_state: true
ads_enabled_harnesses:
  - opencode
  - codex
  - claudecode
  - pi
  - omp
  - jcode

# Disabled unless explicitly configured.
ads_repositories_mount_enabled: true
ads_repositories_host_path: /home/me/src
ads_repositories_box_path: /workspace
ads_repositories_mount_read_only: true
```

The final variable names and defaults should be documented alongside the example file.

`ads_box_home` defaults to `~/distrobox-agent` when it is not overridden. Provisioning creates this persistent host directory before creating the Distrobox, then uses it as the box user's home. This keeps installed harness configuration and local workspace state across box recreation. Set an absolute `ads_box_home` path to place it elsewhere.

### Secrets and local variables

Set credentials directly in the untracked, mode-`0600`
`ansible/host_vars/localhost.yml` file:

```yaml
ads_buzz_relay_url: https://relay.example.example
ads_buzz_private_key: nsec1_replace_me
ads_buzz_source_revision: dad5a33865fc81a2e55b3b60746632f615ec1e3a
ads_buzz_sprig_release_tag: sprig-latest
ads_buzz_auth_tag: ""
ads_git_user_name: Your Name
ads_git_user_email: you@example.com
```

Other harnesses retain their own interactive authentication flows. Secret tasks
suppress their output, and only processes that need Buzz credentials receive
them. Never commit `localhost.yml`.

### Optional repository mount

The sandbox has no host mounts or integrations by default. Operators may explicitly bind-mount one host directory containing code repositories:

```yaml
ads_repositories_mount_enabled: true
ads_repositories_host_path: /home/me/src
ads_repositories_box_path: /workspace
```

This is intended for source code only. The configured Git name and email are available inside the box, but Git credentials, SSH agents, GPUs, desktop applications, and browsers are not forwarded by default.

## Common operations

Run these from `ansible/` once the playbooks exist:

```bash
ansible-playbook site.yml                 # create or converge the sandbox
ansible-playbook site.yml --tags base     # update the base environment
ansible-playbook site.yml --tags harnesses # install/update selected harnesses
ansible-playbook site.yml --tags harness_codex # install/update one harness
ansible-playbook site.yml --tags buzz     # install/configure Buzz and its relay CLI
ansible-playbook verify.yml                # validate the installed environment
ansible-playbook destroy.yml               # remove the managed sandbox
```

Run repository checks without provisioning a box:

```bash
bash tests/static_checks.sh
```

Backup and restore are deferred until the destination and retention policy are defined.
`backup.yml` exits without copying anything; `destroy.yml` removes only the resolved
box name and preserves its persistent home and any repository mount.

## Using Buzz

The Buzz role compiles only the relay CLI from a pinned Block source revision.
It installs `buzz-acp` from the official checksum-pinned Sprig bundle. The
managed `buzz` wrapper loads relay credentials and invokes the compiled CLI.
Confirm connectivity without exposing secret values:

```bash
distrobox enter agentic -- buzz channels list
```

The role removes both `buzz-appimage` and `buzz-bin`; no desktop client is installed.

### Creating an allowlisted Buzz agent

The Buzz role also installs `buzz-acp` and a fail-closed launcher named
`buzz-agent-create`. List the operator-approved agent configurations and launch
one with:

```bash
buzz-agent-create --list
buzz-agent-create codex
```

The launcher accepts exactly one logical name. It does not accept a command or
extra arguments from the caller; both come from the Ansible allowlist:

```yaml
ads_buzz_agent_allowlist:
  codex:
    command: codex
    args: []
  claudecode:
    command: claude
    args: []
```

Only enabled harness names may appear as allowlist keys. Fixed arguments may be
declared by the operator, but cannot contain commas because Buzz ACP's argument
interface is comma-delimited. The launcher reads the mode-`0600` Buzz environment
file only after the requested agent passes allowlist validation, then starts
`buzz-acp`; secret values are neither printed nor placed in command arguments.

## Harness isolation with ai-jail

Provisioning installs [`ai-jail`](https://github.com/akitaonrails/ai-jail)
from the AUR and creates managed wrappers in `~/.local/bin`. The configured
harness commands therefore run through `ai-jail` by default.

The defaults explicitly grant network access and the selected harness's agent
state because interactive agents normally need both. ai-jail still denies its
other host capabilities and the wrappers forward only configured Buzz variables,
not the entire parent environment. These grants and the integration itself can
be tightened independently:

```yaml
ads_ai_jail_network: false
ads_ai_jail_agent_state: false
ads_ai_jail_enabled: false
```

Every ai-jail and Distrobox hardening option is configured in `localhost.yml`:

```yaml
ads_ai_jail_enabled: true
ads_ai_jail_aur_package: ai-jail-bin
ads_ai_jail_network: true
ads_ai_jail_agent_state: true
ads_ai_jail_deny_host_home: true
ads_container_pids_limit: 512
ads_container_memory: 8g
ads_container_cpus: 4
ads_container_allow_host_loopback: false
ads_container_network_backend: pasta
```

Re-run `site.yml` after changing them so managed harness wrappers are regenerated.

Project `.ai-jail` files are ignored by this repository by default.

## Repository layout

```text
ansible/
  collections/             # Ansible collection requirements
  group_vars/all/          # Safe defaults, package lists, harness catalog
  host_vars/               # Local machine overrides (ignored except examples)
  roles/                   # base, distrobox, harness, buzz, verify, ...
  site.yml                 # Primary convergent playbook
  verify.yml               # Post-provision checks
SPEC.md                    # Product and implementation specification
README.md                  # Operator guide
```

## Security model

This is layered risk reduction, not a hardened security boundary. Distrobox is
rootless and created with separate device/sysfs, group, IPC, network, and process
namespaces. The container also receives PID, memory, and CPU limits; host-loopback
access is disabled through Podman's supported `pasta` backend; optional repository
mounts default to read-only; and the
creation settings are recorded in an immutable hardening label. Provisioning
refuses an older box or one created with different hardening settings until the
operator explicitly runs `destroy.yml` and recreates it.

Distrobox still deliberately integrates with the host. In particular, its
generated container configuration can expose `/run/host` and
`distrobox-host-exec`; therefore Distrobox itself must not be treated as the
agent security boundary. Managed Buzz agents are forced to absolute ai-jail
wrapper paths. ai-jail denies those escape surfaces plus Docker and Podman
sockets, supplies a private home, filters the environment, and exposes only the
capabilities explicitly configured by the operator.

Network-enabled agents can exfiltrate any data deliberately exposed to them,
including their own agent state and Buzz identity. Use a dedicated, least-
privileged Buzz key for each agent, keep the Buzz allowlist narrow, prefer
read-only source mounts, and use a disposable VM for hostile workloads.

Managed ai-jail harnesses deny the invoking user's host home. The configured
persistent box home is the only exception, allowing explicitly requested agent
state to be mounted. Host code should be exposed through the narrow `/workspace`
repository mount; launching a harness from an arbitrary host-home checkout fails
closed.

A raw `distrobox enter` shell is not confined this way. Distrobox always mounts
the invoking user's home, and Podman rejects a second masking mount at that same
destination. Never offer a raw Distrobox shell to an untrusted user. If the
interactive shell itself must be confined, use a dedicated host account or a
disposable VM. The supported agent boundary is `buzz-agent-create` followed by
the managed ai-jail wrapper.

## Status and roadmap

- [x] Define the baseline: Arch, with `yay` for AUR packages.
- [x] Implement Ansible roles for base packages, Distrobox creation, harnesses, Buzz, and verification.
- [x] Add untracked localhost variables and secret-safe Ansible loading.
- [x] Add local smoke-test coverage through `verify.yml`.
- [ ] Document each supported harness and its update path.

Implementation requirements and acceptance criteria are in [SPEC.md](SPEC.md).
