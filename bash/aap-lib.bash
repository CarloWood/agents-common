# __aap_notice <message...>
#
# Print an informational notice to stdout using the standard AAP notice prefix.
__aap_notice() {
  printf '%b%s\n' $'\e[36mNOTICE:\e[0m ' "$*"
}

# __aap_warn <message...>
#
# Print a warning to stderr using the standard AAP warning prefix.
__aap_warn() {
  printf '%b%s\n' $'\e[31mWARNING:\e[0m ' "$*" >&2
}

# __aap_warn_out <message...>
#
# Print a warning to stdout; use when warnings should appear in command output.
__aap_warn_out() {
  printf '%b%s\n' $'\e[31mWARNING:\e[0m ' "$*"
}

# __aap_die <message...>
#
# Print an error to stderr and return failure; callers may rely on set -e unless called in a conditional context.
__aap_die() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

# __aap_rel_to_planroot <path>
#
# Print <path> relative to $PLANROOT, for human-readable diagnostics and symlink targets.
__aap_rel_to_planroot() {
  local path="$1"
  realpath --relative-to="$PLANROOT" "$path"
}

# __aap_is_goal_dir <path>
#
# Return success if <path> is a visible plan child directory.
__aap_is_goal_dir() {
  [[ -d "$1" && "$(basename "$1")" != .* ]]
}

# __aap_list_goal_dirs <node>
#
# Print NUL-separated direct child plan-node directories of <node>, sorted lexicographically.
__aap_list_goal_dirs() {
  local node="$1"
  find "$node" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print0 2>/dev/null | LC_ALL=C sort -z
}

# __aap_node_has_goal_dirs <node>
#
# Return success if <node> has at least one visible child plan-node directory.
__aap_node_has_goal_dirs() {
  local node="$1"
  local found=""
  found="$(find "$node" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]]
}

# __aap_read_status <node>
#
# Print the status of <node>: either `achieved` or `not-achieved`.
# Missing status files are treated as `not-achieved` so callers can repair them.
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

# __aap_write_status <node> <achieved|not-achieved>
#
# Validate and write the exact status value for <node>.
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

# __aap_ensure_description <node> <fix>
#
# Ensure <node>/description exists. If <fix> is true and a leaf lacks a description,
# remove that malformed leaf and return 2; return failure for non-leaf nodes or ObjectiveTree.
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

# __aap_ensure_status <node> <fix>
#
# Ensure <node>/status exists. If <fix> is true, create/propagate a not-achieved
# status for <node>; return failure for ObjectiveTree or unfixable missing status.
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
    __aap_rollup_not_achieved_from "$node" "$PLANROOT/ObjectiveTree"
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

# __aap_refpath_of <node>
#
# Print an abbreviated but unique absolute refpath for <node>.
# For example if <node> is `x/y/ObjectiveTree/04.5-foo/01-leaf`
# and `x/y/ObjectiveTree/04.51-foo/01-leaf` also exists then
# this will print `/04.5-/01-leaf`.
__aap_refpath_of() {
  local node="$1"
  local rel parent part abbrev out
  local -a parts
  local sibling sibling_base
  local need_hyphen

  rel="${node#*/ObjectiveTree}"

  if [[ $rel == "$node" ]]; then
    echo "__aap_refpath_of: Not below ObjectiveTree: $node" >&2
    return 1
  fi

  rel="${rel#/}"

  if [[ -z $rel ]]; then
    printf '/\n'
    return 0
  fi

  IFS=/ read -r -a parts <<< "$rel"

  parent="${node%/ObjectiveTree/*}/ObjectiveTree"
  out=

  for part in "${parts[@]:0:${#parts[@]}-1}"; do
    abbrev="${part%%-*}"

    # If there is no hyphen, don't abbreviate this component.
    if [[ $abbrev == "$part" ]]; then
      out+="/$part"
      parent+="/$part"
      continue
    fi

    need_hyphen=false

    for sibling in "$parent"/"$abbrev"*; do
      [[ -d $sibling ]] || continue

      sibling_base="${sibling##*/}"

      if [[ $sibling_base != "$part" ]]; then
        need_hyphen=true
        break
      fi
    done

    if [[ $need_hyphen == true ]]; then
      out+="/$abbrev-"
    else
      out+="/$abbrev"
    fi

    parent+="/$part"
  done

  out+="/${parts[-1]}"
  printf '%s\n' "$out"
}

