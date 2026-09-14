#!/usr/bin/python3 -I
"""
dock-audio.py - Per-application audio mute controller for Omarchy macOS Dock
Interacts with PipeWire / PulseAudio (via pactl) and Hyprland (hyprctl) to
find audio streams belonging to a dock application and toggle or report mute state.
"""

import sys
import os
import json
import secrets
import select
import signal
import stat
import subprocess
import glob
import re
import time

# Tools by absolute path only; nothing is resolved through PATH.
PGREP = "/usr/bin/pgrep"
HYPRCTL = "/usr/bin/hyprctl"
PACTL = "/usr/bin/pactl"
NOTIFY_SEND = "/usr/bin/notify-send"

HOME = os.environ.get("HOME", "")
UID = os.getuid()
STATE_DIR_PARTS = (".config", "omarchy")
MUTED_NAME = "dock-muted-apps.json"
MAX_STATE_BYTES = 64 * 1024
MAX_KEYS = 512
MAX_KEY_LEN = 512
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC

# Output budgets and deadlines for every tool this helper runs.
T_TOOL = 5
B_LARGE = 2 * 1024 * 1024   # hyprctl clients -j, pactl list sink-inputs
B_SMALL = 64 * 1024         # pgrep, pactl set-*, notify-send



def private_dir(fd):
    st = os.fstat(fd)
    return stat.S_ISDIR(st.st_mode) and st.st_uid == UID and not (st.st_mode & 0o022)


