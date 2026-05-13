__aap_reset_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ $AICLI_MODE != "planner" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-reset! The 'planner' agent may run this, when explicitly told to."
    exit 1
  fi

  local refpath="${1:-}"
  if [[ "$refpath" == "--help" || "$refpath" == "-h" ]]; then
    cat <<'EOF'
usage: aap-reset <ref>|<refpath>

Move current_objective to the referenced plan node and set only that node's
status to not-achieved. A <ref> is resolved relative to the parent of the
current objective; a <refpath> starts with '/' and is resolved from ObjectiveTree.
EOF
    exit 0
  fi

  if (( $# != 1 )); then
    __aap_die "usage: aap-reset [--help] <ref>|<refpath>"
    exit 1
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ ! -d "$objective_tree" ]]; then
    __aap_die "Missing ObjectiveTree directory: $(__aap_rel_to_planroot "$objective_tree")"
    exit 1
  fi

  local current_objective_abs=""
  if [[ -L "$current_objective_link" ]]; then
    current_objective_abs="$(readlink -f -- "$current_objective_link" 2>/dev/null || true)"
  fi

  local target_abs=""
  target_abs="$(__aap_resolve_refpath_parent "$objective_tree" "$current_objective_abs" "$refpath")"

  local objective_tree_abs
  objective_tree_abs="$(readlink -f -- "$objective_tree")"
  if [[ "$target_abs" == "$objective_tree_abs" ]]; then
    __aap_die "Cannot reset ObjectiveTree root; provide a refpath to a plan node."
    exit 1
  fi
  if [[ "$target_abs" != "$objective_tree_abs"/* ]]; then
    __aap_die "Resolved target is outside ObjectiveTree: $(abbreviate_path "$target_abs")"
    exit 1
  fi
  if [[ ! -d "$target_abs" ]]; then
    __aap_die "Resolved target is not a directory: $(__aap_rel_to_planroot "$target_abs")"
    exit 1
  fi

  if [[ $AICLI_MODE == "coder" ]]; then
    unset AICLI_MODE
    remountctl rw ai-cli "/${REPOBASE}-AAP"
    trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
    export AICLI_MODE="coder"
  fi

  # Reset only the requested node. Unlike __aap_rollup_not_achieved_from, this
  # intentionally does not update ancestors or descendants, so callers can move
  # the current objective without changing any other objective's status.
  __aap_write_status "$target_abs" not-achieved

  ln -snf -- "$(__aap_rel_to_planroot "$target_abs")" "$current_objective_link"
  __aap_notice "Updated current_objective to point to $(basename -- "$target_abs")."
)

aap-reset() {
  __aap_reset_impl "$@"
}
