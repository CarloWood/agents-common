# The implementations of `aap-*` commands are defined in a `set -euo pipefail` subshell.
# That gives us “strict mode” without running the risk to permanently changing the caller’s environment.

# __aap_ls_impl [OPTIONS]
#
# If no current_objective exists and --fix is given or the default,
# then try to find the first not-achieved node if any and create
# current_objective if found.
#
# Print the 'Parent refpath: ' followed by the <refpath> of the parent of the current_objective,
# or if no current_objective exists, print 'Parent refpath: /'.
#
# If all nodes are achieved then print all primary nodes with a 'v' in front of them
# and then print '(all goals achieved)' at the end.
#
# Otherwise print the goals of the parent of the current objective with a 'v' in front
# of those that are already achieved, and finally print '@) current objective:'
# followed by the contents of the `description` file of the current objective.
#
# Printing of goals is done by calling:
# __aap_print_achieved "  " "$child"
# for child goals that are not current, and
# __aap_print_achieved " @" "$child"
# for the child goal that current_directory is pointing at.
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
  if [[ $AICLI_MODE != "planner" ]]; then
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

Print an overview of the current plan and (optionally) fix common
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

  if [[ $AICLI_MODE != "planner" && $fix -eq 1 ]]; then
    if __aap_is_user; then
      __aap_die "Can not use --fix while the agent is not \"planner\": PLANROOT is read-only."
    else
      __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-ls with the argument --fix: The PLANROOT is read-only!"
    fi
    exit 1
  fi

  # Call `__aap_ensure_description` and `__aap_ensure_status` on all nodes,
  local node
  while IFS= read -r -d '' node; do
    local ensure_description_rc=0
    if ! __aap_ensure_description "$node" "$fix"; then
      ensure_description_rc=$?
      if (( ensure_description_rc == 2 )); then
        # node was removed.
        continue
      fi
      exit "$ensure_description_rc"
    fi
    __aap_ensure_status "$node" "$fix"
  done < <(__aap_list_depth_first_post_order_nodes "$objective_tree")

  # Find the first not-achieved node in the tree, if any.
  local first_not_achieved_node=""
  first_not_achieved_node="$(__aap_find_first_not_achieved_node "$objective_tree" || true)"

  # If all nodes are achieved then print all primary nodes with a 'v' in front
  # and then print '(all goals achieved)' at the end.
  if [[ -z "$first_not_achieved_node" ]]; then
    if (( fix )); then
      rm -f -- "$current_objective_link" 2>/dev/null || true
    fi
    printf 'Parent refpath: /\n'
    local child
    while IFS= read -r -d '' child; do
      __aap_print_achieved "  " "$(basename -- "$child")"
    done < <(__aap_list_goal_dirs "$objective_tree")
    printf '(all goals achieved)\n'
    exit 0
  fi

  local objective_tree_abs
  objective_tree_abs="$(readlink -f -- "$objective_tree")"

  local current_node_abs=""
  local current_target_abs=""
  local repair_reason=""
  if [[ -L "$current_objective_link" ]]; then
    local raw_target
    raw_target="$(readlink -- "$current_objective_link" 2>/dev/null || true)"
    if [[ -n "$raw_target" ]]; then
      local candidate="$raw_target"
      if [[ "$candidate" != /* ]]; then
        candidate="$PLANROOT/$candidate"
      fi
      if [[ -d "$candidate" ]]; then
        current_target_abs="$(readlink -f -- "$candidate")"
      fi
    fi

    if [[ -z "$current_target_abs" ]]; then
      repair_reason="current_objective exists but is broken."
    elif [[ "$current_target_abs" != "$objective_tree_abs"/* ]]; then
      repair_reason="current_objective points outside ObjectiveTree."
    else
      current_node_abs="$current_target_abs"
    fi
  else
    repair_reason="current_objective symlink missing."
  fi

  if [[ -z "$repair_reason" && "$current_node_abs" != "$first_not_achieved_node" ]]; then
    repair_reason="current_objective does not point to the first not-achieved node."
  fi

  if [[ -n "$repair_reason" ]]; then
    if (( fix )); then
      ln -snf -- "$(__aap_rel_to_planroot "$first_not_achieved_node")" "$current_objective_link"
      current_node_abs="$(readlink -f -- "$current_objective_link")"
      __aap_notice "Updated current_objective to point to $(__aap_refpath_of "$current_node_abs")."
    else
      __aap_warn_out "$repair_reason"
      if [[ -z "$current_node_abs" ]]; then
        current_node_abs="$first_not_achieved_node"
      fi
    fi
  fi

  local parent_node_abs
  parent_node_abs="$(dirname -- "$current_node_abs")"
  printf 'Parent refpath: %s\n' "$(__aap_refpath_of "$parent_node_abs")"

  while IFS= read -r -d '' child; do
    local child_name
    child_name="$(basename -- "$child")"
    if [[ "$child" == "$current_node_abs" ]]; then
      if [[ "$(__aap_read_status "$child")" == "achieved" ]]; then
        __aap_print_achieved " @" "$child_name"
      else
        printf '  @ %s\n' "$child_name"
      fi
    elif [[ "$(__aap_read_status "$child")" == "achieved" ]]; then
      __aap_print_achieved "  " "$child_name"
    else
      printf '    %s\n' "$child_name"
    fi
  done < <(__aap_list_goal_dirs "$parent_node_abs")

  printf '@) current objective:\n'
  cat -- "$current_node_abs/description"
)

aap-ls() {
  __aap_ls_impl "$@"
}
