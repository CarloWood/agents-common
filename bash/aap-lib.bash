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

__aap_write_status() {
  local planroot="$1"
  local node="$2"
  local value="$3"
  local status_path="$node/status"

  case "$value" in
    achieved|not-achieved) ;;
    *) __aap_die "Invalid status value '$value' for $(__aap_rel_to_planroot "$planroot" "$node")"; return 1 ;;
  esac

  printf '%s\n' "$value" >"$status_path"
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

__aap_is_leaf() {
  local node="$1"
  ! __aap_node_has_goal_dirs "$node"
}

__aap_list_leaf_nodes() {
  local root="$1"
  local stack=("$root")

  while (( ${#stack[@]} > 0 )); do
    local node="${stack[-1]}"
    unset 'stack[-1]'

    local children=()
    local child
    while IFS= read -r -d '' child; do
      children+=("$child")
    done < <(__aap_list_goal_dirs "$node")

    if (( ${#children[@]} == 0 )); then
      printf '%s\0' "$node"
      continue
    fi

    # Push children in reverse so we visit them lexicographically depth-first.
    local i
    for (( i=${#children[@]}-1; i>=0; --i )); do
      stack+=("${children[i]}")
    done
  done
}

__aap_find_first_not_achieved_leaf() {
  local planroot="$1"
  local root="$2"
  local leaf

  while IFS= read -r -d '' leaf; do
    if [[ "$(__aap_read_status "$planroot" "$leaf")" == "not-achieved" ]]; then
      printf '%s\n' "$leaf"
      return 0
    fi
  done < <(__aap_list_leaf_nodes "$root")

  return 1
}

__aap_rollup_statuses_from() {
  local planroot="$1"
  local node="$2"
  local root="$3"

  local root_abs
  root_abs="$(readlink -f -- "$root")"

  local cur
  cur="$(readlink -f -- "$node")"

  while :; do
    if __aap_node_has_goal_dirs "$cur"; then
      __aap_ensure_status "$planroot" "$cur" 1 || return 1

      local all_achieved=1
      local child
      while IFS= read -r -d '' child; do
        if [[ "$(__aap_read_status "$planroot" "$child")" != "achieved" ]]; then
          all_achieved=0
          break
        fi
      done < <(__aap_list_goal_dirs "$cur")

      if (( all_achieved )); then
        __aap_write_status "$planroot" "$cur" achieved || return 1
      else
        __aap_write_status "$planroot" "$cur" not-achieved || return 1
      fi
    fi

    [[ "$cur" == "$root_abs" ]] && break
    cur="$(dirname -- "$cur")"
  done
}

__aap_normalize_ref() {
  local ref="$1"
  # Allow omitting the leading 0 for single-digit prefixes (e.g. "2" -> "02", "2.5" -> "02.5", "2-mark" -> "02-mark").
  if [[ "$ref" =~ ^[1-9]($|[.-]) ]]; then
    ref="0$ref"
  fi
  printf '%s\n' "$ref"
}

__aap_resolve_ref_in_parent() {
  local planroot="$1"
  local parent="$2"
  local ref="$3"

  local ref_norm
  ref_norm="$(__aap_normalize_ref "$ref")"

  if [[ "$ref_norm" =~ ^[0-9]{1,2}\.$ ]]; then
    __aap_die "Invalid ref '$ref' (must not end in '.')."
    return 1
  fi

  local match_prefix="$ref_norm"
  if [[ "$ref_norm" =~ ^[0-9]{2}$ ]]; then
    # "01" must refer to "01-..." and not "01.5-...".
    match_prefix="${ref_norm}-"
  fi

  local matches=()
  local child
  while IFS= read -r -d '' child; do
    local name
    name="$(basename -- "$child")"
    if [[ "$name" == "$match_prefix"* ]]; then
      matches+=("$child")
    fi
  done < <(__aap_list_goal_dirs "$parent")

  if (( ${#matches[@]} == 0 )); then
    __aap_die "Unknown ref '$ref' under $(__aap_rel_to_planroot "$planroot" "$parent")."
    return 1
  fi

  if (( ${#matches[@]} > 1 )); then
    local names=()
    local m
    for m in "${matches[@]}"; do
      names+=("$(basename -- "$m")")
    done
    __aap_die "Ambiguous ref '$ref' under $(__aap_rel_to_planroot "$planroot" "$parent"): ${names[*]}"
    return 1
  fi

  printf '%s\n' "${matches[0]}"
}
