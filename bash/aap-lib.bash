__aap_notice() {
  printf '%b%s\n' $'\e[36mNOTICE:\e[0m ' "$*"
}

__aap_warn() {
  printf '%b%s\n' $'\e[31mWARNING:\e[0m ' "$*" >&2
}

__aap_warn_out() {
  printf '%b%s\n' $'\e[31mWARNING:\e[0m ' "$*"
}

__aap_die() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

__aap_rel_to_planroot() {
  local path="$1"
  realpath --relative-to="$PLANROOT" "$path"
}

__aap_is_goal_dir() {
  [[ -d "$1" && "$(basename "$1")" != .* ]]
}

__aap_list_goal_dirs() {
  local node="$1"
  find "$node" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0 2>/dev/null | LC_ALL=C sort -z
}

__aap_node_has_goal_dirs() {
  local node="$1"
  local found=""
  found="$(find "$node" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]]
}

__aap_read_status() {
  local node="$1"
  local status_path="$node/status"

  if [[ ! -f "$status_path" ]]; then
    printf '%s\n' "not-achieved"
    return 0
  fi

  local s
  s="$(<"$status_path")"
  s="${s//$'\n'/}"
  case "$s" in
    achieved|not-achieved) printf '%s\n' "$s" ;;
    *) __aap_die "Invalid status in $(__aap_rel_to_planroot "$status_path"): '$s' (expected achieved|not-achieved)." ;;
  esac
}

__aap_write_status() {
  local node="$1"
  local value="$2"
  local status_path="$node/status"

  case "$value" in
    achieved|not-achieved) ;;
    *) __aap_die "Invalid status value '$value' for $(__aap_rel_to_planroot "$node")"; return 1 ;;
  esac

  printf '%s\n' "$value" >"$status_path"
}

__aap_ensure_description() {
  local node="$1"
  local fix="$2"

  if [[ $(basename "$node") == "ObjectiveTree" ]]; then
    __aap_die "Erroneously calling __aap_ensure_description on ObjectiveTree."
    return 1
  fi

  local desc_path="$node/description"
  if [[ -f "$desc_path" ]]; then
    return 0
  fi

  if __aap_node_has_goal_dirs "$node"; then
    __aap_die "Missing description file: $(__aap_rel_to_planroot "$desc_path") (planner must write it)."
    return 1
  fi

  if (( fix )); then
    __aap_warn "Removing leaf plan node missing description: $(__aap_rel_to_planroot "$node")"
    rm -rf -- "$node"
    return 2
  fi

  __aap_die "Leaf plan node missing description: $(__aap_rel_to_planroot "$node")"
  return 1
}

__aap_ensure_status() {
  local node="$1"
  local fix="$2"

  if [[ $(basename "$node") == "ObjectiveTree" ]]; then
    __aap_die "Erroneously calling __aap_ensure_status on ObjectiveTree."
    return 1
  fi

  local status_path="$node/status"
  if [[ -f "$status_path" ]]; then
    return 0
  fi
  if (( fix )); then
    __aap_warn "Adding missing status file: $(__aap_rel_to_planroot "$status_path")"
    printf 'not-achieved\n' >"$status_path"
    return 0
  fi
  __aap_die "Missing status file: $(__aap_rel_to_planroot "$status_path")"
  return 1
}

# __aap_list_depth_first_post_order_nodes <root>
#
# Return full paths of all node directories in <root>, in depth-first post-order.
# <root> itself would come after this list, but is not returned.
__aap_list_depth_first_post_order_nodes() {
  local root="$1"
  local child
  while IFS= read -r -d '' child; do
    __aap_list_depth_first_post_order_nodes "$child"
    printf '%s\0' "$child"
  done < <(__aap_list_goal_dirs "$root")
}

# __aap_find_first_not_achieved_node <root>
#
# Print the first not-achieved node in <root>, not including <root> itself.
# Return 0 if successful and 1 if all nodes in <root> have been achieved.
__aap_find_first_not_achieved_node() {
  local root="$1"
  local node

  while IFS= read -r -d '' node; do
    if [[ "$(__aap_read_status "$node")" == "not-achieved" ]]; then
      printf '%s\n' "$node"
      return 0
    fi
  done < <(__aap_list_depth_first_post_order_nodes "$root")

  return 1
}