def open_state_dir(create=False):
    """Descriptor for $HOME/.config/omarchy with every component from $HOME
    down opened O_NOFOLLOW relative to the previous one; $HOME and the two
    directories below it must be owned by this uid and not group/world
    writable. Returns None if unusable."""
    if not HOME.startswith("/") or HOME == "/":
        return None
    parts = [p for p in HOME.split("/") if p]
    try:
        fd = os.open("/", DIR_FLAGS)
        for name in parts:
            nxt = os.open(name, DIR_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = nxt
        if not private_dir(fd):
            os.close(fd)
            return None
        for name in STATE_DIR_PARTS:
            try:
                nxt = os.open(name, DIR_FLAGS, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    os.close(fd)
                    return None
                try:
                    os.mkdir(name, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
                nxt = os.open(name, DIR_FLAGS, dir_fd=fd)
            os.close(fd)
            fd = nxt
            if not private_dir(fd):
                os.close(fd)
                return None
        return fd
    except OSError:
        return None


def kill_group(pid):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except OSError:
            return
        time.sleep(0.2)


def run_bounded(cmd, budget=B_SMALL, timeout=T_TOOL):
    """Run cmd in its own process group; read stdout against a byte budget and
    a deadline; kill the group on either. Returns (rc, text)."""
    try:
        p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, close_fds=True, process_group=0,
                             env={"HOME": HOME, "PATH": "/usr/bin", "LANG": "C.UTF-8",
                                  "XDG_RUNTIME_DIR": os.environ.get("XDG_RUNTIME_DIR", ""),
                                  "HYPRLAND_INSTANCE_SIGNATURE": os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""),
                                  "WAYLAND_DISPLAY": os.environ.get("WAYLAND_DISPLAY", ""),
                                  "DBUS_SESSION_BUS_ADDRESS": os.environ.get("DBUS_SESSION_BUS_ADDRESS", ""),
                                  "PULSE_SERVER": os.environ.get("PULSE_SERVER", "")})
    except OSError:
        return 127, ""
    out = bytearray()
    fd = p.stdout.fileno()
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            kill_group(p.pid)
            p.wait(timeout=5)
            return 124, ""
        ready, _, _ = select.select([fd], [], [], min(remaining, 0.5))
        if not ready:
            continue
        chunk = os.read(fd, 65536)
        if not chunk:
            break
        out += chunk
        if len(out) > budget:
            kill_group(p.pid)
            p.wait(timeout=5)
            return 125, ""
    try:
        rc = p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        kill_group(p.pid)
        rc = 124
    return rc, bytes(out).decode("utf-8", "replace")


def normalize_name(s):
    if not s:
        return ""
    # Strip common suffixes and special characters for fuzzy matching
    s = str(s).lower().strip()
    s = re.sub(r"\.desktop$", "", s)
    s = re.sub(r"-(stable|bin|git|oss|browser|desktop|electron)$", "", s)
    return re.sub(r"[^a-z0-9]", "", s)


# Tokens too generic to identify an application. Matching them would let
# unrelated streams cross-match ("desktop", reverse-DNS prefixes, ...).
GENERIC_TOKENS = {
    "org", "com", "io", "net", "github", "gitlab", "gnome", "kde", "xfce",
    "app", "apps", "linux", "desktop", "stable", "bin", "git", "oss",
    "browser", "electron", "client", "native", "web", "preview", "beta",
    "dev", "nightly", "the",
}


def name_tokens(s):
    if not s:
        return set()
    parts = re.split(r"[^a-z0-9]+", str(s).lower())
    return {p for p in parts if len(p) >= 2 and p not in GENERIC_TOKENS}


def stream_pid_of(props):
    try:
        return int(props.get("application.process.id"))
    except (TypeError, ValueError):
        return None


def load_muted_state():
    """Bounded, shape-checked read: regular file, owned by this uid, one link,
    at most MAX_STATE_BYTES; a JSON object of at most MAX_KEYS string keys
    mapping to true."""
    dfd = open_state_dir()
    if dfd is None:
        return {}
    try:
        try:
            fd = os.open(MUTED_NAME, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dfd)
        except OSError:
            return {}
        try:
            st = os.fstat(fd)
            if (not stat.S_ISREG(st.st_mode) or st.st_uid != UID or st.st_nlink != 1
                    or st.st_size > MAX_STATE_BYTES):
                return {}
            data = b""
            while len(data) < st.st_size:
                chunk = os.read(fd, st.st_size - len(data))
                if not chunk:
                    break
                data += chunk
        finally:
            os.close(fd)
        try:
            parsed = json.loads(data.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return {}
        if not isinstance(parsed, dict):
            return {}
        return {k: True for k, v in list(parsed.items())[:MAX_KEYS]
                if isinstance(k, str) and len(k) <= MAX_KEY_LEN and v is True}
    finally:
        os.close(dfd)


def save_muted_state(state):
    """Descriptor-relative atomic write: random exclusive temp file in the
    verified directory, fsync, then rename over the target."""
    dfd = open_state_dir(create=True)
    if dfd is None:
        sys.stderr.write("Error saving muted state: config directory is not usable\n")
        return
    state = {k: True for k, v in list(state.items())[:MAX_KEYS]
             if isinstance(k, str) and len(k) <= MAX_KEY_LEN and v is True}
    tmp = ".dock-muted-apps." + secrets.token_hex(8) + ".tmp"
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=dfd)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp, MUTED_NAME, src_dir_fd=dfd, dst_dir_fd=dfd)
    except Exception as e:
        sys.stderr.write(f"Error saving muted state: {e}\n")
        try:
            os.unlink(tmp, dir_fd=dfd)
        except OSError:
            pass
    finally:
        os.close(dfd)


def get_descendant_pids(pid):
    descendants = set()
    try:
        pid_int = int(pid)
    except (ValueError, TypeError):
        return descendants

    to_check = [pid_int]
    while to_check:
        curr = to_check.pop()
        descendants.add(curr)
        # Try reading /proc/<pid>/task/*/children
        child_pids = set()
        for path in glob.glob(f"/proc/{curr}/task/*/children"):
            try:
                with open(path, "r") as f:
                    for token in f.read().split():
                        child_pids.add(int(token))
            except Exception:
                pass
        # Fallback to pgrep if /proc had no entries or empty
        if not child_pids:
            rc, out = run_bounded([PGREP, "-P", str(curr)], B_SMALL)
            if rc == 0:
                for line in out.splitlines():
                    if line.strip().isdigit():
                        child_pids.add(int(line.strip()))
        for cp in child_pids:
            if cp not in descendants:
                to_check.append(cp)

    return descendants