# __aap_rollup_not_achieved_from <node> <root>
#
# Starting at <node> and walking upward to <root> (exclusive), mark each visited
# node as `not-achieved`. Stop before <root> or before an ancestor that is already
# `not-achieved`.
__aap_rollup_not_achieved_from() {
  local node="$1"
  local root="$2"

  # abs = 'absolute' and marks a variable as a full, absolute path canonicalized with `readlink -f`.
  local root_abs
  root_abs="$(readlink -f -- "$root")"

  local current_abs
  current_abs="$(readlink -f -- "$node")"

  if [[ "$current_abs" != "$root_abs" ]]; then
    while :; do
      __aap_write_status "$current_abs" not-achieved || return 1
      current_abs="$(dirname -- "$current_abs")"
      if [[ "$current_abs" == "$root_abs" ||
            "$(__aap_read_status "$current_abs")" == "not-achieved" ]]; then
        break
      fi
    done
  fi
}

# __aap_normalize_ref <ref>
#
# Normalize short numeric refs by adding a leading zero where appropriate,
# e.g. `2`, `2.5`, and `2-foo` become `02`, `02.5`, and `02-foo`.
__aap_normalize_ref() {
  local ref="$1"
  # Allow omitting the leading 0 for single-digit prefixes (e.g. "2" -> "02", "2.5" -> "02.5", "2-mark" -> "02-mark").
  if [[ "$ref" =~ ^[1-9]($|[.-]) ]]; then
    ref="0$ref"
  fi
  printf '%s\n' "$ref"
}

