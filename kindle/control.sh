#!/bin/sh
# Only these bounded device operations are accepted; no arbitrary command strings.
set -u
cd /mnt/us/kindle-desk
last=''
if [ -f command.done ]; then read -r last rest < command.done; fi
number() {
  n=$(lipc-get-prop com.lab126.powerd "$1" 2>/dev/null) || n=255
  case "$n" in ''|*[!0-9]*) n=255;; esac
  [ "$n" -le 24 ] || n=255
  printf '%s' "$n"
}
sample=0
while :; do
  if [ "$sample" -eq 0 ]; then
    battery=$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null) || battery=255
    charging=$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null) || charging=255
    case "$battery" in ''|*[!0-9]*) battery=255;; esac
    [ "$battery" -le 100 ] || battery=255
    case "$charging" in 0|1) :;; *) charging=255;; esac
    mode=0; [ ! -e native-settings ] || mode=1
    printf '%s %s %s %s %s\n' "$battery" "$charging" "$(number flIntensity)" "$(number currentAmberLevel)" "$mode" > telemetry.tmp
    mv telemetry.tmp telemetry
  fi
  sample=$(((sample+1)%15))
  if [ -f command.req ]; then
    read -r seq code value < command.req
    case "$seq" in ''|*[!0-9a-f]*) sleep 1; continue;; esac
    if [ "${#seq}" -eq 16 ] && [ "$seq" != "$last" ]; then
      status=0
      case "$value" in ''|*[!0-9]*) status=1;; esac
      if [ "$status" -eq 0 ] && [ "$value" -le 24 ]; then
        case "$code" in
          1) lipc-set-prop -i com.lab126.powerd flIntensity "$value" || status=1;;
          2) lipc-set-prop -i com.lab126.powerd currentAmberLevel "$value" || status=1;;
          3)
            sh ./ui-mode.sh native || status=1
            ;;
          4)
            sh ./ui-mode.sh dashboard || status=1
            ;;
          5) :;;
          *) status=1;;
        esac
      else status=1
      fi
      brightness=$(number flIntensity)
      warmth=$(number currentAmberLevel)
      mode=0; [ ! -e native-settings ] || mode=1
      printf '%s %s %s %s %s %s\n' "$seq" "$code" "$brightness" "$warmth" "$mode" "$status" > command.done.tmp
      mv command.done.tmp command.done
      last=$seq
    fi
  fi
  sleep 1
done
