# AAP bash commands.

if [[ -z "${PLANROOT:-}" ]]; then
  echo "ERROR: PLANROOT is not set." >&2
  return 1 2>/dev/null || exit 1
fi

__aap_lib="$PLANROOT/agents-common/bash/aap-lib.bash"
if [[ ! -f "$__aap_lib" ]]; then
  echo "ERROR: $__aap_lib does not exist." >&2
  return 1 2>/dev/null || exit 1
fi
source "$__aap_lib"

__aap_ls_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  local fix=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix) fix=1; shift ;;
      --no-fix) fix=0; shift ;;
      --help|-h)
        cat <<'EOF'
usage: aap-ls [--fix|--no-fix] [--help]

Print an overview of the current AAP ObjectiveTree and (optionally) fix common
problems to restore invariants.

Options:
  --fix     Apply fixes (default).
  --no-fix  Only report problems; do not modify the ObjectiveTree or symlinks.
  --help    Show this help.
EOF
        exit 0
        ;;
      *) echo "aap-ls: unknown argument: $1" >&2; exit 2 ;;
    esac
  done

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ ! -d "$objective_tree" ]]; then
    __aap_die "Missing ObjectiveTree directory: $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")"
    exit 1
  fi

  local objective_tree_abs
  objective_tree_abs="$(readlink -f -- "$objective_tree")"

  local seen_not_achieved_leaf=0
  local first_not_achieved_leaf=""
  local transition_error=""

  local stack=("$objective_tree")
  while (( ${#stack[@]} > 0 )); do
    local node="${stack[-1]}"
    unset 'stack[-1]'

    if ! __aap_ensure_description "$PLANROOT" "$node" "$fix"; then
      continue
    fi
    __aap_ensure_status "$PLANROOT" "$node" "$fix"

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

    # Push children in reverse so we visit them lexicographically depth-first.
    local i
    for (( i=${#children[@]}-1; i>=0; --i )); do
      stack+=("${children[i]}")
    done
  done

  if [[ -n "$transition_error" ]]; then
    __aap_die "Invalid status transition: found 'achieved' after first 'not-achieved' at $(__aap_rel_to_planroot "$PLANROOT" "$transition_error")."
    exit 1
  fi
  if [[ -z "$first_not_achieved_leaf" ]]; then
    __aap_die "No not-achieved leaf plan node found under $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")."
    exit 1
  fi

  local desired_current="$first_not_achieved_leaf"

  local current_link_exists=0
  local current_target_abs=""
  if [[ -L "$current_objective_link" ]]; then
    current_link_exists=1
    if ! current_target_abs="$(readlink -f -- "$current_objective_link" 2>/dev/null)"; then
      __aap_warn "current_objective exists but could not be resolved: $(__aap_rel_to_planroot "$PLANROOT" "$current_objective_link")"
      current_target_abs=""
    fi
  fi

  local found_first_rel
  found_first_rel="$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")"

  if (( current_link_exists )); then
    local link_ok=0
    if [[ -n "$current_target_abs" && -d "$current_target_abs" ]]; then
      link_ok=1
    fi

    if (( ! link_ok )); then
      if (( fix )); then
        __aap_warn "current_objective exists but is broken; updating to first not-achieved leaf objective."
        ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$current_objective_link"
        desired_current="$(readlink -f -- "$current_objective_link")"
        __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
      else
        __aap_warn "current_objective exists but is broken."
        desired_current="$first_not_achieved_leaf"
      fi
    else
      local current_status
      current_status="$(__aap_read_status "$PLANROOT" "$current_objective_link")"

      local current_is_leaf=1
      if __aap_node_has_goal_dirs "$current_target_abs"; then
        current_is_leaf=0
      fi

      local eligible=0
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
            ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$current_objective_link"
            desired_current="$(readlink -f -- "$current_objective_link")"
            __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
          else
            __aap_warn "current_objective points to an internal node or non-leaf objective; updating to first not-achieved leaf objective."
            ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$current_objective_link"
            desired_current="$(readlink -f -- "$current_objective_link")"
            __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
          fi
        fi
      else
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
      ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$current_objective_link"
      desired_current="$(readlink -f -- "$current_objective_link")"
    else
      __aap_warn "current_objective symlink missing."
      desired_current="$first_not_achieved_leaf"
    fi
  fi

  local current_node_abs="$desired_current"
  if [[ "$current_node_abs" != /* ]]; then
    current_node_abs="$(readlink -f -- "$current_node_abs")"
  fi

  if [[ ! -d "$current_node_abs" ]]; then
    __aap_die "Current objective is not a directory: $(__aap_rel_to_planroot "$PLANROOT" "$current_node_abs")"
    exit 1
  fi

  local parent_node_abs
  parent_node_abs="$(dirname -- "$current_node_abs")"
  if [[ "$current_node_abs" == "$objective_tree_abs" ]]; then
    parent_node_abs="$current_node_abs"
  fi

  local parent_rel
  parent_rel="$(__aap_rel_to_planroot "$PLANROOT" "$parent_node_abs")"
  if [[ "$parent_rel" == "." ]]; then
    parent_rel=""
  fi

  local parent_display='$PLANROOT'
  if [[ -n "$parent_rel" ]]; then
    parent_display+="/$parent_rel"
  fi
  parent_display+="/"
  printf 'Parent objective: %s\n' "$parent_display"

  local current_rel
  current_rel="$(__aap_rel_to_planroot "$PLANROOT" "$current_node_abs")"

  while IFS= read -r -d '' child; do
    local child_name
    child_name="$(basename -- "$child")"

    local child_rel
    child_rel="$(__aap_rel_to_planroot "$PLANROOT" "$child")"

    local child_status
    child_status="$(__aap_read_status "$PLANROOT" "$child")"

    if [[ "$child_rel" == "$current_rel" ]]; then
      if [[ "$child_status" == "achieved" ]]; then
        printf '%b%s\n' $' *\e[32m🗸\e[0m ' "$child_name"
      else
        printf '  * %s\n' "$child_name"
      fi
    else
      if [[ "$child_status" == "achieved" ]]; then
        printf '%b%s\n' $'  \e[32m🗸\e[0m ' "$child_name"
      else
        printf '    %s\n' "$child_name"
      fi
    fi
  done < <(__aap_list_goal_dirs "$parent_node_abs")

  printf '*) current objective:\n'
  cat -- "$current_node_abs/description"
)

aap-ls() {
  __aap_ls_impl "$@"
}

