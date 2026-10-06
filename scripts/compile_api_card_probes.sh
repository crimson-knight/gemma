#!/usr/bin/env bash
set -euo pipefail

script_directory="$(dirname "$0")"
repository_root="$(cd "$script_directory/.." && pwd)"
probe_directory="$repository_root/spec/api_card_probes"
grant_repository_root="${GRANT_API_CARD_ROOT:-/Users/crimsonknight/open_source_coding_projects/amber_framework_libraries/grant-api-card}"
expected_grant_revision="0edcd6332bf5feeeae20f32a82739328cea0a00d"

actual_grant_revision="$(git -C "$grant_repository_root" rev-parse HEAD)"
if [[ "$actual_grant_revision" != "$expected_grant_revision" ]]; then
  printf 'Probe compile result: RED (Grant source revision mismatch: expected %s, found %s)\n' "$expected_grant_revision" "$actual_grant_revision"
  exit 1
fi

if [[ ! -f "$repository_root/shard.lock" ]]; then
  (cd "$repository_root" && shards-alpha install --without-development --skip-postinstall --skip-ai-docs --skip-ai-assistant)
fi
(cd "$repository_root" && shards-alpha install --frozen --without-development --skip-postinstall --skip-ai-docs --skip-ai-assistant)
(cd "$grant_repository_root" && shards-alpha install --frozen --skip-postinstall --skip-ai-docs --skip-ai-assistant)

# Link the separately pinned Grant source into Gemma's ignored dependency directory for require "grant".
grant_library_link="$repository_root/lib/grant"
if [[ -L "$grant_library_link" ]]; then
  linked_grant_root="$(readlink "$grant_library_link")"
  if [[ "$linked_grant_root" != "$grant_repository_root" ]]; then
    printf 'Probe compile result: RED (lib/grant points to %s)\n' "$linked_grant_root"
    exit 1
  fi
elif [[ -e "$grant_library_link" ]]; then
  printf 'Probe compile result: RED (lib/grant exists and is not the expected symlink)\n'
  exit 1
else
  ln -s "$grant_repository_root" "$grant_library_link"
fi

for dependency_name in ameba db mysql pg sqlite3; do
  dependency_source="$grant_repository_root/lib/$dependency_name"
  dependency_link="$repository_root/lib/$dependency_name"
  if [[ -e "$dependency_link" || -L "$dependency_link" ]]; then
    linked_dependency="$(readlink "$dependency_link")"
    if [[ "$linked_dependency" != "$dependency_source" ]]; then
      printf 'Probe compile result: RED (lib/%s points to %s)\n' "$dependency_name" "$linked_dependency"
      exit 1
    fi
  else
    ln -s "$dependency_source" "$dependency_link"
  fi
done

cd "$repository_root"
export CRYSTAL_PATH="$repository_root/src:$repository_root/lib"
export CRYSTAL_WORKERS=1
export CRYSTAL_CACHE_DIR="$repository_root/.crystal-cache/api-card-probes"

probe_count=0
error_count=0
warning_count=0

while IFS= read -r probe_path; do
  probe_count=$((probe_count + 1))
  if output=$(crystal-alpha build --no-codegen --no-color "$probe_path" 2>&1); then
    warning_lines=$(printf '%s\n' "$output" | grep -Eic 'warning:' || true)
    warning_count=$((warning_count + warning_lines))
    if (( warning_lines > 0 )); then
      printf 'Warnings in %s:\n%s\n' "$(basename "$probe_path")" "$output"
    fi
  else
    error_count=$((error_count + 1))
    printf 'Compile error in %s:\n%s\n' "$(basename "$probe_path")" "$output"
  fi
done < <(find "$probe_directory" -type f -name '*.cr' -print | sort)

if (( probe_count == 0 )); then
  printf 'Probe compile result: RED (0 probe files found)\n'
  exit 1
elif (( error_count > 0 )); then
  printf 'Probe compile result: RED (errors=%d, warnings=%d, probes=%d)\n' "$error_count" "$warning_count" "$probe_count"
  exit 1
elif (( warning_count > 0 )); then
  printf 'Probe compile result: YELLOW (errors=0, warnings=%d, probes=%d)\n' "$warning_count" "$probe_count"
  exit 1
else
  printf 'Probe compile result: GREEN (errors=0, warnings=0, probes=%d)\n' "$probe_count"
fi
