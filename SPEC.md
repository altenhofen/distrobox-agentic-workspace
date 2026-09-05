# Agentic Distrobox Sandbox Specification

## 1. Purpose

Build a reproducible, Ansible-managed Distrobox for agentic development and
automation. The box packages multiple agent harnesses, a source-pinned Buzz
relay CLI, and prebuilt Buzz ACP tools, while keeping relay
credentials and other secrets local to the operator.

## 2. Scope

### In scope

- A named Arch-based Distrobox and a documented supported host/runtime baseline.
- Ansible playbooks and roles to create, converge, verify, back up, and remove the box.
- A catalog-driven installation of selected agent harnesses.
- Installation and runtime configuration of `buzz`.
- Untracked localhost-variable secret loading for Buzz and future integrations.
- Idempotent provisioning and clear failure messages.

### Out of scope

- Operating or hosting a Buzz relay.
- Replacing each harness's own authentication, licensing, or usage policies.
- Treating Distrobox as a hardened sandbox or mandatory access-control boundary.
- Synchronizing personal agent configuration or credentials from the host without an explicit role and documented opt-in.

## 3. Users and primary workflows

| User | Need | Workflow |
| --- | --- | --- |
| Operator | Create a repeatable agent workspace | Set local variables and secrets, then run `site.yml`. |
| Agent user | Use installed harnesses and Buzz | Enter the box and invoke a harness or `buzz`. |
| Maintainer | Add or update a harness safely | Update its catalog entry/role, converge, and run verification. |
| Operator | Rebuild after a failed experiment | Back up managed state, destroy or recreate the box, then converge. |

## 4. Functional requirements

### 4.1 Provisioning

1. The primary playbook MUST create or converge a Distrobox whose name and image are configurable.
2. The supported baseline MUST use an Arch image and retain `yay` for supported
   AUR dependencies. Buzz desktop packages MUST not be installed.
3. The box MUST run as the matching host UID/GID and use a configurable persistent home/data location.
4. Provisioning MUST create the configured persistent host directory before box creation. Its default MUST be `~/distrobox-agent`; operators MAY override it with an absolute `ads_box_home` path.
5. All create and update operations MUST be idempotent.
6. Roles MUST be taggable so an operator can converge base packages, a single harness, or Buzz without reinstalling unrelated tools.

### 4.2 Harness catalog

1. Each harness MUST have a declarative catalog entry containing its name, version or release channel, source, dependencies, install method, command to verify, and optional flag.
2. Each harness MUST be installed by a dedicated role or a documented reusable role interface.
3. A failed optional harness MUST identify the failing harness and leave unrelated installed tooling usable.
4. The initial supported harnesses are OpenCode, Codex, Claude Code, Pi, OMP, and JCode. They MUST be enabled by default, while the catalog MUST support future opt-in harnesses without modifying the primary playbook.

### 4.3 Buzz desktop and CLI

1. Provisioning MUST compile the Buzz relay CLI from an immutable Block source
   revision, install `buzz-acp` from a checksum-pinned prebuilt Sprig artifact,
   and expose both binaries on `PATH` inside the box.
2. The Buzz role MUST verify the installed AUR package and run `buzz --help`
   (or an equivalent non-network check) after installation.
3. When `ads_buzz_relay_url` and `ads_buzz_private_key` are configured, the environment MUST be made available to interactive shells and explicitly managed harness subprocesses in the box.
4. Secret values MUST NOT appear in task output, facts, generated non-secret files, command lines recorded by Ansible, or verification reports.
5. A connectivity check such as `buzz channels list` MUST be opt-in because it contacts the configured relay.

### 4.4 Configuration and secrets

1. `ansible/host_vars/localhost.yml.example` MUST list every supported Buzz,
   Git identity, ai-jail, and Distrobox hardening variable with safe placeholders.
2. `ansible/host_vars/localhost.yml` MUST be ignored by Git and protected with
   mode `0600`; its example file MAY be tracked.
