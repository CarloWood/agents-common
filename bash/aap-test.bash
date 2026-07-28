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
  local filter=1
  if [[ "$ref" == "--no-filter" ]]; then
    filter=0
    shift
  fi
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-test [--help|--no-filter] [ctest args...]
EOF
    echo "Run tests for $REPOBASE in \$BUILDDIR."
    cat <<'EOF'
Uses (without the grep if --no-filter is used):
ctest --test-dir "$BUILDDIR" --output-on-failure "$@" | grep -E -v '^[[:space:]]*([0-9]+/[0-9]+ Test |Start[[:space:]]+[0-9])'
EOF
    exit 0
  fi

  if [[ $filter == 1 ]]; then
    ctest -j8 --test-dir "$BUILDDIR" --output-on-failure "$@" | awk '
      /^[[:space:]]*[0-9]+\/[0-9]+ Test / { next }                 # Per-test progress lines.
      /^[[:space:]]*Start[[:space:]]+[0-9]/ { next }               # Parallel "Start N:" banners.
      /^The following tests did not run:/ { next }                 # Skipped-list header.
      /^[[:space:]]*[0-9]+ - ava_.*\(Skipped\)$/ { next }          # Skipped test entries.
      /^Label Time Summary:/ { in_labels = 1; next }               # Begin dropping the label block.
      in_labels { if ($0 ~ /^[[:space:]]*$/) in_labels = 0; next } # Drop label lines + its trailing blank.
      skip_line { skip_line = 0; next }                            # Skip one line.
      /^Total Test time/ { skip_line = 1 }                         # Skip the empty line that follows "Total test time...".
      { print }
    '
  else
    ctest -j8 --test-dir "$BUILDDIR" --output-on-failure "$@"
  fi
)

aap-test() {
  __aap_test_impl "$@"
}
