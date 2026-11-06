#!/bin/bash
cd -- "$(dirname -- "$0")" || exit 2
# Finder does not necessarily inherit a terminal's Homebrew PATH. The system
# Bash can run this small launcher, then hand off to the locally installed floor.
if [[ "$(uname -s)" == Darwin ]]; then export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; fi
recovery_bash=''
for candidate in "$(command -v bash)" /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$candidate" ]] && "$candidate" -c '(( BASH_VERSINFO[0] >= 4 ))'; then
        recovery_bash="$candidate"; break
    fi
done
if [[ -z "$recovery_bash" ]]; then
    printf '%s\n' 'Recovery requires a locally installed Bash 4+ (for example Homebrew bash), GNU awk, xxHash and coreutils.' >&2
    if (( $# == 0 )) && [[ -t 0 ]]; then read -r -p 'Press Enter to close' _answer; fi
    exit 2
fi
if (( $# == 0 )); then
    exec "$recovery_bash" ./reconstruct.sh --interactive
else
    exec "$recovery_bash" ./reconstruct.sh "$@"
fi