3. Secret-loading tasks MUST use `no_log: true` and validate that required variables are present before a dependent role runs.
4. Non-secret machine settings MUST live in `host_vars/localhost.yml`, with a tracked example file.
5. The implementation MUST document where localhost variables are loaded and
   which processes receive each secret.
6. `localhost.yml` contains Buzz variables, Git identity variables, and ai-jail
   and Distrobox hardening options as the sole operator configuration source.
7. When both Git identity variables are present, provisioning MUST configure `user.name` and `user.email` in the box user's global Git configuration. It MUST NOT change the host Git configuration.

### 4.5 Host integration

1. The default Distrobox configuration MUST not forward Git credentials, SSH agents, GPU devices, desktop exports, browser state, or arbitrary host directories.
2. Operators MAY enable one explicit bind mount for a host directory of code repositories.
3. The host path and in-box destination MUST be configurable independently and documented in `host_vars/localhost.yml.example`.
4. Mount configuration MUST be validated before box creation; the destroy playbook MUST never delete the host-mounted directory.

### 4.6 Lifecycle and verification

1. `verify.yml` MUST check Distrobox availability, box entry, shared tooling, and every enabled harness's verification command.
2. Verification MUST distinguish local installation failures from relay/authentication failures.
3. Backup and restore are deferred from the first implementation because their destination and retention policy are undecided. Until specified, no playbook MAY copy secrets or managed state off-machine.
4. Destroy MUST display its concrete Distrobox target before removing it and MUST NOT delete arbitrary host paths.

## 5. Proposed Ansible structure

```text
ansible/
  ansible.cfg
  site.yml
  verify.yml
  backup.yml
  destroy.yml
  collections/requirements.yml
  group_vars/all/
    main.yml
    packages.yml
    harnesses.yml
  host_vars/
    localhost.yml.example
  roles/
    prerequisites/          # Validate host commands and inputs
    distrobox/              # Create and enter/manage the named box
    base/                   # Packages and shared directories
    harnesses/              # Catalog dispatcher / common contract
    harness_<name>/         # Per-harness implementation
    buzz/                   # CLI install and environment wiring
    environment/            # Safe shell environment generation
    verify/                 # Local smoke checks
```

The entry playbook should run: input validation → box creation → base tooling → enabled harnesses → Buzz → local verification. Secret-bearing tasks are isolated so that their logs can be suppressed and audited.

## 6. Configuration contract

| Setting | Storage | Example | Notes |
| --- | --- | --- | --- |
| `ads_box_name` | `host_vars/localhost.yml` | `agentic` | Distrobox name. |
| `ads_image` | `host_vars/localhost.yml` | Arch-compatible image | Container image used to create the box. |
| `ads_box_home` | `host_vars/localhost.yml` | `~/distrobox-agent` | Persistent host directory created before the box; an absolute path overrides the default. |
| `ads_enabled_harnesses` | `host_vars/localhost.yml` | `opencode`, `codex`, `claudecode`, `pi`, `omp`, `jcode` | Controls supported roles. |
| `ads_repositories_mount_enabled` | `host_vars/localhost.yml` | `false` | Enables an explicit code-directory mount. |
| `ads_repositories_host_path` | `host_vars/localhost.yml` | `/home/me/src` | Source directory to mount when enabled. |
| `ads_repositories_box_path` | `host_vars/localhost.yml` | `/workspace` | Mount destination inside the box. |
| `ads_buzz_relay_url` | `host_vars/localhost.yml` | `https://relay.example` | Relay endpoint. |
| `ads_buzz_private_key` | `host_vars/localhost.yml` | `nsec1...` | Secret signing key. |
| `ads_buzz_auth_tag` | `host_vars/localhost.yml` | optional attestation | Only passed where required. |
| `ads_buzz_source_revision` | `host_vars/localhost.yml` | full commit SHA | Immutable source used to compile the Buzz CLI. |
| `ads_buzz_sprig_release_tag` | `host_vars/localhost.yml` | `sprig-latest` | Release containing the prebuilt ACP bundle. |
| `ads_git_user_name` | `host_vars/localhost.yml` | `Your Name` | Configures `git config --global user.name` inside the box. |
| `ads_git_user_email` | `host_vars/localhost.yml` | `you@example.com` | Configures `git config --global user.email` inside the box. |

