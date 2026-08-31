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

  rm -f "$objective_tree/OFF"
)

aap-on() {
  __aap_on_impl
}
