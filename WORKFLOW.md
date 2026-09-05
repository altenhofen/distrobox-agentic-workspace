# Complete Workflow

## 1. Host requirements

Install rootless Podman, Ansible, and enable unprivileged user namespaces for
Bubblewrap. Confirm:

```bash
podman --version
ansible-playbook --version
```

No Distrobox installation is required.

## 2. Configure the runtime

```bash
cp ansible/host_vars/localhost.yml.example ansible/host_vars/localhost.yml
chmod 600 ansible/host_vars/localhost.yml
```

Edit the new file. `ads_runtime_state_path` is a private host directory mounted
only as `/home/agent` in the runtime. It is not a bind of your entire home.
Enable `ads_workspace_mount_enabled` only for a narrow repository directory;
use read/write only when the agent must modify it.

Configure Buzz with a dedicated agent key, not your personal owner key:

```yaml
ads_buzz_relay_url: https://relay.example.example
ads_buzz_private_key: nsec1_agent_key
ads_buzz_auth_tag: ''
ads_buzz_acp_agent_owner: '<owner-pubkey>'
ads_buzz_acp_respond_to: owner-only
```

An auth tag is an owner-signed NIP-OA attestation for the agent key. Obtain one
from the Buzz owner-attestation flow; it does not replace relay/channel
membership.

## 3. Provision

```bash
cd ansible
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook site.yml
```

The playbook validates input, starts a transient rootless builder, installs the
catalog, commits `ads_runtime_image`, removes the builder, and runs a hardened
live runtime. The final runtime has a read-only root filesystem, no capabilities,
`no-new-privileges`, PID/memory/CPU limits, private `pasta` networking, and
only the configured state/workspace mounts.

## 4. Verify

```bash
ansible-playbook verify.yml
```

This checks the hardened container flags, secret-file permissions, Buzz tools,
ai-jail, and every enabled harness. Relay access remains opt-in through
`ads_buzz_connectivity_check`.

## 5. Use Buzz agents

From the repository root:

```bash
./buzz-agent-run.sh codex
./buzz-agent-run.sh claude --model sonnet
```

The helper runs `buzz-agent-create` inside the live rootless runtime. Its path
is `buzz-acp → managed ai-jail wrapper → harness`; the Desktop talks to it only
through the configured relay.

Create a Desktop-visible, owner-reviewed draft with:

```bash
./buzz-agent-draft-create.sh <channel-uuid> "Codex Worker" "System prompt"
```

Approve and save the draft in Buzz Desktop, then ensure that agent identity is
a member of the selected channel. A successful ACP connection alone does not
subscribe the agent to every channel.

## 6. Update

Update the repository or `host_vars/localhost.yml`, then rerun:

```bash
cd ansible
ansible-playbook site.yml
ansible-playbook verify.yml
```

Each convergence builds a new immutable local runtime image and replaces the
live runtime container. State remains in `ads_runtime_state_path`.

## 7. Destroy

```bash
cd ansible
ansible-playbook destroy.yml --check
ansible-playbook destroy.yml
```

This removes only `ads_runtime_name` and `ads_builder_name`. It never deletes
the state directory or workspace. Remove either manually only after reviewing
its exact path.

## Troubleshooting

If `ai-jail` cannot start Bubblewrap, fix the host's unprivileged user namespace
policy; do not disable isolation merely to suppress the failure. If Buzz reports
no subscriptions, verify `BUZZ_ACP_AGENT_OWNER`, the owner auth tag, and the
agent's channel membership. Never paste the private key or auth tag into logs.
