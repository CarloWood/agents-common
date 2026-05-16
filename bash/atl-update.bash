# __atl_update_log_current_repair <current-link> <target> <reset-output>
#
# Append a diagnostic JSON record to the opencode Topic List debug log when
# atl-update has to recreate the analyst/current symlink. The log is best-effort:
# failures to write it must not prevent the Topic List itself from being saved.
__atl_update_log_current_repair() {
  local current_link="$1"
  local target="$2"
  local reset_output="$3"

  python3 - "$current_link" "$target" "$reset_output" <<'PY' || true
import json
import os
import pathlib
import sys

current_link, target, reset_output = sys.argv[1:]
state_home = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
log_dir = pathlib.Path(state_home) / "opencode"
log_dir.mkdir(parents=True, exist_ok=True)
with (log_dir / "topic-list-message.jsonl").open("a", encoding="utf-8") as file:
    json.dump(
        {
            "atl-update": {
                "event": "created analyst/current symlink",
                "current": current_link,
                "target": target,
                "atl-reset": reset_output,
            }
        },
        file,
        indent=2,
    )
    file.write("\n")
PY
}

# __atl_update_impl <text>
#
# Extract the first Topic List block from <text> and write it to the current Topic List topics file.
# If analyst/current is missing or broken, recreate it from current_objective via
# atl-reset before writing and log the repair target for later debugging.
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
    __aap_die "usage: atl-update [--help] <text>"
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
  if (( match_status != 0 )); then
    exit 0
  fi

  if [[ ! -d "$current_link" ]]; then
    local reset_output
    reset_output="$(atl-reset)"

    local current_target
    current_target="$(readlink -f -- "$current_link")"
    __atl_update_log_current_repair "$current_link" "$current_target" "$reset_output"
  fi

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

atl-update() {
  __atl_update_impl "$@"
}
