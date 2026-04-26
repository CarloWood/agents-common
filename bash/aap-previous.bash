__aap_previous_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ $AICLI_MODE != "planner" && $AICLI_MODE != "coder" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-previous! The 'coder' and 'planner' agents may run this, when explicitly told to."
    exit 1
  fi
  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-previous

Move current_objective to the previous goal (depth-first lexicographic
order) and mark it not-achieved.
EOF
    exit 0
  fi

  if (( $# != 0 )); then
    __aap_die "usage: aap-previous"
    exit 1
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ ! -d "$objective_tree" ]]; then
    __aap_die "Missing ObjectiveTree directory: $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")"
    exit 1
  fi

  local nodes=()
  local node
  while IFS= read -r -d '' node; do
    nodes+=("$node")
  done < <(__aap_list_depth_first_post_order_nodes "$objective_tree")

  if (( ${#nodes[@]} == 0 )); then
    __aap_die "No nodes found under $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")."
    exit 1
  fi

  local idx=${#nodes[@]}
  local current_abs=""
  if [[ -L "$current_objective_link" ]]; then
    current_abs="$(readlink -f -- "$current_objective_link" 2>/dev/null || true)"
  fi
  if [[ -n "$current_abs" && -d "$current_abs" ]]"; then
    local i
    for (( i=0; i<${#nodes[@]}; ++i )); do
      if [[ "$(readlink -f -- "${nodes[i]}")" == "$current_abs" ]]; then
        idx=$i
        break
      fi
    done
  fi

  if (( idx == 0 )); then
    __aap_notice "Already at the first goal."
    exit 0
  fi

  local prev_node="${nodes[idx-1]}"

  if [[ $AICLI_MODE == "coder" ]]; then
    unset AICLI_MODE
    remountctl rw ai-cli "/${REPOBASE}-AAP"
    trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
    export AICLI_MODE="coder"
  fi

  __aap_ensure_status "$PLANROOT" "$prev_node" 1
  __aap_write_status "$PLANROOT" "$prev_node" not-achieved

  local parent_abs
  parent_abs="$(dirname -- "$prev_node")"
  if [[ "$(readlink -f -- "$prev_node")" == "$(readlink -f -- "$objective_tree")" ]]; then
    parent_abs="$prev_node"
  fi
  __aap_rollup_statuses_from "$PLANROOT" "$parent_abs" "$objective_tree"

  ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$prev_node")" "$current_objective_link"
  __aap_notice "Updated current_objective to point to $(basename -- "$prev_node")."
)

aap-previous() {
  __aap_previous_impl "$@"
}
