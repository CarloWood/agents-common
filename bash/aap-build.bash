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

  local build_type="${AAP_BUILD_TYPE:-Debug}"

  local -a CMAKE_CONFIGURE_OPTIONS=()
  if [[ -n "${CMAKE_CONFIGURE_OPTIONS_STR:-}" ]]; then
    readarray -d '|' -t CMAKE_CONFIGURE_OPTIONS < <(printf '%s' "$CMAKE_CONFIGURE_OPTIONS_STR")
    [[ ${#CMAKE_CONFIGURE_OPTIONS[@]} -gt 0 && ${CMAKE_CONFIGURE_OPTIONS[-1]} == "" ]] && unset 'CMAKE_CONFIGURE_OPTIONS[-1]'
  fi

  local arg
  for arg in "${CMAKE_CONFIGURE_OPTIONS[@]}"; do
    case "$arg" in
      -DCMAKE_BUILD_TYPE=*)
        build_type="${arg#-DCMAKE_BUILD_TYPE=}"
        ;;
    esac
  done
  local have_config=0
  for arg in "$@"; do
    case "$arg" in
      --config|--config=*)
        have_config=1
        ;;
    esac
  done

  local -a cmd=(cmake --build "$BUILDDIR" --parallel "${AAP_BUILD_JOBS:-$(nproc)}")
  if (( ! have_config )); then
    cmd+=(--config "$build_type")
  fi

  cmd+=("$@")

  "${cmd[@]}"
)

aap-build() {
  __aap_build_impl "$@"
}
