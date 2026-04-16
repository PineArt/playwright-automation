#!/usr/bin/env bash
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/playwright-automation.sh" recover "$@"

