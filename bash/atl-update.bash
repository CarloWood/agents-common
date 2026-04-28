# __atl_update_impl <text>
#
# Extract the first Topic List block from <text> and write it to the current Topic List topics file.
__atl_update_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: atl-update <text>

Extract the first "Topic List:" block from <text> and write it to
$PLANROOT/analyst/current/topics.
EOF
    exit 0
  fi

  if [[ $AICLI_MODE != "analyst" ]]; then
    __aap_warn "AICLI_MODE='$AICLI_MODE'"
    __aap_die "atl-update should only be run by the AAP_support.js plugin."
    exit 1
  fi

  if (( $# != 1 )); then
    __aap_die "usage: atl-update <text>"
    exit 1
  fi

  local text="$1"
  local match_status
  local topic_list
  match_status=0
  topic_list="$(python3 - "$text" <<'PY'
import re
import sys

text = sys.argv[1]
match = re.search(r'(?:^|\n)Topic List:?\n([1-9][\s\S]*?)(?:\n\n|$)', text)
if match:
    sys.stdout.write(match.group(1))
    raise SystemExit(0)
raise SystemExit(1)
PY
)" || match_status=$?

  local current_link="$PLANROOT/analyst/current"
  local topics_path="$current_link/topics"
  if [[ -L "$current_link" || -d "$current_link" ]]; then
    if (( match_status != 0 )); then
      exit 0
    fi

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

atl-update() {
  __atl_update_impl "$@"
}
