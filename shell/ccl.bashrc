# shellcheck shell=bash
# Source from ~/.bashrc:   source /path/to/engaging_claude/shell/ccl.bashrc
# Makes plain `claude` use the local model by default (see `ccl mode`).
#   claude [args]          -> local model (or cloud if `ccl mode cloud`)
#   claude --cloud [args]  -> normal Claude Code with your Anthropic login
#   claude --local [args]  -> local model regardless of mode
#   claude --which         -> show what would be used
# Management subcommands (mcp, update, doctor, --version, ...) go straight to the real binary.

_ccl_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case ":$PATH:" in *":$_ccl_repo/bin:"*) ;; *) PATH="$_ccl_repo/bin:$PATH" ;; esac
export PATH
unset _ccl_repo

claude() {
  local target=""
  case "${1:-}" in
    --cloud) shift; target=cloud ;;
    --local) shift; target=local ;;
    --which)
      shift
      case "${1:-}" in
        --cloud) echo "claude --cloud -> Anthropic cloud ($(type -P claude))" ;;
        --local) ccl which | sed 1d ;;
        *) ccl which ;;
      esac
      return ;;
    mcp|update|upgrade|doctor|config|install|migrate-installer|setup-token|plugin|plugins|auth|login|logout|\
    -v|--version|-h|--help)
      command claude "$@"; return ;;
  esac
  [[ -z "$target" ]] && target="$(ccl mode 2>/dev/null || echo local)"
  if [[ "$target" == cloud ]]; then
    ccl cloud "$@"
  else
    ccl local -- "$@"
  fi
}
