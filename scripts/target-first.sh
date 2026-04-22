#!/usr/bin/env bash
set -u

fail() {
  printf '%s\n' "[pw-auto] $1" >&2
  exit "${2:-1}"
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

get_option_values() {
  local name="$1"
  shift
  local token
  local next_is_value=0
  for token in "$@"; do
    if [[ "${next_is_value}" -eq 1 ]]; then
      printf '%s\n' "${token}"
      next_is_value=0
      continue
    fi
    if [[ "${token}" == "${name}" ]]; then
      next_is_value=1
      continue
    fi
    if [[ "${token}" == "${name}="* ]]; then
      printf '%s\n' "${token#${name}=}"
    fi
  done
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

invoke_wrapper_capture() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local output
  output="$(bash "${script_dir}/playwright-automation.sh" "$@" 2>&1)"
  local code=$?
  printf '%s' "${output}"
  return ${code}
}

show_help() {
  printf '%s\n' "[pw-auto] usage:"
  printf '%s\n' "[pw-auto]   target-first.sh fill --session <name> --text <value> --target <target> [--target <target> ...] [--submit] [--settle-ms <ms>]"
  printf '%s\n' "[pw-auto]   target-first.sh click --session <name> --target <target> [--target <target> ...] [button] [--settle-ms <ms>] [--modifiers <keys>]"
  printf '%s\n' "[pw-auto] notes:"
  printf '%s\n' "[pw-auto]   order targets as stable selectors first and snapshot refs last"
  printf '%s\n' "[pw-auto]   fill and click stop on the first successful target"
  printf '%s\n' "[pw-auto]   --settle-ms runs wrapper settle logic via eval after success"
  exit 0
}

if [[ $# -lt 1 ]]; then
  show_help
fi

command_name="$1"
shift

if [[ "${command_name}" == "help" || "${command_name}" == "--help" || "${command_name}" == "-h" ]]; then
  show_help
fi

session="$(get_option_value --session "$@" || true)"
[[ -n "${session}" ]] || fail "missing required --session <name>."

targets=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && targets+=("${line}")
done < <(get_option_values --target "$@")
[[ ${#targets[@]} -gt 0 ]] || fail "missing required --target <target>."

settle_ms="$(get_option_value --settle-ms "$@" || true)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${command_name}" in
  fill)
    text="$(get_option_value --text "$@" || true)"
    [[ -n "${text}" ]] || fail "fill requires --text <value>."
    submit=0
    if has_flag --submit "$@"; then
      submit=1
    fi
    last_failure=""
    for target in "${targets[@]}"; do
      wrapper_args=(run fill "${target}" "${text}" --session "${session}")
      if [[ ${submit} -eq 1 ]]; then
        wrapper_args+=(--submit)
      fi
      output="$(invoke_wrapper_capture "${wrapper_args[@]}")"
      code=$?
      if [[ ${code} -eq 0 ]]; then
        [[ -n "${output}" ]] && printf '%s\n' "${output}"
        printf '%s\n' "[pw-auto] resolved-target=${target}"
        if [[ -n "${settle_ms}" ]]; then
          bash "${script_dir}/playwright-automation.sh" run eval "() => new Promise((resolve) => setTimeout(resolve, ${settle_ms}))" --session "${session}"
          exit $?
        fi
        exit 0
      fi
      last_failure="${output}"
    done
    printf '%s\n' "[pw-auto] target-first fill failed. None of the provided targets worked for session '${session}'."
    [[ -n "${last_failure}" ]] && printf '%s\n' "${last_failure}"
    exit 1
    ;;
  click)
    button=""
    modifiers="$(get_option_value --modifiers "$@" || true)"
    tokens=("$@")
    index=0
    while [[ ${index} -lt ${#tokens[@]} ]]; do
      token="${tokens[${index}]}"
      if [[ "${token}" == --* ]]; then
        case "${token}" in
          --session|--target|--modifiers|--settle-ms)
            index=$((index + 2))
            continue
            ;;
          *)
            index=$((index + 1))
            continue
            ;;
        esac
      fi
      if [[ "${token}" == "${session}" ]]; then
        index=$((index + 1))
        continue
      fi
      is_target=0
      for target in "${targets[@]}"; do
        if [[ "${token}" == "${target}" ]]; then
          is_target=1
          break
        fi
      done
      if [[ ${is_target} -eq 0 ]]; then
        button="${token}"
        break
      fi
      index=$((index + 1))
    done
    last_failure=""
    for target in "${targets[@]}"; do
      wrapper_args=(run click "${target}" --session "${session}")
      if [[ -n "${button}" ]]; then
        wrapper_args=(run click "${target}" "${button}" --session "${session}")
      fi
      if [[ -n "${modifiers}" ]]; then
        wrapper_args+=(--modifiers "${modifiers}")
      fi
      output="$(invoke_wrapper_capture "${wrapper_args[@]}")"
      code=$?
      if [[ ${code} -eq 0 ]]; then
        [[ -n "${output}" ]] && printf '%s\n' "${output}"
        printf '%s\n' "[pw-auto] resolved-target=${target}"
        if [[ -n "${settle_ms}" ]]; then
          bash "${script_dir}/playwright-automation.sh" run eval "() => new Promise((resolve) => setTimeout(resolve, ${settle_ms}))" --session "${session}"
          exit $?
        fi
        exit 0
      fi
      last_failure="${output}"
    done
    printf '%s\n' "[pw-auto] target-first click failed. None of the provided targets worked for session '${session}'."
    [[ -n "${last_failure}" ]] && printf '%s\n' "${last_failure}"
    exit 1
    ;;
  *)
    fail "unknown command '${command_name}'. Use fill or click."
    ;;
esac
