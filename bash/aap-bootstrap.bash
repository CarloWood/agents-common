__aap_bootstrap_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi

  if [[ $AICLI_MODE != "planner" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-bootstrap! This is a 'planner'-agent only function."
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        cat <<'EOF'
usage: aap-bootstrap

Initialize PLANROOT with an initial objective, the main objective.

The description is read from stdin (heredoc/piped input recommended). If stdin
is a TTY, input is read until EOF (Ctrl-D).
EOF
        exit 0
        ;;
      --*) __aap_die "aap-bootstrap: unknown option: $1"; exit 1 ;;
      *) break ;;
    esac
  done

  if (( $# != 0 )); then
    __aap_die "usage: aap-bootstrap"
    exit 1
  fi

  local objective_tree="$PLANROOT/ObjectiveTree"
  local current_objective_link="$PLANROOT/current_objective"

  if [[ -d "$objective_tree" ]]; then
    __aap_die "ObjectiveTree directory already exist: $(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")"
    exit 1
  fi

  if [[ -t 0 ]]; then
    printf 'Enter bootstrap description, then end with Ctrl-D:\n' >&2
  fi

  local desc
  desc="$(cat)"
  local desc_check="${desc//$'\r'/}"
  if [[ -z "${desc_check//[[:space:]]/}" ]]; then
    __aap_die "Empty description."
    exit 1
  fi

  mkdir -p -- "$objective_tree"
  printf '%s' "$desc" >"$objective_tree/description"
  if [[ "$desc" != *$'\n' ]]; then
    printf '\n' >>"$objective_tree/description"
  fi
  printf 'not-achieved\n' >"$objective_tree/status"

  ln -snf -- "$(__aap_rel_to_planroot "$PLANROOT" "$objective_tree")" "$current_objective_link"

  __aap_notice "Updated current_objective to point to $(basename -- "$objective_tree")."
)

aap-bootstrap() {
  __aap_bootstrap_impl "$@"
}
