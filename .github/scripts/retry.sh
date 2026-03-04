#!/usr/bin/env bash

retry() {
  local attempts="${RETRY_ATTEMPTS:-5}"
  local delay="${RETRY_INITIAL_DELAY_SECONDS:-2}"
  local max_delay="${RETRY_MAX_DELAY_SECONDS:-30}"

  local attempt=1
  while true; do
    local exit_code=0
    if "$@"; then
      return 0
    else
      exit_code=$?
    fi
    if (( attempt >= attempts )); then
      echo "Command failed after ${attempt} attempt(s): $*" >&2
      return "$exit_code"
    fi

    echo "Command failed (attempt ${attempt}/${attempts}, exit ${exit_code}). Retrying in ${delay}s: $*" >&2
    sleep "$delay"

    delay=$((delay * 2))
    if (( delay > max_delay )); then
      delay="$max_delay"
    fi

    attempt=$((attempt + 1))
  done
}

gh_retry() {
  retry gh "$@"
}