def get_hyprland_clients():
    rc, out = run_bounded([HYPRCTL, "clients", "-j"], B_LARGE)
    if rc != 0:
        return []
    try:
        clients = json.loads(out)
    except ValueError:
        return []
    return [c for c in clients if isinstance(c, dict)][:2000] if isinstance(clients, list) else []


def get_sink_inputs():
    rc, out = run_bounded([PACTL, "list", "sink-inputs"], B_LARGE)
    if rc != 0:
        return []

    inputs = []
    curr = None
    for raw_line in out.splitlines():
        line = raw_line.strip()
        if line.startswith("Sink Input #"):
            if curr:
                inputs.append(curr)
            curr = {"id": line.split("#")[1].strip(), "muted": False, "props": {}}
        elif curr is not None:
            if line.startswith("Mute:"):
                curr["muted"] = (line.split(":", 1)[1].strip().lower() == "yes")
            elif "=" in line:
                parts = line.split("=", 1)
                k = parts[0].strip()
                v = parts[1].strip().strip('"')
                curr["props"][k] = v
    if curr:
        inputs.append(curr)
    return inputs


def find_matching_streams(app_id, app_name):
    norm_id = normalize_name(app_id)
    norm_name = normalize_name(app_name)

    # 1. Gather all PIDs for windows belonging to this app from Hyprland
    clients = get_hyprland_clients()
    target_pids = set()
    for c in clients:
        c_class = normalize_name(c.get("class"))
        c_init = normalize_name(c.get("initialClass"))
        c_title = normalize_name(c.get("title"))

        matched = False
        if norm_id and (norm_id in c_class or c_class in norm_id or norm_id in c_init or c_init in norm_id):
            matched = True
        elif norm_name and (norm_name in c_title or norm_name in c_class or c_class in norm_name):
            matched = True

        if matched:
            win_pid = c.get("pid")
            if win_pid:
                target_pids.update(get_descendant_pids(win_pid))

    # 2. Check all active sink inputs
    sink_inputs = get_sink_inputs()
    matching_streams = []

    for si in sink_inputs:
        props = si.get("props", {})
        stream_pid = stream_pid_of(props)
        stream_name = props.get("application.name")
        stream_bin = props.get("application.process.binary")
        stream_app_id = props.get("application.id")

        is_match = False
        # PID match
        if stream_pid is not None and stream_pid in target_pids:
            is_match = True
        else:
            # Metadata fallback: exact normalized equality or a shared
            # meaningful token. Raw substrings are never used, so an app named
            # "Code" cannot match a stream named "Unicode" (and vice versa).
            app_tokens = name_tokens(app_name) | name_tokens(app_id)
            for val in [stream_name, stream_bin, stream_app_id]:
                if not val:
                    continue
                nval = normalize_name(val)
                if nval and (nval == norm_id or nval == norm_name):
                    is_match = True
                    break
                if app_tokens & name_tokens(val):
                    is_match = True
                    break

        if is_match:
            matching_streams.append(si)

    return matching_streams


def notify(title, message, icon="audio-volume-muted"):
    run_bounded([NOTIFY_SEND, "-a", "Omarchy Dock", "-i", icon, "-u", "low", str(title)[:200], str(message)[:200]], B_SMALL)


def cmd_status(app_id, app_name):
    streams = find_matching_streams(app_id, app_name)
    state = load_muted_state()
    saved_muted = bool(state.get(app_id) or state.get(app_name))

    if streams:
        # If any stream is unmuted, consider it unmuted; if all are muted, consider muted
        all_muted = all(s.get("muted", False) for s in streams)
        is_muted = all_muted
    else:
        is_muted = saved_muted

    result = {
        "app_id": app_id,
        "app_name": app_name,
        "has_streams": len(streams) > 0,
        "is_muted": is_muted,
        "stream_count": len(streams),
        "stream_ids": [s["id"] for s in streams]
    }
    print(json.dumps(result))
    return 0


