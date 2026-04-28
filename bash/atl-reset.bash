# __atl_reset_impl
#
# Change the current Topic List to use the current objective node and print its refpath.
__atl_reset_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if (( $# != 0 )) || [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'EOF'
usage: atl-reset

Change the current Topic List to use the current objective node.
EOF
    exit 0
  fi

  local current_objective_link="$PLANROOT/current_objective"
  if [[ ! -L "$current_objective_link" ]]; then
    __aap_die "current_objective symlink missing; run aap-ls --fix first."
    exit 1
  fi

  local objective_abs
  objective_abs="$(readlink -f -- "$current_objective_link")"
  if [[ ! -d "$objective_abs" ]]; then
    __aap_die "current_objective is not a directory."
    exit 1
  fi

  if [[ $AICLI_MODE == "analyst" || $AICLI_MODE == "coder" ]]; then
    unset AICLI_MODE
    remountctl rw ai-cli "/${REPOBASE}-AAP"
    trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
    export AICLI_MODE="analyst"
  fi

  mkdir -p -- "$PLANROOT/analyst"
  if [[ -d "$PLANROOT/analyst/current" && ! -L "$PLANROOT/analyst/current" ]]; then
    rm -rf -- "$PLANROOT/analyst/current"
  fi
  ln -snf -- "$objective_abs" "$PLANROOT/analyst/current"
  __aap_refpath_of "$objective_abs"
)

atl-reset() {
  __atl_reset_impl "$@"
}