# __aap_resolve_ref_in_parent <parent> <ref>
#
# Print the full path of the direct child of <parent> uniquely identified by <ref>.
# Two-digit refs such as `01` match only `01-*`, not `01.5-*`.
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
    __aap_die "Unknown ref '$ref' under $(__aap_refpath_of "$parent")."
    return 1
  fi

  if (( ${#matches[@]} > 1 )); then
    local names=("Multiple matches:")
    local m
    for m in "${matches[@]}"; do
      names+=("$(basename -- "$m")")
    done
    __aap_die "Ambiguous ref '$ref' under $(__aap_refpath_of "$parent"). ${names[*]}"
    return 1
  fi

  printf '%s\n' "${matches[0]}"
}

# __aap_goal_name_ok <name>
#
# Return success if <name> has the required numeric ordering prefix and hyphen.
__aap_goal_name_ok() {
  local name="$1"
  [[ "$name" =~ ^[0-9][0-9][^-]*- ]]
}

# __aap_goal_token <name>
#
# Print the ordering token before the first hyphen in a plan-node name.
__aap_goal_token() {
  local name="$1"
  printf '%s\n' "${name%%-*}"
}

# __aap_ref_matches_element <ref> <element>
#
# Return success if <ref> can identify the path element <element>.
# This is a low-level path matching helper; it does not check siblings for uniqueness.
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

# __aap_resolve_refpath_parent <objective_tree> <current_objective_abs> <parent-ref>
#
# Resolve the value passed to `aap-insert --parent` to a plan-node directory.
# Intended semantics:
# - `/` resolves to <objective_tree> itself, allowing insertion of a primary node.
# - absolute refpaths beginning with `/`, such as `/03` or `/03/04/01`, resolve
#   globally from ObjectiveTree and may target any existing node in the plan tree.
# - non-absolute refs, such as `03`, resolve against the current `aap-ls` sibling
#   listing: the direct children of the current objective's parent.
# - if non-absolute paths with slashes are supported, resolve the first element
#   in the current sibling listing and subsequent elements below that node.
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

  local parent
  if (( absolute )); then
    parent="$objective_tree_abs"
  else
    if [[ -z "$current_objective_abs" || ! -d "$current_objective_abs" ]]; then
      __aap_die "Cannot resolve relative --parent '$3' without a valid current_objective (use --parent / or an absolute refpath)."
      return 1
    fi
    if [[ "$current_objective_abs" != "$objective_tree_abs"/* ]]; then
      __aap_die "Cannot resolve relative --parent '$3' because current_objective is outside ObjectiveTree."
      return 1
    fi
    parent="$(dirname -- "$current_objective_abs")"
  fi

  local ref
  for ref in "${refs[@]}"; do
    parent="$(__aap_resolve_ref_in_parent "$parent" "$ref")" || return 1
  done

  printf '%s\n' "$parent"
}
# __aap_insert_position_ok <current_objective_abs> <new_node>
#
# Check whether <new_node> would sort immediately before <current_objective_abs>
# among the current objective's siblings. Used when aap-insert is called without --parent.
__aap_insert_position_ok() {
  local current_objective_abs="$1"
  local new_node="$2"

  local parent_abs
  parent_abs="$(dirname -- "$current_objective_abs")"
  local current_name
  current_name="$(basename -- "$current_objective_abs")"

  if [[ ! -d "$current_objective_abs" ]]; then
    __aap_die "Current objective points to non-existent node."
    return 1
  fi

  # Load all currently existing goal names into `names`.
  local names=()
  local child
  while IFS= read -r -d '' child; do
    names+=("$(basename -- "$child")")
  done < <(__aap_list_goal_dirs "$parent_abs")

  # Insert `new_node` and return sorted list in array `sorted`.
  local sorted=()
  mapfile -t sorted < <(printf '%s\n' "${names[@]}" "$new_node" | LC_ALL=C sort)

  # Find index of `current_name` in array `sorted`.
  local cur_idx=-1
  local i
  for (( i=0; i<${#sorted[@]}; ++i )); do
    if [[ "${sorted[i]}" == "$current_name" ]]; then
      cur_idx=$i
      break
    fi
  done

  # Make sure `new_node` was sorted right before it.
  if [[ $cur_idx -le 0 || "${sorted[cur_idx-1]}" != "$new_node" ]]; then
    __aap_die "New node '$new_node' must sort immediately before '$current_name' under $(__aap_refpath_of "$parent_abs")."
    return 1
  fi
}

# __aap_token_unique_in_parent <parent> <new_name>
#
# Ensure <new_name>'s numeric ordering token is unambiguous among <parent>'s
# direct child plan nodes, so refs remain unique.
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
      __aap_die "Numeric prefix token '$new_token' is not unique under $(__aap_refpath_of "$parent") (conflicts with '$token')."
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
        __aap_die "Numeric prefix token '$new_token' is not unique under $(__aap_refpath_of "$parent") (conflicts with '$token')."
        return 1
      fi
    fi
  done < <(__aap_list_goal_dirs "$parent")
}

# __aap_print_achieved <prefix> <child-name>
#
# Print one achieved child line using a checkmark in shell mode or `v` otherwise.
__aap_print_achieved() {
  local prefix="$1"
  local child_name="$2"
  if [[ $AICLI_MODE == "shell" ]]; then
    printf '%s%b%s\n' "$prefix" $'\e[32m🗸\e[0m ' "$child_name"
  else
    printf '%sv %s\n' "$prefix" "$child_name"
  fi
}

# __aap_is_user
#
# Return success when the current command was initiated directly by the user,
# as indicated by the OPENCODE_IS_USER_COMMAND marker.
__aap_is_user() {
  local magic=$(echo "${OPENCODE_IS_USER_COMMAND:-}" | md5sum | awk '{ print $1 }')
  [[ $magic == "9fad39ae375a33ff8d1e9d2a8af3f268" ]]
}
