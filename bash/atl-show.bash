# __atl_show_impl
#
# Print the refpath of the plan node whose topics file is the current Topic List.
__atl_show_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if (( $# != 0 )) || [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
usage: atl-show

Show which plan node holds the current Topic List, as a <refpath>.
EOF
    exit 0
  fi

  local current_link="$PLANROOT/analyst/current"
  if [[ ! -e "$current_link" && ! -L "$current_link" ]]; then
    __aap_die "No current Topic List exists."
    exit 1
  fi

  local current_abs
  current_abs="$(readlink -f -- "$current_link")"
  if [[ ! -d "$current_abs" ]]; then
    __aap_die "Current Topic List points to a non-directory."
    exit 1
  fi

  __aap_refpath_of "$current_abs"
)

atl-show() {
  __atl_show_impl "$@"
}
