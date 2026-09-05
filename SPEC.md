# Agentic Rootless Runtime Specification

## Purpose

Provide a reproducible, Ansible-managed rootless Podman runtime for agent
harnesses and Buzz ACP. The host Buzz Desktop remains outside the runtime and
communicates through the configured relay.

## Requirements

1. The project MUST not require or invoke Distrobox.
2. Provisioning MUST use rootless Podman and an Arch-compatible base image.
3. Provisioning MUST create a short-lived builder, install selected harnesses,
   commit a local runtime image, remove the builder, and start a live runtime.
4. The live runtime MUST use a read-only root filesystem, `no-new-privileges`,
   `--cap-drop=ALL`, bounded PID/memory/CPU use, and non-host networking.
5. The live runtime MUST mount only the private state directory and, when
   enabled, one explicitly configured workspace directory. It MUST NOT mount
   host home, container-engine sockets, desktop exports, SSH agents, or browser
   state.
6. All operator settings, including Buzz secrets and every runtime option, MUST
   be represented in `host_vars/localhost.yml.example`; real values belong only
   in untracked mode-`0600` `host_vars/localhost.yml`.
7. Buzz CLI MUST be built from a pinned Block revision and ACP binaries MUST be
   checksum-pinned. Desktop packages are not installed in the runtime.
8. A dedicated Buzz keypair, owner attestation, relay URL, and channel
   membership MUST be sufficient to make a runtime process a live Buzz agent.
9. `verify.yml` MUST reject a runtime without the requested hardening flags,
   missing resource limits, incorrect hardening label, or permissive secret file.
10. `destroy.yml` MUST remove only named managed containers and preserve state
    and explicitly mounted workspaces.

## Interfaces

- `buzz-agent-run.sh AGENT_COMMAND [ARG ...]` starts Buzz ACP inside the live
  runtime.
- `buzz-agent-draft-create.sh CHANNEL_UUID DISPLAY_NAME SYSTEM_PROMPT` creates
  an owner-reviewed Buzz Desktop draft via the live runtime.
- `ansible-playbook site.yml` converges the image and runtime.

## Security boundary

Rootless Podman and ai-jail are defense-in-depth mechanisms. They reduce host
integration and filesystem exposure but share the host kernel; hostile code
requires a dedicated VM or microVM backend.
