# AAP bash commands.

if [[ -z "${PLANROOT:-}" ]]; then
  echo "ERROR: PLANROOT is not set." >&2
  return 1 2>/dev/null || exit 1
fi

# Source low-level helper and utility functions.
__aap_lib="$PLANROOT/agents-common/bash/aap-lib.bash"
source "$__aap_lib"

function __aap_load()
{
  local command

  # Source AAP commands.
  for file in ls insert previous "done" configure build; do
    source "$PLANROOT/agents-common/bash/aap-$file.bash"
  done

  # Source ATP commands.
  for file in list all-done update; do
    source "$PLANROOT/agents-common/bash/atp-$file.bash"
  done
}

__aap_load
unset -f __aap_load

# Export all functions defined here, because the AI needs them and opencode only provides it with exported stuff :/.
for func in $(declare -F | grep '^declare -f ' | sed -e 's/^declare -f //' | grep -E '^(aap-|__aap|atp-|__atp)'); do
  declare -fx $func
done
