__aap_insert_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ $AICLI_MODE != "planner" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-insert: The PLANROOT is read-only!"
    exit 1
  fi

  local parent_refpath=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --parent)
        shift
        if [[ $# -lt 1 ]]; then
          __aap_die "usage: aap-insert [--parent <refpath>] <node>"
          exit 1
        fi
        parent_refpath="$1"
        shift
        ;;
      --help|-h)
        cat <<'EOF'
usage: aap-insert [--parent <refpath>] <node>

Insert a new leaf goal node and set it as current_objective.

The description is read from stdin (heredoc/piped input recommended). If stdin
is a TTY, input is read until EOF (Ctrl-D).
EOF
        exit 0
        ;;
      --*) __aap_die "aap-insert: unknown option: $1"; exit 1 ;;
      *) break ;;
    esac
  done

  if (( $# != 1 )); then
    __aap_die "usage: aap-insert [--parent <refpath>] <node>"
    exit 1
  fi

  local node_name="$1"
  if [[ "$node_name" == */* ]]; then
    __aap_die "Node name must not contain '/': '$node_name'"
    exit 1
  fi
  if ! __aap_goal_name_ok "$node_name"; then
    __aap_die "Invalid node name '$node_name' (expected to match ^[0-9][0-9][^-]*-)."
    exit 1
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ ! -d "$objective_tree" ]]; then
    __aap_die "Missing ObjectiveTree directory: $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")"
    exit 1
  fi

  local current_abs=""
  if [[ -L "$current_objective_link" ]]; then
    current_abs="$(readlink -f -- "$current_objective_link" 2>/dev/null || true)"
  fi

  local parent_abs=""
  if [[ -n "$parent_refpath" ]]; then
    parent_abs="$(__aap_resolve_refpath_parent "$PLANROOT" "$objective_tree" "$current_abs" "$parent_refpath")"
  else
    if [[ -z "$current_abs" || ! -d "$current_abs" ]]; then
      __aap_die "current_objective is missing or broken; run aap-ls --fix or use aap-insert --parent /."
      exit 1
    fi
    parent_abs="$(dirname -- "$current_abs")"
    __aap_insert_position_ok "$PLANROOT" "$parent_abs" "$node_name" "$(basename -- "$current_abs")"
  fi

  if [[ $parent_abs != "$PLANROOT/ObjectiveTree" && $parent_abs != "$PLANROOT/ObjectiveTree/"* ]]; then
    if [[ $parent_abs == "$PLANROOT" ]]; then
      __aap_die "Can not add a sibling to the current objective, which is the root objective. Use aap-insert --parent / to add a new objective into ObjectiveTree."
      exit 1
    fi
    __aap_die "Resolved parent is outside ObjectiveTree: $(abbreviate_path $parent_abs)"
    exit 1
  fi

  if [[ ! -d "$parent_abs" ]]; then
    __aap_die "Resolved parent is not a directory: $(__aap_rel_to_planroot "$PLANROOT" "$parent_abs")"
    exit 1
  fi

  __aap_token_unique_in_parent "$PLANROOT" "$parent_abs" "$node_name"

  local new_dir="$parent_abs/$node_name"
  if [[ -e "$new_dir" ]]; then
    __aap_die "Node already exists: $(__aap_rel_to_planroot "$PLANROOT" "$new_dir")"
    exit 1
  fi

  if [[ -t 0 ]]; then
    printf 'Enter description for %s, then end with Ctrl-D:\n' "$node_name" >&2
  fi

  local desc
  desc="$(cat)"
  local desc_check="${desc//$'\r'/}"
  if [[ -z "${desc_check//[[:space:]]/}" ]]; then
    __aap_die "Empty description."
    exit 1
  fi

  mkdir -p -- "$new_dir"
  printf '%s' "$desc" >"$new_dir/description"
  if [[ "$desc" != *$'\n' ]]; then
    printf '\n' >>"$new_dir/description"
  fi
  printf 'not-achieved\n' >"$new_dir/status"

  ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$new_dir")" "$current_objective_link"

  __aap_rollup_statuses_from "$PLANROOT" "$parent_abs" "$objective_tree"

  __aap_notice "Updated current_objective to point to $(basename -- "$new_dir")."
)

aap-insert() {
  __aap_insert_impl "$@"
}
