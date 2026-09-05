#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
main_vars="$repo_root/ansible/group_vars/all/main.yml"
host_example="$repo_root/ansible/host_vars/localhost.yml.example"
harness_vars="$repo_root/ansible/group_vars/all/harnesses.yml"
dry_run=false
check_only=false

usage() {
  printf 'Usage: %s [--check] [--dry-run]\n' "$(basename "$0")" >&2
}

while (($#)); do
  case "$1" in
    --check) check_only=true ;;
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 64 ;;
  esac
  shift
done

command -v gh >/dev/null || { echo 'update_deps.sh: gh is required' >&2; exit 69; }
command -v curl >/dev/null || { echo 'update_deps.sh: curl is required' >&2; exit 69; }
command -v sha256sum >/dev/null || { echo 'update_deps.sh: sha256sum is required' >&2; exit 69; }
command -v python3 >/dev/null || { echo 'update_deps.sh: python3 is required' >&2; exit 69; }

new_buzz_revision=$(gh api repos/block/buzz/commits/main --jq '.sha')
[[ $new_buzz_revision =~ ^[0-9a-f]{40}$ ]] || { echo 'invalid Buzz revision returned by GitHub' >&2; exit 65; }

sprig_x86=$(curl --fail --silent --show-error --location https://github.com/block/buzz/releases/download/sprig-latest/sprig-x86_64-unknown-linux-musl.tar.gz.sha256 | awk 'NR == 1 {print $1}')
sprig_arm=$(curl --fail --silent --show-error --location https://github.com/block/buzz/releases/download/sprig-latest/sprig-aarch64-unknown-linux-musl.tar.gz.sha256 | awk 'NR == 1 {print $1}')
[[ $sprig_x86 =~ ^[0-9a-f]{64}$ && $sprig_arm =~ ^[0-9a-f]{64}$ ]] || { echo 'invalid Sprig checksum returned by GitHub' >&2; exit 65; }

new_jcode_version=$(gh api repos/1jehuang/jcode/releases/latest --jq '.tag_name')
[[ $new_jcode_version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid JCode release tag: $new_jcode_version" >&2; exit 65; }

printf 'Buzz revision: %s\nSprig x86_64: %s\nSprig aarch64: %s\nJCode release: %s\n' \
  "$new_buzz_revision" "$sprig_x86" "$sprig_arm" "$new_jcode_version"

if $check_only || $dry_run; then
  exit 0
fi

python3 - "$main_vars" "$host_example" "$harness_vars" "$new_buzz_revision" "$sprig_x86" "$sprig_arm" "$new_jcode_version" <<'PY'
import pathlib
import re
import sys

main_path, host_path, harness_path, buzz, sprig_x86, sprig_arm, jcode = sys.argv[1:]

def replace(path, pattern, replacement):
    p = pathlib.Path(path)
    text = p.read_text()
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"update_deps.sh: expected one match in {path}: {pattern}")
    p.write_text(updated)

replace(main_path, r'(^ads_buzz_source_revision: )[0-9a-f]{40}$', rf'\g<1>{buzz}')
replace(main_path, r'(^  x86_64: \{name: sprig-x86_64-unknown-linux-musl\.tar\.gz, sha256: )[0-9a-f]{64}(\})$', rf'\g<1>{sprig_x86}\2')
replace(main_path, r'(^  aarch64: \{name: sprig-aarch64-unknown-linux-musl\.tar\.gz, sha256: )[0-9a-f]{64}(\})$', rf'\g<1>{sprig_arm}\2')
replace(host_path, r'(^ads_buzz_source_revision: )[0-9a-f]{40}$', rf'\g<1>{buzz}')
replace(harness_path, r'(^    version: )v[0-9]+\.[0-9]+\.[0-9]+$', rf'\g<1>{jcode}')
PY

bash "$repo_root/tests/static_checks.sh"
git -C "$repo_root" diff --check
