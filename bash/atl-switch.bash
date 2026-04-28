# __atl_resolve_refpath <refpath>
#
# Resolve an absolute plan <refpath> to the corresponding plan node directory.
__atl_resolve_refpath() {
  local refpath="$1"
  local objective_tree="$PLANROOT/ObjectiveTree"
  local -a parts

  if [[ "$refpath" != /* ]]; then
    __aap_die "Expected absolute <refpath>, got '$refpath'."
    return 1
  fi
  if [[ "$refpath" == "/" ]]; then
    __aap_die "Topic Lists belong to plan nodes, not ObjectiveTree itself."
    return 1
  fi

  local node="$objective_tree"
  local rest="${refpath#/}"
  local part
  IFS='/' read -r -a parts <<< "$rest"
  for part in "${parts[@]}"; do
    if [[ -z "$part" ]]; then
      __aap_die "Invalid <refpath> '$refpath'."
      return 1
    fi
    node="$(__aap_resolve_ref_in_parent "$node" "$part")" || return 1
  done

  printf '%s\n' "$node"
}

# __atl_switch_impl <refpath>
#
# Change the current Topic List to use the plan node identified by <refpath>.
__atl_switch_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
usage: atl-switch <refpath>

Change the current Topic List to use <refpath>.
EOF
    exit 0
  fi
  if (( $# != 1 )); then
    __aap_die "usage: atl-switch <refpath>"
    exit 1
  fi

  local node_abs
  node_abs="$(__atl_resolve_refpath "$1")"
  if [[ $AICLI_MODE == "analyst" || $AICLI_MODE == "coder" ]]; then
    unset AICLI_MODE
    remountctl rw ai-cli "/${REPOBASE}-AAP"
    trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
    export AICLI_MODE="analyst"
  fi

  mkdir -p -- "$PLANROOT/analyst"
  if [[ -d "$PLANROOT/analyst/current" && ! -L "$PLANROOT/analyst/current" ]]; then
    rm -rf -- "$PLANROOT/analyst/current"
  fi
  ln -snf -- "$node_abs" "$PLANROOT/analyst/current"
  __aap_refpath_of "$node_abs"
)

atl-switch() {
  __atl_switch_impl "$@"
}
