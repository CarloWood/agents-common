# The implementations of `aap-*` commands are defined in a `set -euo pipefail` subshell.
# That gives us “strict mode” without running the risk to permanently changing the caller’s environment.

# __aap_off_impl
#
__aap_off_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"

  if ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-off!"
    exit 1
  fi

  touch "$objective_tree/OFF"
)

aap-off() {
  __aap_off_impl
}
