__aap_build_impl() (
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
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-build! This is a 'coder'-agent only function (although the 'planner' can run it too)."
    exit 1
  fi

  if [[ ! -d "$BUILDDIR" ]]; then
    __aap_die "\$BUILDDIR ($(abbreviate_path $BUILDDIR)) does not exist; first run aap-configure."
    exit 1
  fi
  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-build [cmake --build args...]

EOF
    echo "Build $REPOBASE in \$BUILDDIR."
    cat <<'EOF'
Uses:
  cmake --build "$BUILDDIR" --parallel ${AAP_BUILD_JOBS:-$(nproc)}
EOF
    exit 0
  fi

  cmake --build "$BUILDDIR" --parallel "${AAP_BUILD_JOBS:-$(nproc)}" "$@"
)

aap-build() {
  __aap_build_impl "$@"
}
