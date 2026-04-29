#!/usr/bin/env bash
set -u

fail() {
  printf '%s\n' "[pw-auto] $1" >&2
  exit "${2:-1}"
}

write_help() {
  local topic="${1:-}"
  case "${topic}" in
    "")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] <command> [args] [options]
[pw-auto] commands:
[pw-auto]   doctor       print workspace paths and playwright-cli session state
[pw-auto]   open         open a URL with explicit --mode and --session
[pw-auto]   goto         navigate an existing session without reopening it
[pw-auto]   reload       reload the current page in an existing session
[pw-auto]   snapshot     capture current refs for an existing session
[pw-auto]   screenshot   save a screenshot under output/playwright/<session>/
[pw-auto]   trace-start  start Playwright tracing for a session
[pw-auto]   trace-stop   stop Playwright tracing for a session
[pw-auto]   cookie       set, list, or clear cookies without echoing values
[pw-auto]   state        save or load browser authentication state
[pw-auto]   target-first selector-first, ref-fallback fill/click helper
[pw-auto]   sessions     list active Playwright CLI sessions
[pw-auto]   recover      attempt non-destructive recovery for one session
[pw-auto]   cleanup      close one session and optionally delete its data
[pw-auto]   run|cli|raw  pass a subcommand through to playwright-cli
[pw-auto] help:
[pw-auto]   playwright-automation help
[pw-auto]   playwright-automation help <command>
[pw-auto]   playwright-automation <command> --help
[pw-auto] notes:
[pw-auto]   open requires both --session <name> and --mode headed|headless
[pw-auto]   wrappers use the current working directory as workspace unless --workspace is set
[pw-auto]   help output is local and does not invoke npx, browsers, or daemon setup
EOF
      ;;
    "doctor")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] doctor
[pw-auto] description: print resolved workspace, daemon, artifacts path, CLI version, and session list
[pw-auto] notes:
[pw-auto]   creates local workspace directories if needed
[pw-auto]   does not install browsers
EOF
      ;;
    "open")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] open <url> --session <name> --mode <headed|headless> [--maximize] [--http-username-env <ENV> --http-password-env <ENV> | --http-credentials-file <path>] [extra playwright-cli open flags]
[pw-auto] description: open a browser page in a named session
[pw-auto] required:
[pw-auto]   <url>
[pw-auto]   --session <name>
[pw-auto]   --mode headed|headless
[pw-auto] notes:
[pw-auto]   headed maps to playwright-cli open --headed
[pw-auto]   --maximize injects a temporary config so Chromium-family browsers start maximized
[pw-auto]   Basic Auth uses Playwright context httpCredentials from env vars or a JSON file
[pw-auto]   --http-credentials-file expects JSON: {"username":"...","password":"..."}
[pw-auto]   raw HTTP credential values are unsupported and credentials are never printed
[pw-auto]   open is a create/recreate entrypoint; use goto or reload for an existing stateful session
[pw-auto]   extra flags are forwarded except wrapper-only options
EOF
      ;;
    "goto")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] goto <url> --session <name> [extra playwright-cli goto flags]
[pw-auto] description: navigate an existing session without reopening or recreating it
[pw-auto] required:
[pw-auto]   <url>
[pw-auto]   --session <name>
[pw-auto] notes:
[pw-auto]   use after cookie/state injection when the existing page should consume the new state
EOF
      ;;
    "reload")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] reload --session <name> [extra playwright-cli reload flags]
[pw-auto] description: reload the current page in an existing session
[pw-auto] required:
[pw-auto]   --session <name>
[pw-auto] notes:
[pw-auto]   use after cookie/state injection or same-hash route checks
EOF
      ;;
    "snapshot")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] snapshot --session <name> [extra playwright-cli snapshot flags]
[pw-auto] description: capture current refs for an existing session
[pw-auto] required:
[pw-auto]   --session <name>
EOF
      ;;
    "screenshot")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] screenshot --session <name> [--name <label>] [--full-page] [target]
[pw-auto] description: save a screenshot under output/playwright/<session>/
[pw-auto] required:
[pw-auto]   --session <name>
[pw-auto] notes:
[pw-auto]   default name is 'page'
[pw-auto]   prints the saved filename on success
EOF
      ;;
    "trace-start")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] trace-start --session <name> [extra playwright-cli tracing-start flags]
[pw-auto] description: start Playwright tracing for a session
[pw-auto] required:
[pw-auto]   --session <name>
EOF
      ;;
    "trace-stop")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] trace-stop --session <name> [extra playwright-cli tracing-stop flags]
