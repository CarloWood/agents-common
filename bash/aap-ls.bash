# The implementations of `aap-*` commands are defined in a `set -euo pipefail` subshell.
# That gives us “strict mode” without running the risk to permanently changing the caller’s environment.
#
__aap_ls_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  local fix=1
  local default_fix=
  local default_no_fix=
  if [[ $AICLI_MODE != "planner" ]] && ! __aap_is_user; then
    fix=0
    default_no_fix=" (default)"
  else
    default_fix=" (default)"
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fix) fix=1; shift ;;
      --no-fix) fix=0; shift ;;
      --help|-h)
        cat <<EOF
usage: aap-ls [--fix|--no-fix] [--help]

Print an overview of the current AAP ObjectiveTree and (optionally) fix common
problems to restore invariants.

Options:
  --fix     Apply fixes${default_fix}.
  --no-fix  Only report problems; do not modify the ObjectiveTree or symlinks${default_no_fix}.
  --help    Show this help.
EOF
        exit 0
        ;;
      *) echo "aap-ls: unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ ! -d "$objective_tree" ]]; then
    __aap_notice 'No plan exists yet. Use `aap-insert --parent / <node>` to add the first primary objective.'
    exit 0
  fi

  if [[ $AICLI_MODE != "planner" && $fix -eq 1 ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-ls with the argument --fix: The PLANROOT is read-only!"
    exit 1
  fi

  local objective_tree_abs
  objective_tree_abs="$(readlink -f -- "$objective_tree")"

  local first_not_achieved_leaf=""

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
    fi

    # Push children in reverse so we visit them lexicographically depth-first.
    local i
    for (( i=${#children[@]}-1; i>=0; --i )); do
      stack+=("${children[i]}")
    done
  done

  if [[ -z "$first_not_achieved_leaf" ]]; then
    if (( fix )); then
      rm -f -- "$current_objective_link" 2>/dev/null || true
    fi
    __aap_notice "All goals have been achieved."
    printf 'Parent objective: $PLANROOT/ObjectiveTree/\n'
    local child
    while IFS= read -r -d '' child; do
      __aap_print_achieved "  " "$(basename -- "$child")"
    done < <(__aap_list_goal_dirs "$objective_tree")
    printf '@) current objective:\n'
    printf '(all goals achieved)\n'
    exit 0
  fi

  local current_link_exists=0
  local current_target_abs=""
  local current_target_display=""
  if [[ -L "$current_objective_link" ]]; then
    current_link_exists=1
    local raw_target
    raw_target="$(readlink -- "$current_objective_link" 2>/dev/null || true)"
    if [[ -z "$raw_target" ]]; then
      current_target_abs=""
      current_target_display="$(__aap_rel_to_planroot "$PLANROOT" "$current_objective_link")"
    else
      local candidate="$raw_target"
      if [[ "$candidate" != /* ]]; then
        candidate="$PLANROOT/$candidate"
      fi
      if [[ -d "$candidate" ]]; then
        current_target_abs="$(readlink -f -- "$candidate" 2>/dev/null || true)"
      else
        current_target_abs=""
      fi
      if [[ "$raw_target" == /* ]]; then
        current_target_display="$(__aap_rel_to_planroot "$PLANROOT" "$raw_target")"
      else
        current_target_display="$raw_target"
      fi
    fi
  fi

  local desired_current="$first_not_achieved_leaf"

  if (( current_link_exists )); then
    local link_ok=0
    if [[ -n "$current_target_abs" && -d "$current_target_abs" ]]; then
      link_ok=1
    fi

    if (( ! link_ok )); then
      if (( fix )); then
        if [[ -n "$current_target_display" ]]; then
          __aap_warn_out "current_objective points to non-existent $current_target_display:"
        else
          __aap_warn_out "current_objective is broken:"
        fi
        ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$current_objective_link"
        desired_current="$(readlink -f -- "$current_objective_link")"
        __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
      else
        __aap_warn_out "current_objective exists but is broken."
        desired_current="$first_not_achieved_leaf"
      fi
    else
      local current_status
      current_status="$(__aap_read_status "$PLANROOT" "$current_objective_link")"

      local current_is_leaf=1
      if __aap_node_has_goal_dirs "$current_target_abs"; then
        current_is_leaf=0
      fi

      if (( current_is_leaf )); then
        if (( fix )); then
          if [[ "$current_status" == "not-achieved" ]]; then
            desired_current="$current_target_abs"
          else
            ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$current_objective_link"
            desired_current="$(readlink -f -- "$current_objective_link")"
            __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
          fi
        else
          desired_current="$current_target_abs"
          if [[ "$current_status" == "achieved" ]]; then
            __aap_warn "current_objective points to an achieved node."
          fi
        fi
      else
        if (( fix )); then
          __aap_warn_out "current_objective points to an internal node; updating to first not-achieved leaf objective."
          ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$current_objective_link"
          desired_current="$(readlink -f -- "$current_objective_link")"
          __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
        else
          __aap_warn_out "current_objective points to an internal node."
          desired_current="$first_not_achieved_leaf"
        fi
      fi
    fi
  else
    if (( fix )); then
      ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$first_not_achieved_leaf")" "$current_objective_link"
      desired_current="$(readlink -f -- "$current_objective_link")"
      __aap_notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
    else
      __aap_warn_out "current_objective symlink missing."
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
        __aap_print_achieved " @" "$child_name"
      else
        printf '  @ %s\n' "$child_name"
      fi
    else
      if [[ "$child_status" == "achieved" ]]; then
        __aap_print_achieved "  " "$child_name"
      else
        printf '    %s\n' "$child_name"
      fi
    fi
  done < <(__aap_list_goal_dirs "$parent_node_abs")

  printf '@) current objective:\n'
  cat -- "$current_node_abs/description"
)

aap-ls() {
  __aap_ls_impl "$@"
}
