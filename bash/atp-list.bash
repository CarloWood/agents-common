# __atp_list_impl
#
# Print the current analyst Topic List from $PLANROOT/analyst/current/topics, if it exists.
__atp_list_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: atp-list [--help]

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

atp-list() {
  __atp_list_impl "$@"
}