[pw-auto] description: stop Playwright tracing for a session
[pw-auto] required:
[pw-auto]   --session <name>
EOF
      ;;
    "cookie")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] cookie <set|list|clear> --session <name> --url <url> [options]
[pw-auto] description: safely set, list, or clear cookies in an existing Playwright session
[pw-auto] commands:
[pw-auto]   cookie set --session <name> --url <url> --name <cookie_name> --value-env <ENV_NAME> [--path /] [--domain <domain>] [--same-site Strict|Lax|None] [--secure] [--http-only]
[pw-auto]   cookie set --session <name> --url <url> --name <cookie_name> --value-file <path> [same options]
[pw-auto]   cookie clear --session <name> --url <url> --name <cookie_name> [--path /] [--domain <domain>]
[pw-auto]   cookie list --session <name> --url <url> [--redact|--show-values]
[pw-auto] required:
[pw-auto]   --session <name>
[pw-auto]   --url <url>
[pw-auto] notes:
[pw-auto]   values are redacted by default and never printed by set or clear
[pw-auto]   set reads values from --value-env or --value-file; raw --value is intentionally unsupported
[pw-auto]   list redacts values unless --show-values is explicitly provided
[pw-auto]   --url is always required; the wrapper does not guess origin or domain
[pw-auto]   cookie set success only proves injection; verify with cookie list, reload/goto, snapshot, and app auth state
EOF
      ;;
    "target-first")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] target-first <fill|click> --session <name> [options]
[pw-auto] description: invoke scripts/target-first.sh through the main wrapper entrypoint
[pw-auto] examples:
[pw-auto]   playwright-automation target-first fill --session <name> --text <value> --target <stable selector> --target e12
[pw-auto]   playwright-automation target-first click --session <name> --target <stable selector> --target e21 --settle-ms 1500
[pw-auto] notes:
[pw-auto]   order targets as scoped stable selectors first and latest snapshot refs last
[pw-auto]   if a selector is ambiguous, add a container scope, exact role/label, or latest snapshot ref
EOF
      ;;
    "state")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] state <save|load> --session <name> [--file <path>]
[pw-auto] description: save or load browser storage state for manual-first login reuse
[pw-auto] commands:
[pw-auto]   state save --session <name> [--file <path>]
[pw-auto]   state load --session <name> --file <path>
[pw-auto] notes:
[pw-auto]   save only after confirming the app is authenticated
[pw-auto]   default save path is output/playwright/<session>/storage-state-<timestamp>.json
[pw-auto]   state files contain cookies and tokens; delete or rotate them after use
[pw-auto]   load restores browser state only; run reload/goto, snapshot, and an app-specific auth probe before product checks
EOF
      ;;
    "sessions")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] sessions
[pw-auto] description: list active Playwright CLI sessions for the resolved workspace
EOF
      ;;
    "recover")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] recover --session <name>
[pw-auto] description: try attach first, then attempt a non-destructive close for the named session
[pw-auto] required:
[pw-auto]   --session <name>
[pw-auto] notes:
[pw-auto]   if close succeeds, reopen explicitly with the same --session and --mode
EOF
      ;;
    "cleanup")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] cleanup --session <name> [--delete-data]
[pw-auto] description: close one session and optionally delete its stored data
[pw-auto] required:
[pw-auto]   --session <name>
[pw-auto] notes:
[pw-auto]   without --delete-data, artifacts remain under output/playwright/<session>/
EOF
      ;;
    "run"|"cli"|"raw")
      cat <<'EOF'
[pw-auto] usage: playwright-automation [--workspace <path>] run|cli|raw [--session <name>] <playwright-cli subcommand> [args]
[pw-auto] description: pass a command through to playwright-cli after wrapper environment setup
[pw-auto] notes:
[pw-auto]   use this for click, fill, press, console, network, eval, run-code, and similar commands
[pw-auto]   if --session is present, the wrapper prefixes it before forwarding
EOF
      ;;
    *)
      fail "unknown help topic '${topic}'."
      ;;
  esac
  exit 0
}

