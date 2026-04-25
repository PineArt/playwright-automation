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
[pw-auto]   snapshot     capture current refs for an existing session
[pw-auto]   screenshot   save a screenshot under output/playwright/<session>/
[pw-auto]   trace-start  start Playwright tracing for a session
[pw-auto]   trace-stop   stop Playwright tracing for a session
[pw-auto]   cookie       set, list, or clear cookies without echoing values
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
[pw-auto] usage: playwright-automation [--workspace <path>] open <url> --session <name> --mode <headed|headless> [--maximize] [extra playwright-cli open flags]
[pw-auto] description: open a browser page in a named session
[pw-auto] required:
[pw-auto]   <url>
[pw-auto]   --session <name>
[pw-auto]   --mode headed|headless
[pw-auto] notes:
[pw-auto]   headed maps to playwright-cli open --headed
[pw-auto]   --maximize injects a temporary config so Chromium-family browsers start maximized
[pw-auto]   extra flags are forwarded except wrapper-only options
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
[pw-auto]   use this for click, fill, press, console, network, eval, and similar commands
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

require_session() {
  local session
  session="$(get_option_value --session "$@")" || fail "missing required --session <name>."
  printf '%s\n' "${session}"
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

resolve_open_base_config_path() {
  local config_value
  config_value="$(get_option_value --config "$@" || true)"
  if [[ -n "${config_value}" ]]; then
    resolve_config_path "${workspace_root}" "${config_value}"
    return 0
  fi

  local default_config="${workspace_root}/.playwright/cli.config.json"
  if [[ -f "${default_config}" ]]; then
    printf '%s\n' "${default_config}"
  fi
}

create_maximized_open_config() {
  local session="$1"
  shift

  local base_config=""
  base_config="$(resolve_open_base_config_path "$@" || true)"
  if [[ -n "${base_config}" && ! -f "${base_config}" ]]; then
    fail "cannot apply --maximize because config '${base_config}' does not exist."
  fi

  local config_dir="${output_root}/_pwauto"
  mkdir -p "${config_dir}"
  local safe_session
  safe_session="$(printf '%s' "${session}" | tr -c 'A-Za-z0-9._-' '_')"
  local temp_config="${config_dir}/open-${safe_session}-maximize-$(timestamp).json"
  local browser_name=""
  browser_name="$(get_option_value --browser "$@" || true)"

  BASE_CONFIG="${base_config}" TARGET_CONFIG="${temp_config}" BROWSER_NAME="${browser_name}" node - <<'NODE'
const fs = require('fs');
const path = require('path');

const baseConfig = process.env.BASE_CONFIG || '';
const targetConfig = process.env.TARGET_CONFIG;
let config = {};

if (baseConfig) {
  try {
    const raw = fs.readFileSync(baseConfig, 'utf8').trim();
    if (raw)
      config = JSON.parse(raw);
  } catch (error) {
    console.error(`[pw-auto] cannot apply --maximize because config '${baseConfig}' is not valid JSON.`);
    process.exit(1);
  }
}

if (!config || typeof config !== 'object' || Array.isArray(config))
  config = {};

if (!config.browser || typeof config.browser !== 'object' || Array.isArray(config.browser))
  config.browser = {};

const browserName = process.env.BROWSER_NAME || config.browser.browserName || '';
if (browserName === 'firefox' || browserName === 'webkit') {
  console.error('[pw-auto] --maximize is supported only for Chromium-family browsers.');
  process.exit(1);
}

if (!config.browser.launchOptions || typeof config.browser.launchOptions !== 'object' || Array.isArray(config.browser.launchOptions))
  config.browser.launchOptions = {};
if (browserName) {
  if (browserName === 'chrome' || browserName.startsWith('chrome-')) {
    config.browser.browserName = 'chromium';
    config.browser.launchOptions.channel = browserName;
  } else if (browserName === 'msedge' || browserName.startsWith('msedge-')) {
    config.browser.browserName = 'chromium';
    config.browser.launchOptions.channel = browserName;
  } else {
    config.browser.browserName = browserName;
  }
}

const launchArgs = Array.isArray(config.browser.launchOptions.args) ? config.browser.launchOptions.args.map(String) : [];
if (!launchArgs.includes('--start-maximized'))
  launchArgs.push('--start-maximized');
config.browser.launchOptions.args = launchArgs;

if (!config.browser.contextOptions || typeof config.browser.contextOptions !== 'object' || Array.isArray(config.browser.contextOptions))
  config.browser.contextOptions = {};
config.browser.contextOptions.viewport = null;

fs.mkdirSync(path.dirname(targetConfig), { recursive: true });
fs.writeFileSync(targetConfig, `${JSON.stringify(config, null, 2)}\n`);
NODE
  local node_code=$?
  [[ ${node_code} -eq 0 ]] || exit ${node_code}

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

  build_common_env
  ensure_npx
  local cli=(--session "${session}" open "${url}")
  local forward_args=(--values --mode --session)
  if [[ ${maximize} -eq 1 ]]; then
    forward_args+=(--flags --maximize)
    if get_option_value --config "$@" >/dev/null 2>&1; then
      forward_args+=(--values --config)
    fi
    if get_option_value --browser "$@" >/dev/null 2>&1; then
      forward_args+=(--values --browser)
    fi
  fi
  forward_tokens cli "${forward_args[@]}" -- "$@"

  if [[ "${mode}" == "headed" ]]; then
    cli+=(--headed)
  fi
  if [[ ${maximize} -eq 1 ]]; then
    unset PLAYWRIGHT_MCP_VIEWPORT_SIZE
    local temp_config
    temp_config="$(create_maximized_open_config "${session}" "$@")"
    cli+=(--config "${temp_config}")
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
  snapshot) snapshot_cmd "$@" ;;
  screenshot) screenshot_cmd "$@" ;;
  trace-start) trace_start_cmd "$@" ;;
  trace-stop) trace_stop_cmd "$@" ;;
  cookie) cookie_cmd "$@" ;;
  sessions) sessions_cmd ;;
  recover) recover_cmd "$@" ;;
  cleanup) cleanup_cmd "$@" ;;
  run) run_cmd "$@" ;;
  cli) run_cmd "$@" ;;
  raw) run_cmd "$@" ;;
  *) fail "unknown command '${command_name}'." ;;
esac
