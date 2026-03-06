aap_lib="$PLANROOT/agents-common/bash/aap-lib.bash"
if [[ ! -f "$aap_lib" ]]; then
  echo "ERROR: $aap_lib does not exist." >&2
  return 1 2>/dev/null || exit 1
fi
source "$aap_lib"

aap-ls() (
  # NOTE: This function is intentionally a direct wrapping of the former
  # agents-common/scripts/aap-ls.sh script (no internal refactor).

  set -euo pipefail

  usage() {
    cat <<'EOF'
usage: aap-ls.sh [--fix|--no-fix] [--help]

Print an overview of the current AAP ObjectiveTree and (optionally) fix common
problems to restore invariants.

Options:
  --fix     Apply fixes (default).
  --no-fix  Only report problems; do not modify the ObjectiveTree or symlinks.
  --help  Show this help.
EOF
  }

  fix=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix) fix=1; shift ;;
      --no-fix) fix=0; shift ;;
      --help|-h) usage; exit 0 ;;
      *) echo "aap-ls.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  PLANROOT="${PLANROOT:-$PWD}"
  OBJECTIVE_TREE="${PLANROOT%/}/ObjectiveTree"
  CURRENT_OBJECTIVE_LINK="${PLANROOT%/}/current_objective"

  ensure_description() {
    local node="$1"
    local desc_path="$node/description"
    if [[ -f "$desc_path" ]]; then
      return 0
    fi

    local has_goals=0
    if __aap_node_has_goal_dirs "$node"; then
      has_goals=1
    fi

    if (( has_goals )); then
      __aap_die "Missing description file: $(__aap_rel_to_planroot "$PLANROOT" "$desc_path") (planner must write it)." || exit 1
    fi

    if (( fix )); then
      __aap_warn "Removing leaf plan node missing description: $(__aap_rel_to_planroot "$PLANROOT" "$node")"
      rm -rf -- "$node"
      return 2
    fi

    __aap_die "Leaf plan node missing description: $(__aap_rel_to_planroot "$PLANROOT" "$node")" || exit 1
  }

  ensure_status() {
    local node="$1"
    local status_path="$node/status"
    if [[ -f "$status_path" ]]; then
      return 0
    fi
    if (( fix )); then
      __aap_warn "Adding missing status file: $(__aap_rel_to_planroot "$PLANROOT" "$status_path")"
      printf 'not-achieved\n' >"$status_path"
      return 0
    fi
    __aap_die "Missing status file: $(__aap_rel_to_planroot "$PLANROOT" "$status_path")" || exit 1
  }

  [[ -d "$OBJECTIVE_TREE" ]] || { __aap_die "Missing ObjectiveTree directory: $(__aap_rel_to_planroot "$PLANROOT" "$OBJECTIVE_TREE")"; exit 1; }
  OBJECTIVE_TREE_ABS="$(readlink -f -- "$OBJECTIVE_TREE")"

  seen_not_achieved_leaf=0
  first_not_achieved_leaf=""
  transition_error=""

  traverse() {
    local node="$1"

    ensure_description "$node" || return 0
    ensure_status "$node"

    local children=()
    local child
    while IFS= read -r -d '' child; do
      children+=("$child")
    done < <(__aap_list_goal_dirs "$node")

    local is_leaf=1
    if (( ${#children[@]} > 0 )); then
      is_leaf=0
    fi

    local status
    status="$(__aap_read_status "$PLANROOT" "$node")"

    # Only leaf nodes can be a current objective; internal nodes are objectives for their child goals.
    if (( is_leaf )); then
      if [[ -z "$first_not_achieved_leaf" && "$status" == "not-achieved" ]]; then
        first_not_achieved_leaf="$node"
      fi
      if (( seen_not_achieved_leaf )) && [[ "$status" == "achieved" ]]; then
        transition_error="$node"
      fi
      if [[ "$status" == "not-achieved" ]]; then
        seen_not_achieved_leaf=1
      fi
    fi

    for child in "${children[@]}"; do
      traverse "$child"
    done
  }

  traverse "$OBJECTIVE_TREE"

  if [[ -n "$transition_error" ]]; then
    __aap_die "Invalid status transition: found 'achieved' after first 'not-achieved' at $(__aap_rel_to_planroot "$PLANROOT" "$transition_error")." || exit 1
  fi
  [[ -n "$first_not_achieved_leaf" ]] || { __aap_die "No not-achieved leaf plan node found under $(__aap_rel_to_planroot "$PLANROOT" "$OBJECTIVE_TREE")."; exit 1; }

  desired_current="$first_not_achieved_leaf"
  current_link_exists=0
  current_target_abs=""
  current_target_rel=""

  if [[ -L "$CURRENT_OBJECTIVE_LINK" ]]; then
    current_link_exists=1
    current_target_rel="$(readlink -- "$CURRENT_OBJECTIVE_LINK" 2>/dev/null || true)"
    if current_target_abs="$(readlink -f -- "$CURRENT_OBJECTIVE_LINK" 2>/dev/null)"; then
      :
    else
      __aap_warn "current_objective exists but could not be resolved: $(__aap_rel_to_planroot "$PLANROOT" "$CURRENT_OBJECTIVE_LINK")"
      current_target_abs=""
    fi
  fi

  found_first_rel="$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")"

  if (( current_link_exists )); then
    link_ok=0
    if [[ -n "$current_target_abs" && -d "$current_target_abs" ]]; then
      link_ok=1
    fi

    if (( ! link_ok )); then
      if (( fix )); then
        __aap_warn "current_objective exists but is broken; updating to first not-achieved leaf objective."
        ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$CURRENT_OBJECTIVE_LINK"
        current_target_abs="$(readlink -f -- "$CURRENT_OBJECTIVE_LINK")"
        desired_current="$current_target_abs"
        __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
      else
        __aap_warn "current_objective exists but is broken."
        desired_current="$first_not_achieved_leaf"
      fi
    else
      current_status="$(__aap_read_status "$PLANROOT" "$CURRENT_OBJECTIVE_LINK")"
      current_is_leaf=1
      if __aap_node_has_goal_dirs "$current_target_abs"; then
        current_is_leaf=0
      fi

      eligible=0
      if [[ "$current_status" == "not-achieved" ]] && (( current_is_leaf )); then
        eligible=1
      fi

      if (( fix )); then
        if (( eligible )); then
          desired_current="$current_target_abs"
          if [[ "$(readlink -f -- "$first_not_achieved_leaf")" != "$current_target_abs" ]]; then
            __aap_notice "First not-achieved objective $found_first_rel"
          fi
        else
          if [[ "$current_status" == "achieved" ]]; then
            ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$CURRENT_OBJECTIVE_LINK"
            current_target_abs="$(readlink -f -- "$CURRENT_OBJECTIVE_LINK")"
            desired_current="$current_target_abs"
            __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
          else
            __aap_warn "current_objective points to an internal node or non-leaf objective; updating to first not-achieved leaf objective."
            ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$CURRENT_OBJECTIVE_LINK"
            current_target_abs="$(readlink -f -- "$CURRENT_OBJECTIVE_LINK")"
            desired_current="$current_target_abs"
            __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
          fi
        fi
      else
        # --no-fix: always show what current_objective currently points to (if valid),
        # even if it violates the invariant of being the first not-achieved leaf node.
        desired_current="$current_target_abs"
        if (( eligible )); then
          if [[ "$(readlink -f -- "$first_not_achieved_leaf")" != "$current_target_abs" ]]; then
            __aap_notice "First not-achieved objective $found_first_rel"
          fi
        else
          if [[ "$current_status" == "achieved" ]]; then
            __aap_warn "current_objective points to an achieved node."
          else
            __aap_warn "current_objective points to an internal node or non-leaf objective."
          fi
        fi
      fi
    fi
  else
    if (( fix )); then
      ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$CURRENT_OBJECTIVE_LINK"
      current_target_abs="$(readlink -f -- "$CURRENT_OBJECTIVE_LINK")"
      desired_current="$current_target_abs"
    else
      __aap_warn "current_objective symlink missing."
      desired_current="$first_not_achieved_leaf"
    fi
  fi

  current_node_abs="${desired_current}"
  if [[ "$current_node_abs" != /* ]]; then
    current_node_abs="$(readlink -f -- "$current_node_abs")"
  fi

  if [[ ! -d "$current_node_abs" ]]; then
    __aap_die "Current objective is not a directory: $(__aap_rel_to_planroot "$PLANROOT" "$current_node_abs")" || exit 1
  fi

  parent_node_abs="$(dirname -- "$current_node_abs")"
  if [[ "$current_node_abs" == "$OBJECTIVE_TREE_ABS" ]]; then
    parent_node_abs="$current_node_abs"
  fi

  parent_rel="$(__aap_rel_to_planroot "$PLANROOT" "$parent_node_abs")"
  if [[ "$parent_rel" == "." ]]; then
    parent_rel=""
  fi
  parent_display='$PLANROOT'
  if [[ -n "$parent_rel" ]]; then
    parent_display+="/$parent_rel"
  fi
  parent_display+="/"
  printf 'Parent objective: %s\n' "$parent_display"

  current_rel="$(__aap_rel_to_planroot "$PLANROOT" "$current_node_abs")"
  while IFS= read -r -d '' child; do
    child_name="$(basename -- "$child")"
    child_rel="$(__aap_rel_to_planroot "$PLANROOT" "$child")"
    if [[ "$child_rel" == "$current_rel" ]]; then
      if [[ "$(__aap_read_status "$PLANROOT" "$child")" == "achieved" ]]; then
        printf '%b%s\n' $' *\e[32m🗸\e[0m ' "$child_name"
      else
        printf '  * %s\n' "$child_name"
      fi
    else
      if [[ "$(__aap_read_status "$PLANROOT" "$child")" == "achieved" ]]; then
        printf '%b%s\n' $'  \e[32m🗸\e[0m ' "$child_name"
      else
        printf '    %s\n' "$child_name"
      fi
    fi
  done < <(__aap_list_goal_dirs "$parent_node_abs")

  printf '*) current objective:\n'
  cat -- "$current_node_abs/description"
)
