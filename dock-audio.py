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
import stat
import subprocess
import glob
import re

# Tools by absolute path only; nothing is resolved through PATH.
PGREP = "/usr/bin/pgrep"
HYPRCTL = "/usr/bin/hyprctl"
PACTL = "/usr/bin/pactl"
NOTIFY_SEND = "/usr/bin/notify-send"

CONFIG_DIR = os.path.join(os.environ.get("HOME", ""), ".config/omarchy")
MUTED_NAME = "dock-muted-apps.json"
MUTED_FILE = os.path.join(CONFIG_DIR, MUTED_NAME)
UID = os.getuid()


def open_config_dir():
    """Open the config directory without following symlinks and check ownership."""
    if not CONFIG_DIR.startswith("/"):
        return None
    try:
        os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
        fd = os.open(CONFIG_DIR, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError:
        return None
    st = os.fstat(fd)
    if st.st_uid != UID or (st.st_mode & stat.S_IWOTH):
        os.close(fd)
        return None
    return fd


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
    dfd = open_config_dir()
    if dfd is None:
        return {}
    try:
        fd = os.open(MUTED_NAME, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dfd)
    except OSError:
        os.close(dfd)
        return {}
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != UID:
            return {}
        with os.fdopen(fd, "r", encoding="utf-8") as f:
            fd = -1
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}
    finally:
        if fd >= 0:
            os.close(fd)
        os.close(dfd)


def save_muted_state(state):
    """Descriptor-relative atomic write: random exclusive temp file in the
    verified directory, fsync, then rename over the target."""
    dfd = open_config_dir()
    if dfd is None:
        sys.stderr.write("Error saving muted state: config directory is not usable\n")
        return
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
            try:
                out = subprocess.check_output([PGREP, "-P", str(curr)], text=True, stderr=subprocess.DEVNULL)
                for line in out.splitlines():
                    if line.strip():
                        child_pids.add(int(line.strip()))
            except Exception:
                pass
        for cp in child_pids:
            if cp not in descendants:
                to_check.append(cp)

    return descendants


def get_hyprland_clients():
    try:
        out = subprocess.check_output([HYPRCTL, "clients", "-j"], text=True, stderr=subprocess.DEVNULL)
        return json.loads(out)
    except Exception:
        return []


def get_sink_inputs():
    try:
        res = subprocess.run([PACTL, "list", "sink-inputs"], capture_output=True, text=True, timeout=3)
    except Exception:
        return []

    inputs = []
    curr = None
    for raw_line in res.stdout.splitlines():
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
    try:
        subprocess.run(
            [NOTIFY_SEND, "-a", "Omarchy Dock", "-i", icon, "-u", "low", title, message],
            check=False,
            stderr=subprocess.DEVNULL
        )
    except Exception:
        pass


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
            subprocess.run([PACTL, "set-sink-input-mute", s["id"], new_val_str], check=False)
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
        subprocess.run([PACTL, "set-sink-input-mute", s["id"], "1"], check=False)
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
        subprocess.run([PACTL, "set-sink-input-mute", s["id"], "0"], check=False)
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
                subprocess.run([PACTL, "set-sink-input-mute", s["id"], "1"], check=False)
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

