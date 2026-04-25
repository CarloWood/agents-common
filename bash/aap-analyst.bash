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

  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-analyst-update-topic-list <text>

Extract the first "Topic List:" block from <text> and write it to
$PLANROOT/analyst/current/topics.
EOF
    exit 0
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
