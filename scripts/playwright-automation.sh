#!/usr/bin/env bash
set -u

fail() {
  printf '%s\n' "[pw-auto] $1" >&2
  exit "${2:-1}"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pw_auto_workspace_override=""

resolve_npx() {
  if command -v npx >/dev/null 2>&1; then
    printf '%s\n' "npx"
    return 0
  fi
  fail "npx was not found on PATH."
}

npx_cmd="$(resolve_npx)"
cli_prefix=(--yes --package @playwright/cli playwright-cli)

get_option_value() {
  local name="$1"
  shift
  local token
  local next_is_value=0
  for token in "$@"; do
    if [[ "${next_is_value}" -eq 1 ]]; then
      printf '%s\n' "${token}"
      return 0
    fi
    if [[ "${token}" == "${name}" ]]; then
      next_is_value=1
      continue
    fi
    if [[ "${token}" == "${name}="* ]]; then
      printf '%s\n' "${token#${name}=}"
      return 0
    fi
  done
  return 1
}

require_session() {
  local session
  session="$(get_option_value --session "$@")" || fail "missing required --session <name>."
  printf '%s\n' "${session}"
}

forward_tokens() {
  local -n out_ref=$1
  shift
  local skip_names=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      break
    fi
    skip_names+=("$1")
    shift
  done

  while [[ $# -gt 0 ]]; do
    local token="$1"
    local skip=0
    local name
    for name in "${skip_names[@]}"; do
      if [[ "${token}" == "${name}" ]]; then
        shift
        if [[ $# -gt 0 ]]; then
          shift
        fi
        skip=1
        break
      fi
      if [[ "${token}" == "${name}="* ]]; then
        shift
        skip=1
        break
      fi
    done
    if [[ ${skip} -eq 0 ]]; then
      out_ref+=("${token}")
      shift
    fi
  done
}

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

extract_wrapper_options() {
  cleaned_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workspace)
        [[ $# -ge 2 ]] || fail "missing value for --workspace."
        pw_auto_workspace_override="$2"
        shift 2
        ;;
      --workspace=*)
        pw_auto_workspace_override="${1#--workspace=}"
        shift
        ;;
      *)
        cleaned_args+=("$1")
        shift
        ;;
    esac
  done
}

resolve_workspace_root() {
  local candidate=""
  if [[ -n "${pw_auto_workspace_override}" ]]; then
    candidate="${pw_auto_workspace_override}"
  elif [[ -n "${PW_AUTO_WORKSPACE:-}" ]]; then
    candidate="${PW_AUTO_WORKSPACE}"
  elif [[ -n "${PLAYWRIGHT_AUTOMATION_WORKSPACE:-}" ]]; then
    candidate="${PLAYWRIGHT_AUTOMATION_WORKSPACE}"
  else
    pwd
    return 0
  fi

  [[ -d "${candidate}" ]] || fail "workspace path '${candidate}' does not exist."
  (cd "${candidate}" && pwd)
}

build_common_env() {
  workspace_root="$(resolve_workspace_root)"
  output_root="${workspace_root}/output/playwright"
  daemon_root="${workspace_root}/.playwright-daemon"
  npm_cache="${workspace_root}/.npm-cache"

  mkdir -p "${output_root}" "${daemon_root}" "${npm_cache}"

  export PLAYWRIGHT_DAEMON_SESSION_DIR="${daemon_root}"
  export npm_config_cache="${npm_cache}"
}

run_cli() {
  "${npx_cmd}" "${cli_prefix[@]}" "$@"
  exit $?
}

doctor() {
  build_common_env
  printf '%s\n' "[pw-auto] workspace=${workspace_root}"
  printf '%s\n' "[pw-auto] daemon=${daemon_root}"
  printf '%s\n' "[pw-auto] artifacts=${output_root}"
  "${npx_cmd}" "${cli_prefix[@]}" --version || exit $?
  "${npx_cmd}" "${cli_prefix[@]}" list || exit $?
  printf '%s\n' "[pw-auto] doctor completed. If browser open still fails with EPERM or spawn errors, the runtime is restricting browser startup."
}

open_cmd() {
  [[ $# -ge 1 ]] || fail "open requires a URL."
  local url="$1"
  shift

  local session
  session="$(require_session "$@")"
  local mode
  mode="$(get_option_value --mode "$@")" || fail "open requires --mode headed or --mode headless."
  [[ "${mode}" == "headed" || "${mode}" == "headless" ]] || fail "invalid mode '${mode}'. Use headed or headless."

  build_common_env
  local cli=(--session "${session}" open "${url}")
  forward_tokens cli --mode --session -- "$@"

  if [[ "${mode}" == "headed" ]]; then
    cli+=(--headed)
  fi

  "${npx_cmd}" "${cli_prefix[@]}" "${cli[@]}"
  local code=$?
  if [[ ${code} -ne 0 ]]; then
    printf '%s\n' "[pw-auto] session '${session}' open failed. Run recover --session ${session} or inspect troubleshooting.md."
  fi
  exit ${code}
}

snapshot_cmd() {
  build_common_env
  local session
  session="$(require_session "$@")"
  local cli=(--session "${session}" snapshot)
  forward_tokens cli --session -- "$@"
  run_cli "${cli[@]}"
}

screenshot_cmd() {
  build_common_env
  local session
  session="$(require_session "$@")"
  local name
  name="$(get_option_value --name "$@" || true)"
  if [[ -z "${name}" ]]; then
    name="page"
  fi

  local session_dir="${output_root}/${session}"
  mkdir -p "${session_dir}"
  local filename="${session_dir}/${name}-$(timestamp).png"

  local cli=(--session "${session}" screenshot --filename "${filename}")
  forward_tokens cli --session --name -- "$@"

  "${npx_cmd}" "${cli_prefix[@]}" "${cli[@]}"
  local code=$?
  if [[ ${code} -eq 0 ]]; then
    printf '%s\n' "[pw-auto] screenshot=${filename}"
  fi
  exit ${code}
}

trace_start_cmd() {
  build_common_env
  local session
  session="$(require_session "$@")"
  local cli=(--session "${session}" tracing-start)
  forward_tokens cli --session -- "$@"
  run_cli "${cli[@]}"
}

trace_stop_cmd() {
  build_common_env
  local session
  session="$(require_session "$@")"
  local cli=(--session "${session}" tracing-stop)
  forward_tokens cli --session -- "$@"
  run_cli "${cli[@]}"
}

sessions_cmd() {
  build_common_env
  run_cli list
}

recover_cmd() {
  build_common_env
  local session
  session="$(require_session "$@")"

  "${npx_cmd}" "${cli_prefix[@]}" attach "${session}" --session "${session}"
  local attach_code=$?
  if [[ ${attach_code} -eq 0 ]]; then
    printf '%s\n' "[pw-auto] session '${session}' attached successfully."
    exit 0
  fi

  printf '%s\n' "[pw-auto] attach failed for '${session}'. Attempting non-destructive close of the named session."
  "${npx_cmd}" "${cli_prefix[@]}" --session "${session}" close
  local close_code=$?
  if [[ ${close_code} -eq 0 ]]; then
    printf '%s\n' "[pw-auto] session '${session}' closed. Re-open it explicitly with the same --session and --mode."
    exit 0
  fi

  printf '%s\n' "[pw-auto] recovery failed for '${session}'. Inspect output/playwright/${session} and troubleshooting.md."
  exit ${close_code}
}

cleanup_cmd() {
  build_common_env
  local session
  session="$(require_session "$@")"

  "${npx_cmd}" "${cli_prefix[@]}" --session "${session}" close
  local close_code=$?
  if [[ ${close_code} -ne 0 ]]; then
    exit ${close_code}
  fi

  local delete_data=0
  local token
  for token in "$@"; do
    if [[ "${token}" == "--delete-data" ]]; then
      delete_data=1
      break
    fi
  done

  if [[ ${delete_data} -eq 1 ]]; then
    "${npx_cmd}" "${cli_prefix[@]}" --session "${session}" delete-data
    exit $?
  fi

  printf '%s\n' "[pw-auto] session '${session}' closed. Artifacts remain under output/playwright/${session}."
}

run_cmd() {
  [[ $# -ge 1 ]] || fail "run requires a playwright-cli command."
  build_common_env
  local session=""
  session="$(get_option_value --session "$@" || true)"
  local cli=()
  if [[ -n "${session}" ]]; then
    cli+=(--session "${session}")
  fi
  forward_tokens cli --session -- "$@"
  "${npx_cmd}" "${cli_prefix[@]}" "${cli[@]}"
  local code=$?
  if [[ ${code} -ne 0 ]]; then
    if [[ -n "${session}" ]]; then
      printf '%s\n' "[pw-auto] command failed for session '${session}'. Run recover --session ${session} if the browser is stuck."
    fi
  fi
  exit ${code}
}

extract_wrapper_options "$@"
set -- "${cleaned_args[@]}"

[[ $# -ge 1 ]] || fail "missing command. Use doctor, open, snapshot, screenshot, trace-start, trace-stop, sessions, recover, cleanup, or run."

command_name="$1"
shift

case "${command_name}" in
  doctor) doctor ;;
  open) open_cmd "$@" ;;
  snapshot) snapshot_cmd "$@" ;;
  screenshot) screenshot_cmd "$@" ;;
  trace-start) trace_start_cmd "$@" ;;
  trace-stop) trace_stop_cmd "$@" ;;
  sessions) sessions_cmd ;;
  recover) recover_cmd "$@" ;;
  cleanup) cleanup_cmd "$@" ;;
  run) run_cmd "$@" ;;
  *) fail "unknown command '${command_name}'." ;;
esac

