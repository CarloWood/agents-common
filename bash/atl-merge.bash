# __atl_resolve_refpath <refpath>
#
# Resolve an absolute plan <refpath> to the corresponding plan node directory.
__atl_resolve_refpath() {
  local refpath="$1"
  local objective_tree="$PLANROOT/ObjectiveTree"
  local -a parts

  if [[ "$refpath" != /* ]]; then
    __aap_die "Expected absolute <refpath>, got '$refpath'."
    return 1
  fi
  if [[ "$refpath" == "/" ]]; then
    __aap_die "Topic Lists belong to plan nodes, not ObjectiveTree itself."
    return 1
  fi

  local node="$objective_tree"
  local rest="${refpath#/}"
  local part
  IFS='/' read -r -a parts <<< "$rest"
  for part in "${parts[@]}"; do
    if [[ -z "$part" ]]; then
      __aap_die "Invalid <refpath> '$refpath'."
      return 1
    fi
    node="$(__aap_resolve_ref_in_parent "$node" "$part")" || return 1
  done

  printf '%s\n' "$node"
}

# __atl_topics_effectively_empty <topics-path>
#
# Return success if a topics file is missing, blank, or contains only the all-done marker.
__atl_topics_effectively_empty() {
  local topics_path="$1"
  [[ ! -s "$topics_path" ]] && return 0

  local text
  text="$(<"$topics_path")"
  text="${text//$'\r'/}"
  text="${text%$'\n'}"
  [[ -z "${text//[[:space:]]/}" || "$text" == "1. all done" ]]
}

# __atl_append_unique_topics <source> <destination>
#
# Append simple numbered topic lines from <source> to <destination>, removing exact duplicate texts and renumbering from 1.
__atl_append_unique_topics() {
  local source="$1"
  local destination="$2"
  local tmp
  tmp="$(mktemp "$PLANROOT/.atl-merge.XXXXXX")"

  local -a texts=()
  local file line text existing duplicate
  for file in "$destination" "$source"; do
    __atl_topics_effectively_empty "$file" && continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      text="$line"
      if [[ "$text" =~ ^[[:space:]]*[0-9]+\.[[:space:]]*(.*)$ ]]; then
        text="${BASH_REMATCH[1]}"
      fi
      [[ -z "${text//[[:space:]]/}" || "$text" == "all done" ]] && continue
      duplicate=0
      for existing in "${texts[@]}"; do
        if [[ "$existing" == "$text" ]]; then
          duplicate=1
          break
        fi
      done
      (( duplicate )) || texts+=("$text")
    done < "$file"
  done

  if (( ${#texts[@]} == 0 )); then
    printf '1. all done\n' > "$tmp"
  else
    local i
    for (( i=0; i<${#texts[@]}; ++i )); do
      printf '%d. %s\n' "$((i + 1))" "${texts[i]}" >> "$tmp"
    done
  fi
  mv -- "$tmp" "$destination"
}

# __atl_merge_impl <from-refpath> <to-refpath>
#
# Switch the current Topic List to <to-refpath>, merge topics from <from-refpath> into it, and mark <from-refpath> all done.
__atl_merge_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
usage: atl-merge <from-refpath> <to-refpath>

Switch the current Topic List to <to-refpath> and merge topics from <from-refpath> into it.
EOF
    exit 0
  fi
  if (( $# != 2 )); then
    __aap_die "usage: atl-merge <from-refpath> <to-refpath>"
    exit 1
  fi

  local from_abs to_abs
  from_abs="$(__atl_resolve_refpath "$1")"
  to_abs="$(__atl_resolve_refpath "$2")"

  if [[ $AICLI_MODE == "analyst" || $AICLI_MODE == "coder" ]]; then
    unset AICLI_MODE
    remountctl rw ai-cli "/${REPOBASE}-AAP"
    trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
    export AICLI_MODE="analyst"
  fi

  local from_topics="$from_abs/topics"
  local to_topics="$to_abs/topics"
  __atl_append_unique_topics "$from_topics" "$to_topics"
  printf '1. all done\n' > "$from_topics"

  mkdir -p -- "$PLANROOT/analyst"
  if [[ -d "$PLANROOT/analyst/current" && ! -L "$PLANROOT/analyst/current" ]]; then
    rm -rf -- "$PLANROOT/analyst/current"
  fi
  ln -snf -- "$to_abs" "$PLANROOT/analyst/current"
  __aap_refpath_of "$to_abs"
)

atl-merge() {
  __atl_merge_impl "$@"
}
