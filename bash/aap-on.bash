# The implementations of `aap-*` commands are defined in a `set -euo pipefail` subshell.
# That gives us “strict mode” without running the risk to permanently changing the caller’s environment.

# __aap_on_impl
#
__aap_on_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"

  if ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-on!"
    exit 1
  fi

  if [[ $AICLI_MODE != "planner" ]]; then
    local agent="$AICLI_MODE"
    unset AICLI_MODE
    remountctl rw ai-cli "/${REPOBASE}-AAP"
    trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
    export AICLI_MODE="$agent"
  fi

  rm -f "$objective_tree/OFF"
)

aap-on() {
  __aap_on_impl
}
