__aap_configure_impl() (
  set -euo pipefail

  if [[ -z "${PLANROOT:-}" ]]; then
    __aap_die "PLANROOT is not set."
    exit 1
  fi
  if [[ -z "${REPOROOT:-}" ]]; then
    __aap_die "REPOROOT is not set."
    exit 1
  fi
  if [[ -z "${BUILDDIR:-}" ]]; then
    __aap_die "BUILDDIR is not set."
    exit 1
  fi
  if [[ $AICLI_MODE != "planner" && $AICLI_MODE != "coder" ]] && ! __aap_is_user; then
    __aap_die "As '$AICLI_MODE' agent, you should never try to run aap-configure! This is a 'coder'-agent only function (although the 'planner' can run it too)."
    exit 1
  fi
  if [[ ! -d "$BUILDDIR" || ! -w "$BUILDDIR" ]]; then
    __aap_die "BUILDDIR is not a writable directory."
    exit 1
  fi
  local ref="${1:-}"
  if [[ "$ref" == "--help" || "$ref" == "-h" ]]; then
    cat <<'EOF'
usage: aap-configure [cmake args...]

EOF
    echo "Configure $REPOBASE out-of-tree in \$BUILDDIR."
    cat <<'EOF'

Defaults:
  -G ${AAP_GENERATOR:-Ninja}
  -DCMAKE_BUILD_TYPE=${AAP_BUILD_TYPE:-Debug}
EOF
    exit 0
  fi

  local -a cmd=(cmake -S "$REPOROOT" -B "$BUILDDIR")

  local -a CMAKE_CONFIGURE_OPTIONS=()
  if [[ -n "${CMAKE_CONFIGURE_OPTIONS_STR:-}" ]]; then
    readarray -d '|' -t CMAKE_CONFIGURE_OPTIONS < <(printf '%s' "$CMAKE_CONFIGURE_OPTIONS_STR")
    [[ ${#CMAKE_CONFIGURE_OPTIONS[@]} -gt 0 && ${CMAKE_CONFIGURE_OPTIONS[-1]} == "" ]] && unset 'CMAKE_CONFIGURE_OPTIONS[-1]'
  fi

  local have_generator=0
  local have_build_type=0
  local arg
  for arg in "$@" "${CMAKE_CONFIGURE_OPTIONS[@]}"; do
    case "$arg" in
      -G|--generator|--generator=*) have_generator=1 ;;
      -DCMAKE_BUILD_TYPE=*) have_build_type=1 ;;
    esac
  done

  local build_type="${AAP_BUILD_TYPE:-Debug}"
  local generator="${AAP_GENERATOR:-Ninja}"
  if (( ! have_generator )); then
    cmd+=(-G "$generator")
  fi
  if (( ! have_build_type )); then
    cmd+=("-DCMAKE_BUILD_TYPE=$build_type")
  fi

  cmd+=("${CMAKE_CONFIGURE_OPTIONS[@]}")
  cmd+=("$@")

  "${cmd[@]}"
)

aap-configure() {
  __aap_configure_impl "$@"
}
