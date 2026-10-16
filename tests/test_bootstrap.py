"""Exercise delayed USB-storage release without booting a device."""
import os
from pathlib import Path
import subprocess

SCRIPT = Path(__file__).resolve().parents[1]/'kindle/bootstrap.sh'


def run_bootstrap(tmp_path, mode):
    base, local, binary = [tmp_path/n for n in ('device','persistent','bin')]
    for p in (base,local,binary):p.mkdir()
    (local/'enabled').touch()
    sleeper=binary/'sleep'
    sleeper.write_text('''#!/bin/sh
n=0
[ ! -f "$TEST_ROOT/count" ] || n=$(cat "$TEST_ROOT/count")
n=$((n+1)); echo "$n" > "$TEST_ROOT/count"
if [ "$TEST_MODE" = disabled ]; then rm -f "$KINDLE_DESK_PERSISTENT/enabled"; fi
if [ "$n" -eq 36 ]; then
  mkdir -p "$KINDLE_DESK_BASE/bin"
  printf '#!/bin/sh\\ntouch "$TEST_ROOT/started"\\n' > "$KINDLE_DESK_BASE/run.sh"
  touch "$KINDLE_DESK_BASE/bin/ble-client"
  chmod +x "$KINDLE_DESK_BASE/bin/ble-client"
fi
''')
    sleeper.chmod(0o755)
    if mode=='restore':(base/'restore-reader').touch()
    env={**os.environ,'PATH':str(binary)+os.pathsep+os.environ['PATH'],
         'KINDLE_DESK_BASE':str(base),'KINDLE_DESK_PERSISTENT':str(local),
         'KINDLE_DESK_MANUAL_FLAG':str(tmp_path/'manual'),'TEST_ROOT':str(tmp_path),'TEST_MODE':mode}
    result=subprocess.run(['sh',str(SCRIPT)],env=env,timeout=10)
    return result,local


def test_start_after_usb_assets_return_later_than_old_timeout(tmp_path):
    result,_=run_bootstrap(tmp_path,'delayed')
    assert result.returncode==0
    assert (tmp_path/'started').exists()
    assert int((tmp_path/'count').read_text())==36


def test_disabling_autostart_stops_waiting_for_usb(tmp_path):
    result,_=run_bootstrap(tmp_path,'disabled')
    assert result.returncode==0 and not (tmp_path/'started').exists()


def test_restore_reader_marker_overrides_delayed_start(tmp_path):
    result,local=run_bootstrap(tmp_path,'restore')
    assert result.returncode==0 and not (tmp_path/'started').exists()
    assert not (local/'enabled').exists()
