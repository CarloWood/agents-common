__aap_done_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ $AICLI_MODE != "planner" && $AICLI_MODE != "coder" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-done! This is a 'coder'-agent only function (although the 'planner' may run it too when explicitly told to)."
    exit 1
  fi

  if (( $# != 1 )); then
    __aap_die "usage: aap-done <ref>"
    exit 1
  fi
  local ref="$1"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-done <ref>

Mark the current objective as achieved (must match <ref>), then update
$PLANROOT/current_objective to the first not-achieved node of the current plan.
EOF
    exit 0
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ ! -d "$objective_tree" ]]; then
    __aap_notice "Missing ObjectiveTree directory: $(__aap_rel_to_planroot "$objective_tree");"' Use `aap-insert --parent / <node>` to add a primary objective.'
    exit 0
  fi

  if [[ ! -L "$current_objective_link" ]]; then
    __aap_notice "All goals have been achieved."
    exit 0
  fi

  local current_abs
  current_abs="$(readlink -f -- "$current_objective_link")"
  if [[ ! -d "$current_abs" ]]; then
    __aap_die "current_objective is not a directory: $(__aap_rel_to_planroot "$current_abs")"
    exit 1
  fi

  local current_status
  current_status="$(__aap_read_status "$current_abs")"
  if [[ "$current_status" != "not-achieved" ]]; then
    __aap_die "current objective is already achieved: $(basename -- "$current_abs")"
    exit 1
  fi

  local parent_abs
  parent_abs="$(dirname -- "$current_abs")"
  local resolved
  resolved="$(__aap_resolve_ref_in_parent "$parent_abs" "$ref")"
  local resolved_abs
  resolved_abs="$(readlink -f -- "$resolved")"
  if [[ "$resolved_abs" != "$current_abs" ]]; then
    __aap_die "Ref '$ref' does not refer to the current objective ($(basename -- "$current_abs"))."
    exit 1
  fi

  if [[ $AICLI_MODE == "coder" ]]; then
    unset AICLI_MODE
    remountctl rw ai-cli "/${REPOBASE}-AAP"
    trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
    export AICLI_MODE="coder"
  fi

  __aap_ensure_status "$current_abs" 1
  # Mark the current objective as achieved.
  __aap_write_status "$current_abs" achieved

  # Set current_objective to the first not-achieved node of the current plan.
  local first_not_achieved_node=""
  if first_not_achieved_node="$(__aap_find_first_not_achieved_node "$objective_tree")"; then
    ln -snf -- "$(__aap_rel_to_planroot "$first_not_achieved_node")" "$current_objective_link"
    __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_node")."
    exit 0
  fi

  # No not-achieved node exists anymore.
  rm -f -- "$current_objective_link"
  __aap_notice "All goals have been achieved."
)

aap-done() {
  __aap_done_impl "$@"
}
