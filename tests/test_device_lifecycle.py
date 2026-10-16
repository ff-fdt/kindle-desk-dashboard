"""Exercise shell transitions with a failing device command, without hardware."""
import json
import os
from pathlib import Path
import subprocess
import sys

SCRIPT = Path(__file__).resolve().parents[1] / "kindle/ui-mode.sh"


def device(tmp_path, fail=""):
    binary = tmp_path / "bin"
    binary.mkdir()
    state = tmp_path / "device.json"
    state.write_text(json.dumps({"jobs": dict.fromkeys(
        ["x", "framework", "statusbar", "webreader", "kfxreader", "kfxview"], True),
        "wm_paused": False, "pillow": "enable", "calls": [], "fail": fail}))
    runner = binary / "mock"
    runner.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
from pathlib import Path
p = Path(os.environ["MOCK_STATE"])
s = json.loads(p.read_text())
name = Path(sys.argv[0]).name
a = sys.argv[1:]
call = " ".join([name] + a)
s["calls"].append(call)
rc = 0
if s["fail"] and call.startswith(s["fail"]):
    s["fail"] = ""
    rc = 1
elif name == "initctl":
    print(a[1] + (" start/running" if s["jobs"].get(a[1]) else " stop/waiting"))
elif name in ("start", "stop"):
    s["jobs"][a[0]] = name == "start"
elif name == "killall":
    s["wm_paused"] = a[0] == "-STOP"
elif name == "lipc-set-prop" and a[1] == "disableEnablePillow":
    s["pillow"] = a[2]
p.write_text(json.dumps(s))
sys.exit(rc)
''')
    runner.chmod(0o755)
    for name in ["initctl", "start", "stop", "killall", "lipc-set-prop", "fbink"]:
        (binary / name).symlink_to(runner)
    base = tmp_path / "base"
    base.mkdir()
    env = {**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"],
           "MOCK_STATE": str(state), "KINDLE_DESK_BASE": str(base),
           "KINDLE_DESK_LOCAL": str(tmp_path / "local"),
           "KINDLE_DESK_VIEWER": str(binary / "viewer"),
           "KINDLE_DESK_UI_LOCK": str(tmp_path / "lock")}
    viewer = binary / "viewer"
    viewer.write_text(f"#!{sys.executable}\n" + """import os, time
from pathlib import Path
base = Path(os.environ['KINDLE_DESK_LOCAL'])
if not (Path(__import__('sys').argv[1]) / 'frame.png').exists():
    raise SystemExit(5)
(base / 'viewer.ready').write_text(str(os.getpid()))
while not (base / 'viewer.quit').exists():
    time.sleep(0.03)
(base / 'viewer.ready').unlink(missing_ok=True)
""")
    viewer.chmod(0o755)
    (base / "frame.png").write_bytes(b"mock valid image")
    return state, base, env


def transition(env, mode):
    return subprocess.run(["sh", str(SCRIPT), mode], env=env,
                          capture_output=True, text=True, timeout=10)


def assert_native(state):
    s = json.loads(state.read_text())
    assert all(s["jobs"].values())
    assert not s["wm_paused"]
    assert s["pillow"] == "enable"
    assert "stop x" not in s["calls"]
    assert "stop framework" not in s["calls"]


def test_dashboard_native_round_trip_keeps_native_services_running(tmp_path):
    state, base, env = device(tmp_path)
    try:
        assert transition(env, "dashboard").returncode == 0
        assert not (base / "native-settings").exists()
        assert_native(state)
    finally:
        assert transition(env, "native").returncode == 0
    assert (base / "native-settings").exists()
    assert_native(state)


def test_failed_viewer_keeps_native_available(tmp_path):
    state, base, env = device(tmp_path)
    (base / "frame.png").unlink()
    assert transition(env, "dashboard").returncode != 0
    assert (base / "native-settings").exists()
    assert_native(state)


def test_migration_resumes_old_paused_window_manager(tmp_path):
    state, base, env = device(tmp_path)
    s = json.loads(state.read_text())
    s["wm_paused"] = True
    s["pillow"] = "disable"
    s["jobs"]["statusbar"] = False
    state.write_text(json.dumps(s))
    local = Path(env["KINDLE_DESK_LOCAL"])
    local.mkdir()
    (local / "ui-owned").touch()
    (local / "ui-jobs").write_text("statusbar\n")
    try:
        assert transition(env, "dashboard").returncode == 0
        assert_native(state)
    finally:
        transition(env, "native")


def test_failed_legacy_restore_does_not_launch_viewer(tmp_path):
    state, base, env = device(tmp_path, "killall -CONT awesome")
    local = Path(env["KINDLE_DESK_LOCAL"])
    local.mkdir()
    (local / "ui-owned").touch()
    assert transition(env, "dashboard").returncode != 0
    assert (base / "native-settings").exists()
    assert not (local / "viewer.ready").exists()
