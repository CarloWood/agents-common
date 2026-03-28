# AAP bash commands.

if [[ -z "${PLANROOT:-}" ]]; then
  echo "ERROR: PLANROOT is not set." >&2
  return 1 2>/dev/null || exit 1
fi

# Source low-level helper and utility functions.
__aap_lib="$PLANROOT/agents-common/bash/aap-lib.bash"
if [[ ! -f "$__aap_lib" ]]; then
  echo "ERROR: $__aap_lib does not exist." >&2
  return 1 2>/dev/null || exit 1
fi
source "$__aap_lib"

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
      printf '%b%s\n' $'  \e[32m🗸\e[0m ' "$(basename -- "$child")"
    done < <(__aap_list_goal_dirs "$objective_tree")
    printf '*) current objective:\n'
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

__aap_done_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  if (( $# != 1 )); then
    __aap_die "usage: aap-done <ref>"
    exit 2
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
    __aap_die "Missing ObjectiveTree directory: $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")"
    exit 1
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

  local parent_abs
  parent_abs="$(dirname -- "$current_abs")"

  local resolved
  resolved="$(__aap_resolve_ref_in_parent "$PLANROOT" "$parent_abs" "$ref")"
  if [[ "$(readlink -f -- "$resolved")" != "$(readlink -f -- "$current_abs")" ]]; then
    __aap_die "Ref '$ref' does not refer to the current objective ($(basename -- "$current_abs"))."
    exit 1
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
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    __aap_done_impl --help
    return 0
  fi
  __aap_done_impl "$@"
}

__aap_previous_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  if (( $# != 0 )); then
    __aap_die "usage: aap-previous"
    exit 2
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ ! -d "$objective_tree" ]]; then
    __aap_die "Missing ObjectiveTree directory: $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")"
    exit 1
  fi

  local leaves=()
  local leaf
  while IFS= read -r -d '' leaf; do
    leaves+=("$leaf")
  done < <(__aap_list_leaf_nodes "$objective_tree")

  if (( ${#leaves[@]} == 0 )); then
    __aap_die "No leaf goals found under $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")."
    exit 1
  fi

  local idx=${#leaves[@]}
  local current_abs=""
  if [[ -L "$current_objective_link" ]]; then
    current_abs="$(readlink -f -- "$current_objective_link" 2>/dev/null || true)"
  fi
  if [[ -n "$current_abs" && -d "$current_abs" ]] && __aap_is_leaf "$current_abs"; then
    local i
    for (( i=0; i<${#leaves[@]}; ++i )); do
      if [[ "$(readlink -f -- "${leaves[i]}")" == "$current_abs" ]]; then
        idx=$i
        break
      fi
    done
  fi

  if (( idx == 0 )); then
    __aap_notice "Already at the first goal."
    exit 0
  fi

  local prev_leaf="${leaves[idx-1]}"

  __aap_ensure_status "$PLANROOT" "$prev_leaf" 1
  __aap_write_status "$PLANROOT" "$prev_leaf" not-achieved

  local parent_abs
  parent_abs="$(dirname -- "$prev_leaf")"
  if [[ "$(readlink -f -- "$prev_leaf")" == "$(readlink -f -- "$objective_tree")" ]]; then
    parent_abs="$prev_leaf"
  fi
  __aap_rollup_statuses_from "$PLANROOT" "$parent_abs" "$objective_tree"

  ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$prev_leaf")" "$current_objective_link"
  __aap_notice "Updated current_objective to point to $(basename -- "$prev_leaf")."
)

aap-previous() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
usage: aap-previous

Move current_objective to the previous leaf goal (depth-first lexicographic
order) and mark it not-achieved.
EOF
    return 0
  fi
  __aap_previous_impl "$@"
}

__aap_insert_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  local parent_refpath=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --parent)
        shift
        if [[ $# -lt 1 ]]; then
          __aap_die "usage: aap-insert [--parent <refpath>] <node>"
          exit 2
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
      --*) __aap_die "aap-insert: unknown option: $1"; exit 2 ;;
      *) break ;;
    esac
  done

  if (( $# != 1 )); then
    __aap_die "usage: aap-insert [--parent <refpath>] <node>"
    exit 2
  fi

  local node_name="$1"
  if [[ "$node_name" == */* ]]; then
    __aap_die "Node name must not contain '/': '$node_name'"
    exit 2
  fi
  if ! __aap_goal_name_ok "$node_name"; then
    __aap_die "Invalid node name '$node_name' (expected to match ^[0-9][0-9][^-]*-)."
    exit 2
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
    if ! __aap_is_leaf "$current_abs"; then
      __aap_die "current_objective is not a leaf objective; run aap-ls --fix."
      exit 1
    fi
    parent_abs="$(dirname -- "$current_abs")"
    __aap_insert_position_ok "$PLANROOT" "$parent_abs" "$node_name" "$(basename -- "$current_abs")"
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

__aap_configure_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ -z "${REPOROOT:-}" ]]; then
    __aap_die "REPOROOT is not set."
    exit 1
  fi
  if [[ -z "${BUILDDIR:-}" ]]; then
    __aap_die "BUILDDIR is not set."
    exit 1
  fi

  local build_type="${AAP_BUILD_TYPE:-Debug}"
  local generator="${AAP_GENERATOR:-Ninja}"

  local have_generator=0
  local have_build_type=0
  local arg
  for arg in "$@"; do
    case "$arg" in
      -G|--generator) have_generator=1 ;;
      -DCMAKE_BUILD_TYPE=*) have_build_type=1 ;;
    esac
  done

  mkdir -p -- "$BUILDDIR"

  local -a cmd=(cmake -S "$REPOROOT" -B "$BUILDDIR")
  if (( ! have_generator )); then
    cmd+=(-G "$generator")
  fi
  if (( ! have_build_type )); then
    cmd+=("-DCMAKE_BUILD_TYPE=$build_type")
  fi
  cmd+=("$@")

  "${cmd[@]}"
)

aap-configure() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
usage: aap-configure [cmake args...]

EOF
    echo "Configure $REPOBASE out-of-tree in \$BUILDDIR."
    cat <<'EOF'

Defaults:
  -G ${AAP_GENERATOR:-Ninja}
  -DCMAKE_BUILD_TYPE=${AAP_BUILD_TYPE:-Debug}
EOF
    return 0
  fi
  __aap_configure_impl "$@"
}

__aap_build_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ -z "${BUILDDIR:-}" ]]; then
    __aap_die "BUILDDIR is not set."
    exit 1
  fi

  if [[ ! -d "$BUILDDIR" ]]; then
    __aap_die "\$BUILDDIR ($(abbreviate_path $BUILDDIR)) does not exist; first run aap-configure."
    exit 1
  fi

  cmake --build "$BUILDDIR" --parallel "${AAP_BUILD_JOBS:-$(nproc)}" "$@"
)

aap-build() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
usage: aap-build [cmake --build args...]

EOF
    echo "Build $REPOBASE in \$BUILDDIR."
    cat <<'EOF'
Uses:
  cmake --build "$BUILDDIR" --parallel ${AAP_BUILD_JOBS:-$(nproc)}
EOF
    return 0
  fi
  __aap_build_impl "$@"
}
