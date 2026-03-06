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

