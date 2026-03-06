__aap_notice() {
  printf '%b%s\n' $'\e[36mNOTICE:\e[0m ' "$*"
}

__aap_warn() {
  printf '%b%s\n' $'\e[31mWARNING:\e[0m ' "$*" >&2
}

__aap_die() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

__aap_rel_to_planroot() {
  local planroot="$1"
  local path="$2"

  if command -v realpath >/dev/null 2>&1; then
    realpath --relative-to="$planroot" "$path"
  else
    case "$path" in
      "$planroot"/*) printf '%s\n' "${path#"$planroot"/}" ;;
      *) printf '%s\n' "$path" ;;
    esac
  fi
}

__aap_is_goal_dir() {
  [[ -d "$1" && "$(basename "$1")" != .* ]]
}

__aap_list_goal_dirs() {
  local node="$1"
  local children=()
  local entry

  while IFS= read -r -d '' entry; do
    children+=("$entry")
  done < <(find "$node" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | LC_ALL=C sort -z)

  local child
  for child in "${children[@]}"; do
    if __aap_is_goal_dir "$child"; then
      printf '%s\0' "$child"
    fi
  done
}

__aap_node_has_goal_dirs() {
  local node="$1"
  local found=""
  found="$(find "$node" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]]
}

__aap_read_status() {
  local planroot="$1"
  local node="$2"
  local status_path="$node/status"

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
    *) __aap_die "Invalid status in $(__aap_rel_to_planroot "$planroot" "$status_path"): '$s' (expected achieved|not-achieved)." ;;
  esac
}

__aap_ensure_description() {
  local planroot="$1"
  local node="$2"
  local fix="$3"

  local desc_path="$node/description"
  if [[ -f "$desc_path" ]]; then
    return 0
  fi

  if __aap_node_has_goal_dirs "$node"; then
    __aap_die "Missing description file: $(__aap_rel_to_planroot "$planroot" "$desc_path") (planner must write it)."
    return 1
  fi

  if (( fix )); then
    __aap_warn "Removing leaf plan node missing description: $(__aap_rel_to_planroot "$planroot" "$node")"
    rm -rf -- "$node"
    return 2
  fi

  __aap_die "Leaf plan node missing description: $(__aap_rel_to_planroot "$planroot" "$node")"
  return 1
}

__aap_ensure_status() {
  local planroot="$1"
  local node="$2"
  local fix="$3"

  local status_path="$node/status"
  if [[ -f "$status_path" ]]; then
    return 0
  fi
  if (( fix )); then
    __aap_warn "Adding missing status file: $(__aap_rel_to_planroot "$planroot" "$status_path")"
    printf 'not-achieved\n' >"$status_path"
    return 0
  fi
  __aap_die "Missing status file: $(__aap_rel_to_planroot "$planroot" "$status_path")"
  return 1
}
