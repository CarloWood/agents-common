# AAP bash commands.

if [[ -z "${PLANROOT:-}" ]]; then
  echo "ERROR: PLANROOT is not set." >&2
  return 1 2>/dev/null || exit 1
fi

# Source low-level helper and utility functions.
__aap_lib="$PLANROOT/agents-common/bash/aap-lib.bash"
source "$__aap_lib"

# Source AAP commands.
__aap_ls="$PLANROOT/agents-common/bash/aap-ls.bash"
source "$__aap_ls"

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

  local parent_abs
  parent_abs="$(dirname -- "$current_abs")"

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

Move current_objective to the previous leaf goal (depth-first lexicographic
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

  if [[ $AICLI_MODE == "coder" ]]; then
    unset AICLI_MODE
    remountctl rw ai-cli "/${REPOBASE}-AAP"
    trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
    export AICLI_MODE="coder"
  fi

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
  __aap_previous_impl "$@"
}

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
    if ! __aap_is_leaf "$current_abs"; then
      __aap_die "current_objective is not a leaf objective; run aap-ls --fix."
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
  if [[ $AICLI_MODE != "planner" && $AICLI_MODE != "coder" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-configure! This is a 'coder'-agent only function (although the 'planner' can run it too)."
    exit 1
  fi
  if [[ ! -d "$BUILDDIR" || ! -w "$BUILDDIR" ]]; then
    __aap_die "BUILDDIR is not a writable directory."
    exit 1
  fi
  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-configure [cmake args...]

EOF
    echo "Configure $REPOBASE out-of-tree in \$BUILDDIR."
    cat <<'EOF'

Defaults:
  -G ${AAP_GENERATOR:-Ninja}
  -DCMAKE_BUILD_TYPE=${AAP_BUILD_TYPE:-Debug}
EOF
    exit 0
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
  if [[ $AICLI_MODE != "planner" && $AICLI_MODE != "coder" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-build! This is a 'coder'-agent only function (although the 'planner' can run it too)."
    exit 1
  fi

  if [[ ! -d "$BUILDDIR" ]]; then
    __aap_die "\$BUILDDIR ($(abbreviate_path $BUILDDIR)) does not exist; first run aap-configure."
    exit 1
  fi
  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-build [cmake --build args...]

EOF
    echo "Build $REPOBASE in \$BUILDDIR."
    cat <<'EOF'
Uses:
  cmake --build "$BUILDDIR" --parallel ${AAP_BUILD_JOBS:-$(nproc)}
EOF
    exit 0
  fi

  cmake --build "$BUILDDIR" --parallel "${AAP_BUILD_JOBS:-$(nproc)}" "$@"
)

aap-build() {
  __aap_build_impl "$@"
}

__aap_analyst_list_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-analyst-list [--help]

   Print the current analyst Topic List, if one exists.

   Options:
     --help  Show this help.
EOF
    exit 0
  fi

  if [[ ! -r "${PLANROOT}/analyst/current/topics" ]]; then
    echo "No Topic List current exists."
    exit 0
  fi

  echo "Topic List:"
  cat "${PLANROOT}/analyst/current/topics"
)

aap-analyst-list() {
  __aap_analyst_list_impl "$@"
}

__aap_analyst_update_topic_list_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  if [[ $AICLI_MODE != "analyst" ]]; then
    __aap_warn "AICLI_MODE='$AICLI_MODE'"
    __aap_die "aap-analyst-update-topic_list should only be run by the topic_list.js plugin."
    exit 1
  fi

  if (( $# != 1 )); then
    __aap_die "usage: aap-analyst-update-topic-list <text>"
    exit 1
  fi

  local text="$1"
  local topic_list
  topic_list="$(python3 - "$text" <<'PY'
import re
import sys

text = sys.argv[1]
match = re.search(r'(?:^|\n)Topic List:?\n([1-9][\s\S]*?)(?:\n\n|$)', text)
if match:
    sys.stdout.write(match.group(1))
PY
)"

  local current_link="$PLANROOT/analyst/current"
  local topics_path="$current_link/topics"
  if [[ -L "$current_link" || -d "$current_link" ]]; then
    if [[ $AICLI_MODE == "analyst" ]]; then
      unset AICLI_MODE
      remountctl rw ai-cli "/${REPOBASE}-AAP"
      trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
      export AICLI_MODE="analyst"
    fi

    printf '%s' "$topic_list" > "$topics_path"
    if [[ "$topic_list" != *$'\n' ]]; then
      printf '\n' >> "$topics_path"
    fi

  fi
)

aap-analyst-update-topic-list() {
  __aap_analyst_update_topic_list_impl "$@"
}

__aap_analyst_all_done() (
  if ! __aap_is_user; then
    __aap_die "aap-analyst-all-done is a user-only command."
    exit 1
  fi

  local current_link="$PLANROOT/analyst/current"
  local topics_path="$current_link/topics"
  if [[ -L "$current_link" || -d "$current_link" ]]; then
    if [[ $AICLI_MODE == "analyst" || $AICLI_MODE == "coder" ]]; then
      unset AICLI_MODE
      remountctl rw ai-cli "/${REPOBASE}-AAP"
      trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
      export AICLI_MODE="analyst"
    fi

    printf '1. all done\n' > "$topics_path"
  fi
)

aap-analyst-all-done() {
  __aap_analyst_all_done
}

__aap_bootstrap_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  if [[ $AICLI_MODE != "planner" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-bootstrap! This is a 'planner'-agent only function."
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        cat <<'EOF'
usage: aap-bootstrap

Initialize PLANROOT with an initial objective, the main objective.

The description is read from stdin (heredoc/piped input recommended). If stdin
is a TTY, input is read until EOF (Ctrl-D).
EOF
        exit 0
        ;;
      --*) __aap_die "aap-bootstrap: unknown option: $1"; exit 1 ;;
      *) break ;;
    esac
  done

  if (( $# != 0 )); then
    __aap_die "usage: aap-bootstrap"
    exit 1
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ -d "$objective_tree" ]]; then
    __aap_die "ObjectiveTree directory already exist: $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")"
    exit 1
  fi

  if [[ -t 0 ]]; then
    printf 'Enter bootstrap description, then end with Ctrl-D:\n' >&2
  fi

  local desc
  desc="$(cat)"
  local desc_check="${desc//$'\r'/}"
  if [[ -z "${desc_check//[[:space:]]/}" ]]; then
    __aap_die "Empty description."
    exit 1
  fi

  mkdir -p -- "$objective_tree"
  printf '%s' "$desc" >"$objective_tree/description"
  if [[ "$desc" != *$'\n' ]]; then
    printf '\n' >>"$objective_tree/description"
  fi
  printf 'not-achieved\n' >"$objective_tree/status"

  ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")" "$current_objective_link"

  __aap_notice "Updated current_objective to point to $(basename -- "$objective_tree")."
)

aap-bootstrap() {
  __aap_bootstrap_impl "$@"
}

# Export all functions defined here, because the AI needs them and opencode only provides it with exported stuff :/.
for func in $(declare -F | grep '^declare -f ' | sed -e 's/^declare -f //' | grep -E '^(aap-|__aap)'); do
  declare -fx $func
done