`ads_` is a provisional variable prefix; retain it or rename it consistently before implementation.

## 7. Security and isolation requirements

- Distrobox creation flags and the optional repository mount MUST be explicit Ansible variables with conservative defaults.
- The rootless container MUST use separate device/sysfs, supplementary-group,
  IPC, network, and process namespaces, plus bounded PID, memory, and CPU usage.
- The rootless Podman `pasta` network MUST deny host-loopback access by default. An operator may
  override this only through an explicit setting.
- Container hardening settings MUST be recorded in a creation-time label. A box
  with a missing or stale label MUST fail closed and require explicit recreation;
  provisioning MUST NOT silently destroy it.
- Agent execution MUST NOT rely on Distrobox as the security boundary. When
  ai-jail is enabled, Buzz MUST invoke the absolute managed wrapper path and the
  wrapper MUST deny `/run/host`, `distrobox-host-exec`, and common container
  engine sockets.
- Managed harnesses MUST deny the invoking user's host home, with only the
  persistent box home excepted for explicitly requested agent state.
- Documentation MUST state that raw `distrobox enter` shells retain Distrobox's
  host-home mount and MUST NOT be provided to untrusted users.
- The persistent box-home directory MUST be created with ownership for the matching host user. Destruction MAY remove the Distrobox but MUST preserve this directory unless a future, separately confirmed cleanup option explicitly targets it.
- No role MAY broadly forward the host environment into the box.
- Git credentials, SSH agents, GPU access, desktop exports, browser state, and arbitrary host mounts MUST remain disabled by default.
- The Git name and email from localhost variables MAY be written to the box
  user's Git configuration; no Git credential, token, private key, or signing
  key other than the explicitly scoped Buzz key MAY be loaded.
- Secrets MUST be provided only to processes that need them, preferably through a shell fragment readable by the box user and mode `0600`.
- The generated secret fragment MUST live within the configured persistent box home, never in the repository.
- Logs and CI output MUST redact known secret variable values.
- Documentation MUST state that a Distrobox shares host integration and is not sufficient isolation for untrusted code.

## 8. Testing and acceptance criteria

| Area | Acceptance criterion |
| --- | --- |
| Fresh provision | On a supported host, `site.yml` creates the configured box and completes without manual package installation. |
| Repeatability | A second `site.yml` run reports no unintended changes and succeeds. |
| Harnesses | Every enabled harness resolves on `PATH` and passes its catalog verification command. |
| Buzz installation | The source-pinned CLI and checksum-pinned ACP bundle run; neither Buzz desktop AUR package is installed. |
| Secrets | A scan of Ansible output and generated tracked files finds no relay URL, private key, or auth tag value. |
| Missing credentials | A Buzz-dependent operation fails early with a precise, secret-safe message. |
| Relay use | With valid opt-in credentials, `buzz channels list` succeeds against the configured relay. |
| Destruction | The destroy playbook removes only the named Distrobox after displaying the resolved target. |
| Container hardening | Verification rejects host PID/IPC/network namespaces, missing resource limits, stale hardening labels, and permissive Buzz secret-file modes. |

## 9. Open decisions

1. Which harnesses are in the first supported set, and which are opt-in?
2. Which container image and package manager form the supported baseline?
3. Which package names, sources, and verification commands should each of the six initial harness roles use?
4. Should the optional repository mount be read-only, read-write, or configurable per operator?
5. What backup destination and restore interface should a later lifecycle feature support for managed, non-secret state?

## 10. Milestones

1. Scaffold the Ansible project, examples, `.gitignore`, Arch/yay baseline, and base Distrobox role.
2. Implement the six initial harness roles and their local verification commands.
3. Add the Buzz role, pinned official installation, and secret-safe localhost variable handling.
4. Add the opt-in repository-mount configuration and verification playbook.
5. Run a clean-host install, idempotence pass, and documented rebuild test.
