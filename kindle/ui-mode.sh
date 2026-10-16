#!/bin/sh
# Keep native X/framework/WM/pillow alive; use an ordinary application window.
set -u
BASE=${KINDLE_DESK_BASE:-/mnt/us/kindle-desk}
LOCAL=${KINDLE_DESK_LOCAL:-/tmp/kindle-desk-ui}
VIEWER=${KINDLE_DESK_VIEWER:-$BASE/bin/dashboard-viewer}
mkdir -p "$LOCAL"
LOCK=${KINDLE_DESK_UI_LOCK:-/tmp/kindle-desk-ui-lock}
mkdir "$LOCK" 2>/dev/null || exit 1
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
touch "$BASE/native-settings"
restore_legacy() {
  # Migrate an already-running older receiver without restarting the native UI.
  if [ -e "$LOCAL/ui-owned" ]; then
    killall -CONT awesome 2>/dev/null || return 1
    lipc-set-prop com.lab126.pillow disableEnablePillow enable || return 1
    if [ -f "$LOCAL/ui-jobs" ]; then
      while read -r job; do
        case "$job" in statusbar|webreader|kfxreader|kfxview)
          initctl status "$job" | grep -q 'start/running' || start "$job" || return 1;;
        esac
      done < "$LOCAL/ui-jobs"
    fi
    rm -f "$LOCAL/ui-owned" "$LOCAL/ui-jobs"
  fi
}
viewer_running() {
  [ -s "$LOCAL/viewer.ready" ] || return 1
  read -r pid < "$LOCAL/viewer.ready"
  case "$pid" in ''|*[!0-9]*) return 1;; esac
  kill -0 "$pid" 2>/dev/null
}
stop_viewer() {
  touch "$LOCAL/viewer.quit"
  i=0
  while viewer_running && [ "$i" -lt 5 ]; do i=$((i+1)); sleep 1; done
  ! viewer_running
}
case "${1:-}" in
  native)
    stop_viewer || exit 1
    restore_legacy || exit 1
    lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
    ;;
  dashboard)
    initctl status x | grep -q 'start/running' || exit 1
    initctl status framework | grep -q 'start/running' || exit 1
    restore_legacy || exit 1
    if viewer_running; then rm -f "$BASE/native-settings"; exit 0; fi
    rm -f "$LOCAL/viewer.quit" "$LOCAL/viewer.ready"
    KINDLE_DESK_LOCAL="$LOCAL" "$VIEWER" "$BASE" >> "$BASE/viewer.log" 2>&1 &
    viewer_pid=$!
    i=0
    while [ "$i" -lt 8 ]; do
      if viewer_running; then rm -f "$BASE/native-settings"; exit 0; fi
      kill -0 "$viewer_pid" 2>/dev/null || break
      i=$((i+1)); sleep 1
    done
    touch "$LOCAL/viewer.quit"
    # This PID belongs to the child launched above, never an arbitrary pidfile.
    kill "$viewer_pid" 2>/dev/null || true
    exit 1
    ;;
  *) exit 2;;
esac
