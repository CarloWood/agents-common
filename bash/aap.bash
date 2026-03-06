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

  notice() { printf '%b%s\n' $'\e[36mNOTICE:\e[0m ' "$*"; }
  warn() { printf '%b%s\n' $'\e[31mWARNING:\e[0m ' "$*" >&2; }
  die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

  rel_to_planroot() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
      realpath --relative-to="$PLANROOT" "$path"
    else
      case "$path" in
        "$PLANROOT"/*) printf '%s\n' "${path#"$PLANROOT"/}" ;;
        *) printf '%s\n' "$path" ;;
      esac
    fi
  }

  is_goal_dir() {
    [[ -d "$1" && "$(basename "$1")" != .* ]]
  }

  list_goal_dirs() {
    local node="$1"
    local children=()
    local entry
    while IFS= read -r -d '' entry; do
      children+=("$entry")
    done < <(find "$node" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | LC_ALL=C sort -z)
    local child
    for child in "${children[@]}"; do
      if is_goal_dir "$child"; then
        printf '%s\0' "$child"
      fi
    done
  }

  node_has_goal_dirs() {
    local node="$1"
    local found=""
    found="$(find "$node" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print -quit 2>/dev/null || true)"
    [[ -n "$found" ]]
  }

  ensure_description() {
    local node="$1"
    local desc_path="$node/description"
    if [[ -f "$desc_path" ]]; then
      return 0
    fi

    local has_goals=0
    if node_has_goal_dirs "$node"; then
      has_goals=1
    fi

    if (( has_goals )); then
      die "Missing description file: $(rel_to_planroot "$desc_path") (planner must write it)."
    fi

    if (( fix )); then
      warn "Removing leaf plan node missing description: $(rel_to_planroot "$node")"
      rm -rf -- "$node"
      return 2
    fi

    die "Leaf plan node missing description: $(rel_to_planroot "$node")"
  }

  ensure_status() {
    local node="$1"
    local status_path="$node/status"
    if [[ -f "$status_path" ]]; then
      return 0
    fi
    if (( fix )); then
      warn "Adding missing status file: $(rel_to_planroot "$status_path")"
      printf 'not-achieved\n' >"$status_path"
      return 0
    fi
    die "Missing status file: $(rel_to_planroot "$status_path")"
  }

  read_status() {
    local status_path="$1/status"
    if [[ ! -f "$status_path" ]]; then
      printf '%s\n' "not-achieved"
      return 0
    fi
    local s
    s="$(<"$status_path")"
    s="${s//$'\r'/}"
    s="${s//$'\n'/}"
    case "$s" in
      achieved|not-achieved) printf '%s\n' "$s" ;;
      *) die "Invalid status in $(rel_to_planroot "$status_path"): '$s' (expected achieved|not-achieved)." ;;
    esac
  }

  [[ -d "$OBJECTIVE_TREE" ]] || die "Missing ObjectiveTree directory: $(rel_to_planroot "$OBJECTIVE_TREE")"
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
    done < <(list_goal_dirs "$node")

    local is_leaf=1
    if (( ${#children[@]} > 0 )); then
      is_leaf=0
    fi

    local status
    status="$(read_status "$node")"

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
    die "Invalid status transition: found 'achieved' after first 'not-achieved' at $(rel_to_planroot "$transition_error")."
  fi
  [[ -n "$first_not_achieved_leaf" ]] || die "No not-achieved leaf plan node found under $(rel_to_planroot "$OBJECTIVE_TREE")."

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
      warn "current_objective exists but could not be resolved: $(rel_to_planroot "$CURRENT_OBJECTIVE_LINK")"
      current_target_abs=""
    fi
  fi

  found_first_rel="$(rel_to_planroot "$first_not_achieved_leaf")"

  if (( current_link_exists )); then
    link_ok=0
    if [[ -n "$current_target_abs" && -d "$current_target_abs" ]]; then
      link_ok=1
    fi

    if (( ! link_ok )); then
      if (( fix )); then
        warn "current_objective exists but is broken; updating to first not-achieved leaf objective."
        ln -snf -- "$(rel_to_planroot "$first_not_achieved_leaf")" "$CURRENT_OBJECTIVE_LINK"
        current_target_abs="$(readlink -f -- "$CURRENT_OBJECTIVE_LINK")"
        desired_current="$current_target_abs"
        notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
      else
        warn "current_objective exists but is broken."
        desired_current="$first_not_achieved_leaf"
      fi
    else
      current_status="$(read_status "$CURRENT_OBJECTIVE_LINK")"
      current_is_leaf=1
      if node_has_goal_dirs "$current_target_abs"; then
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
            notice "First not-achieved objective $found_first_rel"
          fi
        else
          if [[ "$current_status" == "achieved" ]]; then
            ln -snf -- "$(rel_to_planroot "$first_not_achieved_leaf")" "$CURRENT_OBJECTIVE_LINK"
            current_target_abs="$(readlink -f -- "$CURRENT_OBJECTIVE_LINK")"
            desired_current="$current_target_abs"
            notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
          else
            warn "current_objective points to an internal node or non-leaf objective; updating to first not-achieved leaf objective."
            ln -snf -- "$(rel_to_planroot "$first_not_achieved_leaf")" "$CURRENT_OBJECTIVE_LINK"
            current_target_abs="$(readlink -f -- "$CURRENT_OBJECTIVE_LINK")"
            desired_current="$current_target_abs"
            notice "Updated current_objective to point to $(basename -- "$first_not_achieved_leaf")."
          fi
        fi
      else
        # --no-fix: always show what current_objective currently points to (if valid),
        # even if it violates the invariant of being the first not-achieved leaf node.
        desired_current="$current_target_abs"
        if (( eligible )); then
          if [[ "$(readlink -f -- "$first_not_achieved_leaf")" != "$current_target_abs" ]]; then
            notice "First not-achieved objective $found_first_rel"
          fi
        else
          if [[ "$current_status" == "achieved" ]]; then
            warn "current_objective points to an achieved node."
          else
            warn "current_objective points to an internal node or non-leaf objective."
          fi
        fi
      fi
    fi
  else
    if (( fix )); then
      ln -snf -- "$(rel_to_planroot "$first_not_achieved_leaf")" "$CURRENT_OBJECTIVE_LINK"
      current_target_abs="$(readlink -f -- "$CURRENT_OBJECTIVE_LINK")"
      desired_current="$current_target_abs"
    else
      warn "current_objective symlink missing."
      desired_current="$first_not_achieved_leaf"
    fi
  fi

  current_node_abs="${desired_current}"
  if [[ "$current_node_abs" != /* ]]; then
    current_node_abs="$(readlink -f -- "$current_node_abs")"
  fi

  if [[ ! -d "$current_node_abs" ]]; then
    die "Current objective is not a directory: $(rel_to_planroot "$current_node_abs")"
  fi

  parent_node_abs="$(dirname -- "$current_node_abs")"
  if [[ "$current_node_abs" == "$OBJECTIVE_TREE_ABS" ]]; then
    parent_node_abs="$current_node_abs"
  fi

  parent_rel="$(rel_to_planroot "$parent_node_abs")"
  if [[ "$parent_rel" == "." ]]; then
    parent_rel=""
  fi
  parent_display='$PLANROOT'
  if [[ -n "$parent_rel" ]]; then
    parent_display+="/$parent_rel"
  fi
  parent_display+="/"
  printf 'Parent objective: %s\n' "$parent_display"

  current_rel="$(rel_to_planroot "$current_node_abs")"
  while IFS= read -r -d '' child; do
    child_name="$(basename -- "$child")"
    child_rel="$(rel_to_planroot "$child")"
    if [[ "$child_rel" == "$current_rel" ]]; then
      if [[ "$(read_status "$child")" == "achieved" ]]; then
        printf '%b%s\n' $' *\e[32m🗸\e[0m ' "$child_name"
      else
        printf '  * %s\n' "$child_name"
      fi
    else
      if [[ "$(read_status "$child")" == "achieved" ]]; then
        printf '%b%s\n' $'  \e[32m🗸\e[0m ' "$child_name"
      else
        printf '    %s\n' "$child_name"
      fi
    fi
  done < <(list_goal_dirs "$parent_node_abs")

  printf '*) current objective:\n'
  cat -- "$current_node_abs/description"
)

