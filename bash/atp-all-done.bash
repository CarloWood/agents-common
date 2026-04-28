__atp_all_done() (
  if ! __aap_is_user; then
    __aap_die "atp-all-done is a user-only command."
    exit 1
  fi

  local current_link="$PLANROOT/analyst/current"
  local topics_path="$current_link/topics"
  if [[ -L "$current_link" || -d "$current_link" ]]; then
    if [[ $AICLI_MODE == "analyst" || $AICLI_MODE == "coder" ]]; then
      unset AICLI_MODE
      remountctl rw ai-cli "/${REPOBASE}-AAP"
      trap 'unset AICLI_MODE; remountctl ro ai-cli "/${REPOBASE}-AAP"' EXIT
      export AICLI_MODE="analyst"
    fi

    printf '1. all done\n' > "$topics_path"
  fi
)

atp-all-done() {
  __atp_all_done
}
