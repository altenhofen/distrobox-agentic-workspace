# Agentic Rootless Podman Runtime

This project builds a dedicated, rootless Podman runtime for agent harnesses
and connects it to the host Buzz Desktop through a Buzz relay. Distrobox is not
used: the live agent has no host-home mount, no container-engine socket, and no
desktop integration mounts.

## Runtime design

```text
Buzz Desktop ── relay WebSocket ── buzz-acp in rootless Podman runtime
                                        └── ai-jail ── harness
```

Provisioning first creates a short-lived rootless build container. It installs
the pinned CLI, ACP bundle, and enabled harnesses, commits a local image, then
removes the builder. The live runtime starts from that image with a read-only
root filesystem, all Linux capabilities dropped, `no-new-privileges`, resource
limits, and private `pasta` networking. Only these host paths can be mounted:

- `ads_runtime_state_path` at `/home/agent` for agent state and the private
  Buzz environment.
- An explicitly configured workspace at `/workspace`.

The host Buzz Desktop never runs inside the container. It discovers live agents
through the relay, keypair, authorization tag, and channel membership; it does
not need access to the container itself.

## Quick start

```bash
git clone <repository-url> agentic-runtime
cd agentic-runtime/ansible
ansible-galaxy collection install -r collections/requirements.yml
cp host_vars/localhost.yml.example host_vars/localhost.yml
chmod 600 host_vars/localhost.yml
$EDITOR host_vars/localhost.yml
ansible-playbook site.yml
```

Run a Buzz-connected harness from the host:

```bash
cd ..
./buzz-agent-run.sh codex
```

Or inspect the runtime directly:

```bash
podman exec -it agentic bash
```

## Configuration

All operator settings live in the untracked, mode-`0600`
`ansible/host_vars/localhost.yml` file. Important settings:

```yaml
ads_runtime_name: agentic
ads_builder_name: agentic-build
ads_base_image: quay.io/toolbx/arch-toolbox:latest
ads_runtime_image: localhost/agentic-runtime:latest
ads_runtime_state_path: /home/me/.local/share/agentic-runtime

ads_workspace_mount_enabled: true
ads_workspace_host_path: /home/me/src/project
ads_workspace_container_path: /workspace
ads_workspace_mount_read_only: false

ads_buzz_relay_url: https://relay.example.example
ads_buzz_private_key: nsec1_replace_me
ads_buzz_auth_tag: ''
ads_buzz_acp_agent_owner: ''
ads_buzz_acp_respond_to: owner-only
```

The workspace is disabled by default. Do not set its host path to `$HOME` or
`/`; mount only the repository an agent needs.

## Buzz Desktop integration

Set the relay URL, a dedicated agent private key, and (when required) an
owner-issued `BUZZ_AUTH_TAG`, then rerun `site.yml`. Start an agent using
`./buzz-agent-run.sh codex`. Add the agent identity to the target relay/channel
so it receives events.

To create an owner-reviewed Desktop agent draft, run from the host:

```bash
./buzz-agent-draft-create.sh <channel-uuid> "Codex Worker" \
  "Work on repository tasks and report completed changes."
```

`BUZZ_AUTH_TAG` is an owner-signed NIP-OA attestation for that agent public key,
not a reusable Desktop password. Generate a distinct agent keypair with
`buzz-admin generate-key`; the Buzz owner then creates the attestation using
the supported Buzz owner-attestation flow. The agent still needs channel
membership after it is authorized.

## Operations

```bash
cd ansible
ansible-playbook site.yml
ansible-playbook verify.yml
ansible-playbook destroy.yml
```

`destroy.yml` removes only the managed live and build containers. It preserves
the runtime-state directory and any explicitly mounted workspace.

Run repository checks with:

```bash
bash tests/static_checks.sh
```

Refresh pinned Buzz, Sprig, and JCode metadata with `./update_deps.sh`.

## Security boundary

Rootless Podman is a materially stronger fit than Distrobox here because the
agent does not receive Distrobox's host integration. It still shares the host
kernel, so treat it as layered containment rather than protection from kernel
exploits. Use a separate VM for hostile or untrusted workloads. Network-enabled
agents can exfiltrate all data deliberately mounted into their runtime.
