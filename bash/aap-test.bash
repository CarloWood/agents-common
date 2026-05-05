__aap_test_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ -z "${BUILDDIR:-}" ]]; then
    __aap_die "BUILDDIR is not set."
    exit 1
  fi
  if [[ $AICLI_MODE != "planner" && $AICLI_MODE != "coder" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-test! This is a 'coder'-agent only function (although the 'planner' can run it too)."
    exit 1
  fi
  if [[ ! -d "$BUILDDIR" ]]; then
    __aap_die "\$BUILDDIR ($(abbreviate_path "$BUILDDIR")) does not exist; first run aap-configure."
    exit 1
  fi
  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-test [ctest args...]
EOF
    echo "Run tests for $REPOBASE in \$BUILDDIR."
    cat <<'EOF'
Uses:
ctest --test-dir "$BUILDDIR" --output-on-failure
EOF
    exit 0
  fi

  ctest --test-dir "$BUILDDIR" --output-on-failure "$@"
)

aap-test() {
  __aap_test_impl "$@"
}