is_help_token() {
  [[ "${1:-}" == "help" || "${1:-}" == "--help" || "${1:-}" == "-h" ]]
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

npx_cmd=""
cli_prefix=(--yes --package @playwright/cli playwright-cli)

ensure_npx() {
  if [[ -z "${npx_cmd}" ]]; then
    npx_cmd="$(resolve_npx)"
  fi
}

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

has_flag() {
  local name="$1"
  shift
  local token
  for token in "$@"; do
    if [[ "${token}" == "${name}" ]]; then
      return 0
    fi
  done
  return 1
}

has_option_token() {
  local name="$1"
  shift
  local token
  for token in "$@"; do
    if [[ "${token}" == "${name}" || "${token}" == "${name}="* ]]; then
      return 0
    fi
  done
  return 1
}

has_open_http_credentials_option() {
  local name
  for name in --http-username-env --http-password-env --http-credentials-file --http-username --http-password --http-credentials; do
    if has_option_token "${name}" "$@"; then
      return 0
    fi
  done
  return 1
}

session_metadata_exists() {
  local root="$1"
  local session="$2"
  [[ -n "${root}" ]] || return 1
  [[ -f "${root}/${session}.session" ]] && return 0
  find "${root}" -name "${session}.session" -type f -print -quit 2>/dev/null | grep -q .
}

require_session() {
  local session
  session="$(get_option_value --session "$@")" || fail "missing required --session <name>."
  printf '%s\n' "${session}"
}

safe_path_segment() {
  local value="$1"
  local safe
  safe="$(printf '%s' "${value}" | tr -c 'A-Za-z0-9._-' '_')"
  if [[ -z "${safe}" ]]; then
    printf '%s\n' "session"
  else
    printf '%s\n' "${safe}"
  fi
}

forward_tokens() {
  local -n out_ref=$1
  shift
  local skip_value_names=()
  local skip_flags=()
  local mode="values"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --)
        shift
        break
        ;;
      --values)
        mode="values"
        shift
        ;;
      --flags)
        mode="flags"
        shift
        ;;
      *)
        if [[ "${mode}" == "values" ]]; then
          skip_value_names+=("$1")
        else
          skip_flags+=("$1")
        fi
        shift
        ;;
    esac
  done

  while [[ $# -gt 0 ]]; do
    local token="$1"
    local skip=0
    local name
    for name in "${skip_value_names[@]}"; do
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
      for name in "${skip_flags[@]}"; do
        if [[ "${token}" == "${name}" ]]; then
          shift
          skip=1
          break
        fi
      done
    fi
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

resolve_config_path() {
  local root="$1"
  local config_value="$2"
  if [[ "${config_value}" =~ ^[A-Za-z]:[\\/].* ]] || [[ "${config_value}" == /* ]]; then
    printf '%s\n' "${config_value}"
  else
    printf '%s\n' "${root}/${config_value}"
  fi
}

resolve_workspace_file_path() {
  local file_value="$1"
  if [[ "${file_value}" =~ ^[A-Za-z]:[\\/].* ]] || [[ "${file_value}" == /* ]]; then
    printf '%s\n' "${file_value}"
  else
    printf '%s\n' "${workspace_root}/${file_value}"
  fi
}

resolve_open_base_config_path() {
  local config_value
  config_value="$(get_option_value --config "$@" || true)"
  if has_option_token --config "$@"; then
    [[ -n "${config_value}" ]] || fail "missing value for --config."
    resolve_config_path "${workspace_root}" "${config_value}"
    return 0
  fi

  local default_config="${workspace_root}/.playwright/cli.config.json"
  if [[ -f "${default_config}" ]]; then
    printf '%s\n' "${default_config}"
  fi
}

create_open_config() {
  local session="$1"
  local maximize="$2"
  shift 2

  local base_config=""
  base_config="$(resolve_open_base_config_path "$@" || true)"
  local tmp_base="${TMPDIR:-/tmp}"
  local config_dir="${tmp_base}/pw-auto"
  mkdir -p "${config_dir}"
  local safe_session
  safe_session="$(printf '%s' "${session}" | tr -c 'A-Za-z0-9._-' '_')"
  local temp_config="${config_dir}/open-${safe_session}-$(timestamp)-$RANDOM.json"
  local browser_name=""
  browser_name="$(get_option_value --browser "$@" || true)"

  local helper_args=(--workspace-root "${workspace_root}" --target "${temp_config}")
  if [[ -n "${base_config}" ]]; then
    helper_args+=(--base "${base_config}")
  fi
  if [[ "${maximize}" == "1" ]]; then
    helper_args+=(--maximize)
    if [[ -n "${browser_name}" ]]; then
      helper_args+=(--browser "${browser_name}")
    fi
  fi
  helper_args+=(-- "$@")

  command -v node >/dev/null 2>&1 || fail "node was not found on PATH."
  node "${script_dir}/open-config-helper.js" "${helper_args[@]}"
  local node_code=$?
  if [[ ${node_code} -ne 0 ]]; then
    rm -f "${temp_config}"
    exit ${node_code}
  fi

  printf '%s\n' "${temp_config}"
}

run_cli() {
  ensure_npx
  "${npx_cmd}" "${cli_prefix[@]}" "$@"
  exit $?
}

doctor() {
  build_common_env
  ensure_npx
  printf '%s\n' "[pw-auto] workspace=${workspace_root}"
  printf '%s\n' "[pw-auto] daemon=${daemon_root}"
  printf '%s\n' "[pw-auto] artifacts=${output_root}"
  "${npx_cmd}" "${cli_prefix[@]}" --version || exit $?
  local list_output
  list_output="$("${npx_cmd}" "${cli_prefix[@]}" list 2>&1)"
  local list_code=$?
  printf '%s\n' "${list_output}"
  if [[ ${list_code} -ne 0 ]]; then
    exit ${list_code}
  fi
  printf '%s\n' "[pw-auto] note: 'playwright-cli list' reports browser sessions, not installed browser binaries."
  printf '%s\n' "[pw-auto] doctor completed."
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
  local maximize=0
  if has_flag --maximize "$@"; then
    maximize=1
  fi
  [[ ${maximize} -eq 0 || "${mode}" == "headed" ]] || fail "--maximize requires --mode headed."
  local has_http_credentials=0
  if has_open_http_credentials_option "$@"; then
    has_http_credentials=1
  fi

  build_common_env
  if session_metadata_exists "${daemon_root}" "${session}"; then
    printf '%s\n' "[pw-auto] warning: session '${session}' already has metadata; open can recreate page/in-memory state. Use goto or reload for existing cookie/state verification."
  fi
  ensure_npx
  local cli=(--session "${session}" open "${url}")
  local forward_args=(--values --mode --session)
  if [[ ${has_http_credentials} -eq 1 ]]; then
    forward_args+=(--values --http-username-env --http-password-env --http-credentials-file --http-username --http-password --http-credentials)
  fi
  if [[ ${maximize} -eq 1 || ${has_http_credentials} -eq 1 ]]; then
    if has_option_token --config "$@"; then
      forward_args+=(--values --config)
    fi
  fi
  if [[ ${maximize} -eq 1 ]]; then
    forward_args+=(--flags --maximize)
    if has_option_token --browser "$@"; then
      forward_args+=(--values --browser)
    fi
  fi
  forward_tokens cli "${forward_args[@]}" -- "$@"

  if [[ "${mode}" == "headed" ]]; then
    cli+=(--headed)
  fi
  local temp_config=""
  if [[ ${maximize} -eq 1 || ${has_http_credentials} -eq 1 ]]; then
    unset PLAYWRIGHT_MCP_VIEWPORT_SIZE
    local config_status=0
    temp_config="$(create_open_config "${session}" "${maximize}" "$@")" || config_status=$?
    if [[ ${config_status} -ne 0 ]]; then
      exit ${config_status}
    fi
    trap '[[ -n "${temp_config:-}" ]] && rm -f "${temp_config}"' EXIT
    cli+=(--config "${temp_config}")
  fi

  "${npx_cmd}" "${cli_prefix[@]}" "${cli[@]}"
  local code=$?
  if [[ -n "${temp_config}" ]]; then
    rm -f "${temp_config}"
    trap - EXIT
  fi
  if [[ ${code} -ne 0 ]]; then
    printf '%s\n' "[pw-auto] session '${session}' open failed. Run recover --session ${session} or inspect troubleshooting.md."
  elif [[ ${has_http_credentials} -eq 1 ]]; then
    printf '%s\n' "[pw-auto] httpCredentials applied username=<redacted> password=<redacted>"
  fi
  exit ${code}
}

snapshot_cmd() {
  build_common_env
  local session
  session="$(require_session "$@")"
  local cli=(--session "${session}" snapshot)
  forward_tokens cli --values --session -- "$@"
  run_cli "${cli[@]}"
}

goto_cmd() {
  [[ $# -ge 1 ]] || fail "goto requires a URL."
  local url="$1"
  shift
  build_common_env
  local session
  session="$(require_session "$@")"
  local cli=(--session "${session}" goto "${url}")
  forward_tokens cli --values --session -- "$@"
  run_cli "${cli[@]}"
}

reload_cmd() {
  build_common_env
  local session
  session="$(require_session "$@")"
  local cli=(--session "${session}" reload)
  forward_tokens cli --values --session -- "$@"
  run_cli "${cli[@]}"
}

screenshot_cmd() {
  build_common_env
  ensure_npx
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
  forward_tokens cli --values --session --name -- "$@"

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
  forward_tokens cli --values --session -- "$@"
  run_cli "${cli[@]}"
}

trace_stop_cmd() {
  build_common_env
  local session
  session="$(require_session "$@")"
  local cli=(--session "${session}" tracing-stop)
  forward_tokens cli --values --session -- "$@"
  run_cli "${cli[@]}"
}

cookie_cmd() {
  build_common_env
  command -v node >/dev/null 2>&1 || fail "node was not found on PATH."
  node "${script_dir}/cookie-helper.js" --output-root "${output_root}" --workspace-root "${workspace_root}" --daemon-root "${daemon_root}" "$@"
  exit $?
}

state_cmd() {
  [[ $# -ge 1 ]] || fail "state requires save or load."
  local operation="$1"
  shift
  build_common_env
  ensure_npx
  local session
  session="$(require_session "$@")"
  local file_value=""
  file_value="$(get_option_value --file "$@" || true)"

  case "${operation}" in
    save)
      local state_file=""
      if [[ -n "${file_value}" ]]; then
        state_file="$(resolve_workspace_file_path "${file_value}")"
        mkdir -p "$(dirname "${state_file}")"
      else
        local safe_session
        safe_session="$(safe_path_segment "${session}")"
        local state_dir="${output_root}/${safe_session}"
        mkdir -p "${state_dir}"
        state_file="${state_dir}/storage-state-$(timestamp).json"
      fi

      printf '%s\n' "[pw-auto] warning: state file contains credentials. Delete or rotate after use: ${state_file}" >&2
      "${npx_cmd}" "${cli_prefix[@]}" --session "${session}" state-save "${state_file}"
      local code=$?
      if [[ ${code} -eq 0 ]]; then
        printf '%s\n' "[pw-auto] state=${state_file}"
      fi
      exit ${code}
      ;;
    load)
      [[ -n "${file_value}" ]] || fail "state load requires --file <path>."
      local state_file
      state_file="$(resolve_workspace_file_path "${file_value}")"
      [[ -f "${state_file}" ]] || fail "state file '${file_value}' does not exist."

      printf '%s\n' "[pw-auto] warning: state load restores browser state only. Run reload/goto, snapshot, and an app-specific auth probe before product checks." >&2
      "${npx_cmd}" "${cli_prefix[@]}" --session "${session}" state-load "${state_file}"
      exit $?
      ;;
    *)
      fail "unknown state command '${operation}'. Use save or load."
      ;;
  esac
}

target_first_cmd() {
  if [[ -n "${pw_auto_workspace_override}" ]]; then
    PW_AUTO_WORKSPACE="$(resolve_workspace_root)" bash "${script_dir}/target-first.sh" "$@"
  else
    bash "${script_dir}/target-first.sh" "$@"
  fi
  exit $?
}

sessions_cmd() {
  build_common_env
  run_cli list
}

recover_cmd() {
  build_common_env
  ensure_npx
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
  ensure_npx
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
  ensure_npx
  local session=""
  session="$(get_option_value --session "$@" || true)"
  local cli=()
  if [[ -n "${session}" ]]; then
    cli+=(--session "${session}")
  fi
  forward_tokens cli --values --session -- "$@"
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

if [[ $# -lt 1 ]]; then
  write_help
fi

command_name="$1"
shift

if is_help_token "${command_name}"; then
  if [[ $# -gt 0 ]]; then
    write_help "$1"
  fi
  write_help
fi

if [[ $# -gt 0 ]] && is_help_token "$1"; then
  write_help "${command_name}"
fi

case "${command_name}" in
  help|--help|-h) write_help "$@" ;;
  doctor) doctor ;;
  open) open_cmd "$@" ;;
  goto) goto_cmd "$@" ;;
  reload) reload_cmd "$@" ;;
  snapshot) snapshot_cmd "$@" ;;
  screenshot) screenshot_cmd "$@" ;;
  trace-start) trace_start_cmd "$@" ;;
  trace-stop) trace_stop_cmd "$@" ;;
  cookie) cookie_cmd "$@" ;;
  state) state_cmd "$@" ;;
  target-first) target_first_cmd "$@" ;;
  sessions) sessions_cmd ;;
  recover) recover_cmd "$@" ;;
  cleanup) cleanup_cmd "$@" ;;
  run) run_cmd "$@" ;;
  cli) run_cmd "$@" ;;
  raw) run_cmd "$@" ;;
  *) fail "unknown command '${command_name}'." ;;
esac