__aap_rollup_statuses_from() {
  local node="$1"
  local root="$2"

  local root_abs
  root_abs="$(readlink -f -- "$root")"

  local cur
  cur="$(readlink -f -- "$node")"

  while :; do
    if __aap_node_has_goal_dirs "$cur"; then
      __aap_ensure_status "$cur" 1 || return 1

      local all_achieved=1
      local child
      while IFS= read -r -d '' child; do
        if [[ "$(__aap_read_status "$child")" != "achieved" ]]; then
          all_achieved=0
          break
        fi
      done < <(__aap_list_goal_dirs "$cur")

      if (( all_achieved )); then
        __aap_write_status "$cur" achieved || return 1
      else
        __aap_write_status "$cur" not-achieved || return 1
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
  local parent="$1"
  local ref="$2"

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
    __aap_die "Unknown ref '$ref' under $(__aap_rel_to_planroot "$parent")."
    return 1
  fi

  if (( ${#matches[@]} > 1 )); then
    local names=()
    local m
    for m in "${matches[@]}"; do
      names+=("$(basename -- "$m")")
    done
    __aap_die "Ambiguous ref '$ref' under $(__aap_rel_to_planroot "$parent"): ${names[*]}"
    return 1
  fi

  printf '%s\n' "${matches[0]}"
}

__aap_goal_name_ok() {
  local name="$1"
  [[ "$name" =~ ^[0-9][0-9][^-]*- ]]
}

__aap_goal_token() {
  local name="$1"
  printf '%s\n' "${name%%-*}"
}

__aap_ref_matches_element() {
  local ref="$1"
  local element="$2"

  if [[ "$ref" == "." || "$ref" == ".." ]]; then
    return 1
  fi

  local ref_norm
  ref_norm="$(__aap_normalize_ref "$ref")"

  if [[ ! "$ref_norm" =~ ^[0-9][0-9] ]]; then
    return 1
  fi

  [[ "$element" == "$ref_norm"* ]]
}

__aap_resolve_refpath_parent() {
  local objective_tree="$1"
  local current_objective_abs="$2"
  local refpath="$3"

  local objective_tree_abs
  objective_tree_abs="$(readlink -f -- "$objective_tree")"

  if [[ "$refpath" == "/" ]]; then
    printf '%s\n' "$objective_tree_abs"
    return 0
  fi

  if [[ -z "$refpath" ]]; then
    __aap_die "Missing --parent <refpath> value."
    return 1
  fi

  local current_abs=""
  if [[ -n "${current_objective_abs:-}" ]]; then
    current_abs="$(readlink -f -- "$current_objective_abs" 2>/dev/null || true)"
  fi

  local current_rel=""
  if [[ -n "$current_abs" && "$current_abs" == "$objective_tree_abs"* ]]; then
    if command -v realpath >/dev/null 2>&1; then
      current_rel="$(realpath --relative-to="$objective_tree_abs" "$current_abs" 2>/dev/null || true)"
    else
      current_rel="${current_abs#"$objective_tree_abs"/}"
    fi
  fi

  local current_elems=()
  if [[ -n "$current_rel" && "$current_rel" != "." ]]; then
    IFS='/' read -r -a current_elems <<<"$current_rel"
  else
    current_elems=("99-non-existent")
  fi

  local absolute=0
  if [[ "$refpath" == /* ]]; then
    absolute=1
    refpath="${refpath#/}"
  fi

  local refs=()
  IFS='/' read -r -a refs <<<"$refpath"

  local r
  for r in "${refs[@]}"; do
    if [[ -z "$r" ]]; then
      __aap_die "Invalid --parent <refpath>: empty path element."
      return 1
    fi
    if [[ "$r" == "." || "$r" == ".." ]]; then
      __aap_die "Invalid --parent <refpath>: '.' and '..' are not allowed."
      return 1
    fi
  done

  local match_index=-1
  if (( absolute )); then
    if [[ -z "$current_objective_abs" || "${current_elems[0]}" == "99-non-existent" ]]; then
      __aap_die "Cannot resolve absolute --parent '$4' without a valid current_objective (use --parent /)."
      return 1
    fi
    local i
    for (( i=0; i<${#refs[@]}; ++i )); do
      if (( i >= ${#current_elems[@]} )); then
        __aap_die "Absolute --parent '$4' is longer than the current_objective path."
        return 1
      fi
      if ! __aap_ref_matches_element "${refs[i]}" "${current_elems[i]}"; then
        __aap_die "Absolute --parent '$4' does not match the current_objective path at element ${i}."
        return 1
      fi
    done
    match_index=$((${#refs[@]}-1))
  else
    local last_ref="${refs[-1]}"
    local j
    for (( j=${#current_elems[@]}-1; j>=0; --j )); do
      if ! __aap_ref_matches_element "$last_ref" "${current_elems[j]}"; then
        continue
      fi
      local ok=1
      local i
      for (( i=${#refs[@]}-1; i>=0; --i )); do
        local elem_index=$((j - ((${#refs[@]}-1) - i)))
        if (( elem_index < 0 )); then
          ok=0
          break
        fi
        if ! __aap_ref_matches_element "${refs[i]}" "${current_elems[elem_index]}"; then
          ok=0
          break
        fi
      done
      if (( ok )); then
        match_index=$j
        break
      fi
    done
    if (( match_index < 0 )); then
      __aap_die "Could not match --parent '$4' against the current_objective path."
      return 1
    fi
  fi

  local parent="$objective_tree_abs"
  local i
  for (( i=0; i<=match_index && i<${#current_elems[@]}; ++i )); do
    parent+="/${current_elems[i]}"
  done

  printf '%s\n' "$parent"
}

__aap_insert_position_ok() {
  local parent="$1"
  local new_name="$2"
  local current_name="$3"

  local names=()
  local child
  while IFS= read -r -d '' child; do
    names+=("$(basename -- "$child")")
  done < <(__aap_list_goal_dirs "$parent")

  local current_found=0
  local n
  for n in "${names[@]}"; do
    if [[ "$n" == "$current_name" ]]; then
      current_found=1
      break
    fi
  done

  if (( ! current_found )); then
    __aap_die "Current objective '$current_name' is not a direct child of $(__aap_rel_to_planroot "$parent")."
    return 1
  fi

  local sorted=()
  mapfile -t sorted < <(printf '%s\n' "${names[@]}" "$new_name" | LC_ALL=C sort)

  local cur_idx=-1
  local i
  for (( i=0; i<${#sorted[@]}; ++i )); do
    if [[ "${sorted[i]}" == "$current_name" ]]; then
      cur_idx=$i
      break
    fi
  done

  if (( cur_idx <= 0 )); then
    __aap_die "New node '$new_name' must sort immediately before '$current_name' under $(__aap_rel_to_planroot "$parent")."
    return 1
  fi

  if [[ "${sorted[cur_idx-1]}" != "$new_name" ]]; then
    __aap_die "New node '$new_name' must sort immediately before '$current_name' under $(__aap_rel_to_planroot "$parent")."
    return 1
  fi
}

__aap_token_unique_in_parent() {
  local parent="$1"
  local new_name="$2"

  local new_token
  new_token="$(__aap_goal_token "$new_name")"

  local child
  while IFS= read -r -d '' child; do
    local name
    name="$(basename -- "$child")"
    local token
    token="$(__aap_goal_token "$name")"

    if [[ "$token" == "$new_token" ]]; then
      __aap_die "Numeric prefix token '$new_token' is not unique under $(__aap_rel_to_planroot "$parent") (conflicts with '$token')."
      return 1
    fi

    local shorter="$token"
    local longer="$new_token"
    if (( ${#new_token} < ${#token} )); then
      shorter="$new_token"
      longer="$token"
    fi

    if [[ "$longer" == "$shorter"* ]]; then
      # Two-digit refs (e.g. "01") are special-cased to match "01-..." only, so they do
      # not conflict with inserted goals like "01.5-...".
      if [[ ! "$shorter" =~ ^[0-9]{2}$ ]]; then
        __aap_die "Numeric prefix token '$new_token' is not unique under $(__aap_rel_to_planroot "$parent") (conflicts with '$token')."
        return 1
      fi
    fi
  done < <(__aap_list_goal_dirs "$parent")
}

__aap_print_achieved() {
  local prefix="$1"
  local child_name="$2"
  if [[ $AICLI_MODE == "shell" ]]; then
    printf '%s%b%s\n' "$prefix" $'\e[32m🗸\e[0m ' "$child_name"
  else
    printf '%sv %s\n' "$prefix" "$child_name"
  fi
}

__aap_is_user() {
  local magic=$(echo "${OPENCODE_IS_USER_COMMAND:-}" | md5sum | awk '{ print $1 }')
  [[ $magic == "9fad39ae375a33ff8d1e9d2a8af3f268" ]]
}
