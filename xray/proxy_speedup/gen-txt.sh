#!/bin/bash
set -euo pipefail

SHELL_FOLDER=$(cd "$(dirname "$0")" && pwd)
exec bash "$SHELL_FOLDER/../gen-txt.sh" "$SHELL_FOLDER" "$@"
