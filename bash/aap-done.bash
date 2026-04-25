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
$PLANROOT/current_objective to the lexicographically first not-achieved leaf.
EOF
    exit 0
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ ! -d "$objective_tree" ]]; then
    __aap_notice "Missing ObjectiveTree directory: $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree");"' Use `aap-bootstrap` to add the main objective.'
    exit 0
  fi

  if [[ ! -L "$current_objective_link" ]]; then
    __aap_notice "All goals have been achieved."
    exit 0
  fi

  local current_abs
  current_abs="$(readlink -f -- "$current_objective_link")"
  if [[ ! -d "$current_abs" ]]; then
    __aap_die "current_objective is not a directory: $(__aap_rel_to_planroot "$PLANROOT" "$current_abs")"
    exit 1
  fi
  if ! __aap_is_leaf "$current_abs"; then
    __aap_die "current_objective is not a leaf objective: $(__aap_rel_to_planroot "$PLANROOT" "$current_abs")"
    exit 1
  fi

  local current_status
  current_status="$(__aap_read_status "$PLANROOT" "$current_abs")"
  if [[ "$current_status" != "not-achieved" ]]; then
    __aap_die "current objective is already achieved: $(basename -- "$current_abs")"
    exit 1
  fi

  # Set parent_abs to the parent directory of current_abs, unless that is the ObjectiveTree,
  # then set parent_abs to the same directory.
  local parent_abs
  parent_abs="$(dirname -- "$current_abs")"
  if [[ "$(readlink -f -- "$current_abs")" == "$(readlink -f -- "$objective_tree")" ]]; then
    parent_abs="$current_abs"
  fi

  local resolved
  resolved="$(__aap_resolve_ref_in_parent "$PLANROOT" "$parent_abs" "$ref")"
  if [[ "$(readlink -f -- "$resolved")" != "$(readlink -f -- "$current_abs")" ]]; then
    __aap_die "Ref '$ref' does not refer to the current objective ($(basename -- "$current_abs"))."
    exit 1
  fi

  if [[ $AICLI_MODE == "coder" ]]; then
    unset AICLI_MODE
    remountctl rw ai-cli "/${REPOBASE}-AAP"
    trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
    export AICLI_MODE="coder"
  fi

  __aap_ensure_status "$PLANROOT" "$current_abs" 1
  __aap_write_status "$PLANROOT" "$current_abs" achieved

  __aap_rollup_statuses_from "$PLANROOT" "$parent_abs" "$objective_tree"

  local next_leaf=""
  if next_leaf="$(__aap_find_first_not_achieved_leaf "$PLANROOT" "$objective_tree")"; then
    ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$next_leaf")" "$current_objective_link"
    __aap_notice "Updated current_objective to point to $(basename -- "$next_leaf")."
    exit 0
  fi

  rm -f -- "$current_objective_link"
  __aap_notice "All goals have been achieved."
)

aap-done() {
  __aap_done_impl "$@"
}