def cmd_toggle(app_id, app_name):
    streams = find_matching_streams(app_id, app_name)
    state = load_muted_state()
    saved_muted = bool(state.get(app_id) or state.get(app_name))

    if streams:
        all_muted = all(s.get("muted", False) for s in streams)
        new_mute_target = not all_muted
        new_val_str = "1" if new_mute_target else "0"

        for s in streams:
            run_bounded([PACTL, "set-sink-input-mute", str(s["id"])[:16], new_val_str], B_SMALL)
        is_muted = new_mute_target
    else:
        is_muted = not saved_muted

    # Update persistent state
    key = app_id or app_name
    if is_muted:
        state[key] = True
        if app_name and app_name != key:
            state[app_name] = True
    else:
        state.pop(key, None)
        if app_name:
            state.pop(app_name, None)
    save_muted_state(state)

    # Notification
    display_name = app_name or app_id or "Application"
    if is_muted:
        notify(display_name, "Audio muted (silent)", "audio-volume-muted")
    else:
        notify(display_name, "Audio restored", "audio-volume-high")

    result = {
        "app_id": app_id,
        "app_name": app_name,
        "is_muted": is_muted,
        "stream_count": len(streams),
        "stream_ids": [s["id"] for s in streams]
    }
    print(json.dumps(result))
    return 0


def cmd_mute(app_id, app_name):
    streams = find_matching_streams(app_id, app_name)
    state = load_muted_state()
    for s in streams:
        run_bounded([PACTL, "set-sink-input-mute", str(s["id"])[:16], "1"], B_SMALL)
    key = app_id or app_name
    state[key] = True
    if app_name:
        state[app_name] = True
    save_muted_state(state)
    display_name = app_name or app_id or "Application"
    notify(display_name, "Audio muted (silent)", "audio-volume-muted")
    print(json.dumps({"app_id": app_id, "is_muted": True, "stream_count": len(streams)}))
    return 0


def cmd_unmute(app_id, app_name):
    streams = find_matching_streams(app_id, app_name)
    state = load_muted_state()
    for s in streams:
        run_bounded([PACTL, "set-sink-input-mute", str(s["id"])[:16], "0"], B_SMALL)
    key = app_id or app_name
    state.pop(key, None)
    if app_name:
        state.pop(app_name, None)
    save_muted_state(state)
    display_name = app_name or app_id or "Application"
    notify(display_name, "Audio restored", "audio-volume-high")
    print(json.dumps({"app_id": app_id, "is_muted": False, "stream_count": len(streams)}))
    return 0


def cmd_sync():
    state = load_muted_state()
    if not state:
        print(json.dumps({"synced": 0}))
        return 0
    synced_count = 0
    sink_inputs = get_sink_inputs()
    for app_key, is_muted in state.items():
        if not is_muted:
            continue
        streams = find_matching_streams(app_key, app_key)
        for s in streams:
            if not s.get("muted", False):
                run_bounded([PACTL, "set-sink-input-mute", str(s["id"])[:16], "1"], B_SMALL)
                synced_count += 1
    print(json.dumps({"synced": synced_count}))
    return 0


def main():
    if len(sys.argv) < 2:
        print("Usage: dock-audio.py <status|toggle|mute|unmute|sync> <app_id> [app_name]")
        return 1

    action = sys.argv[1].lower()
    if action == "sync":
        return cmd_sync()

    app_id = sys.argv[2] if len(sys.argv) > 2 else ""
    app_name = sys.argv[3] if len(sys.argv) > 3 else ""

    if action == "status":
        return cmd_status(app_id, app_name)
    elif action == "toggle":
        return cmd_toggle(app_id, app_name)
    elif action == "mute":
        return cmd_mute(app_id, app_name)
    elif action == "unmute":
        return cmd_unmute(app_id, app_name)
    else:
        sys.stderr.write(f"Unknown action: {action}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())

