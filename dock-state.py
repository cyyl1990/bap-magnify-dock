#!/usr/bin/python3 -I
"""dock-state.py: every read and write of the dock's state files, done behind
verified descriptors with size and shape limits. Used by DockInstance.qml.

  dock-state.py read  <config|presets|muted>     -> one line of JSON (or null)
  dock-state.py write <config|presets|muted>     JSON object on stdin (one line)
  dock-state.py watch                            -> one line per changed file

Files live in $HOME/.config/omarchy. Every component from $HOME down is
opened O_NOFOLLOW relative to the previous one and must be a directory owned
by this uid that is not group- or world-writable. Files are opened O_NOFOLLOW
relative to the verified directory and must be regular, owned by this uid,
with one link and at most MAX_BYTES bytes; exactly that many bytes are read.
Writes go to a random O_EXCL temp file in the verified directory, fsync, then
rename. Content is validated against a fixed shape with cardinality and string
ceilings before it is accepted in either direction.
"""

import ctypes
import json
import os
import secrets
import select
import stat
import struct
import sys

HOME = os.environ.get("HOME", "")
UID = os.getuid()
REL_DIR = (".config", "omarchy")
FILES = {
    "config": "dock-pinned-macos.json",
    "presets": "dock-presets.json",
    "muted": "dock-muted-apps.json",
}
MAX_BYTES = {"config": 256 * 1024, "presets": 512 * 1024, "muted": 64 * 1024}
MAX_STR = 512
MAX_LIST = 256
MAX_KEYS = 512
MAX_PRESETS = 64
MAX_FOLDERS = 8

DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def fail(msg, code=1):
    sys.stderr.write(msg + "\n")
    sys.exit(code)


# ---------- verified directory ----------

def private_dir(fd, what):
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode):
        fail(f"{what} is not a directory")
    if st.st_uid != UID:
        fail(f"{what} is not owned by you")
    if st.st_mode & 0o022:
        fail(f"{what} is writable by others")


def open_state_dir(create=False):
    """Descriptor for $HOME/.config/omarchy, every component verified."""
    if not HOME.startswith("/") or "/../" in HOME + "/" or HOME == "/":
        fail("HOME is not usable")
    parts = [p for p in HOME.split("/") if p]
    fd = os.open("/", DIR_FLAGS)
    so_far = ""
    for i, name in enumerate(parts):
        so_far += "/" + name
        try:
            nxt = os.open(name, DIR_FLAGS, dir_fd=fd)
        except OSError as e:
            fail(f"cannot open {so_far}: {e.strerror}")
        os.close(fd)
        fd = nxt
    private_dir(fd, HOME)
    for name in REL_DIR:
        so_far += "/" + name
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
        except OSError as e:
            fail(f"cannot open {so_far}: {e.strerror}")
        os.close(fd)
        fd = nxt
        private_dir(fd, so_far)
    return fd


# ---------- shape validation ----------

def s(v, limit=MAX_STR):
    return v if isinstance(v, str) and len(v) <= limit else None


def clean_settings(v):
    if not isinstance(v, dict):
        return {}
    out = {}
    for k, val in list(v.items())[:MAX_KEYS]:
        if s(k, 64) is None:
            continue
        if isinstance(val, bool) or (isinstance(val, (int, float)) and abs(val) < 1e9):
            out[k] = val
        elif s(val) is not None:
            out[k] = val
        elif k == "folders" and isinstance(val, list):
            out[k] = [x for x in val[:MAX_FOLDERS] if s(x, 1024) is not None]
    return out


def clean_pins(v):
    if not isinstance(v, list):
        return None
    out = []
    for x in v[:MAX_LIST]:
        if s(x) is not None:
            out.append(x)
        elif isinstance(x, dict) and s(x.get("id")) is not None:
            out.append({"id": x["id"]})
    return out


def clean_config(v):
    if not isinstance(v, dict):
        return None
    out = {"version": 1, "settings": clean_settings(v.get("settings"))}
    for key in ("autoHide", "reserveSpace", "collapsed"):
        if isinstance(v.get(key), bool):
            out[key] = v[key]
    pins = clean_pins(v.get("pinned"))
    if pins is not None:
        out["pinned"] = pins
    if isinstance(v.get("recent"), list):
        out["recent"] = [x for x in v["recent"][:MAX_LIST] if s(x) is not None]
    return out


def clean_presets(v):
    arr = v if isinstance(v, list) else (v.get("presets") if isinstance(v, dict) else None)
    if not isinstance(arr, list):
        return {"version": 1, "presets": []}
    out = []
    for p in arr[:MAX_PRESETS]:
        if not isinstance(p, dict) or s(p.get("name"), 64) is None or not p["name"].strip():
            continue
        entry = {"name": p["name"].strip(), "settings": clean_settings(p.get("settings"))}
        if s(p.get("savedAt"), 40) is not None:
            entry["savedAt"] = p["savedAt"]
        for key in ("autoHide", "reserveSpace"):
            if isinstance(p.get(key), bool):
                entry[key] = p[key]
        pins = clean_pins(p.get("pinned"))
        if pins is not None:
            entry["pinned"] = pins
        out.append(entry)
    return {"version": 1, "presets": out}


def clean_muted(v):
    if not isinstance(v, dict):
        return {}
    return {k: True for k, val in list(v.items())[:MAX_KEYS] if s(k) is not None and val is True}


CLEAN = {"config": clean_config, "presets": clean_presets, "muted": clean_muted}


# ---------- read / write ----------

def read_file(dfd, which):
    name = FILES[which]
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dfd)
    except FileNotFoundError:
        return None
    except OSError as e:
        fail(f"cannot open {name}: {e.strerror}")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != UID or st.st_nlink != 1:
            fail(f"{name} is not a regular file owned by you with a single link")
        if st.st_size > MAX_BYTES[which]:
            fail(f"{name} is larger than {MAX_BYTES[which]} bytes; refusing")
        data = b""
        while len(data) < st.st_size:
            chunk = os.read(fd, st.st_size - len(data))
            if not chunk:
                break
            data += chunk
    finally:
        os.close(fd)
    if not data.strip():
        return None
    try:
        return json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        fail(f"{name} is not valid JSON")


def write_file(dfd, which, obj):
    name = FILES[which]
    payload = (json.dumps(obj, indent=2) + "\n").encode("utf-8")
    if len(payload) > MAX_BYTES[which]:
        fail(f"{name} would exceed {MAX_BYTES[which]} bytes; refusing")
    tmp = "." + name + "." + secrets.token_hex(8) + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=dfd)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp, name, src_dir_fd=dfd, dst_dir_fd=dfd)
    except OSError as e:
        try:
            os.unlink(tmp, dir_fd=dfd)
        except OSError:
            pass
        fail(f"writing {name} failed: {e.strerror}")


def cmd_read(which):
    dfd = open_state_dir(create=False)
    if dfd is None:
        print("null")
        return
    try:
        raw = read_file(dfd, which)
    finally:
        os.close(dfd)
    print("null" if raw is None else json.dumps(CLEAN[which](raw), separators=(",", ":")))


def cmd_write(which):
    line = sys.stdin.buffer.readline(MAX_BYTES[which] + 2)
    if len(line) > MAX_BYTES[which]:
        fail("input too large")
    try:
        raw = json.loads(line.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        fail("input is not valid JSON")
    obj = CLEAN[which](raw)
    if obj is None:
        fail("input has the wrong shape")
    dfd = open_state_dir(create=True)
    try:
        write_file(dfd, which, obj)
    finally:
        os.close(dfd)
    print("ok")


# ---------- watch ----------

IN_CLOSE_WRITE = 0x8
IN_MOVED_TO = 0x80
IN_CREATE = 0x100
IN_DELETE = 0x200
IN_MOVED_FROM = 0x40
IN_Q_OVERFLOW = 0x4000
IN_IGNORED = 0x8000


def cmd_watch():
    dfd = open_state_dir(create=True)
    libc = ctypes.CDLL(None, use_errno=True)
    ino = libc.inotify_init1(0o2000000)
    if ino < 0:
        fail("inotify unavailable")
    mask = IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE | IN_DELETE | IN_MOVED_FROM
    if libc.inotify_add_watch(ino, f"/proc/self/fd/{dfd}".encode(), mask) < 0:
        fail("could not watch the state directory")
    by_name = {v: k for k, v in FILES.items()}
    sys.stdout.write("ready\n")
    sys.stdout.flush()
    while True:
        select.select([ino], [], [])
        buf = os.read(ino, 65536)
        off = 0
        seen = set()
        while off + 16 <= len(buf):
            wd, m, _cookie, ln = struct.unpack_from("iIII", buf, off)
            name = buf[off + 16:off + 16 + ln].rstrip(b"\0").decode("utf-8", "replace")
            off += 16 + ln
            if m & IN_Q_OVERFLOW:
                seen.update(FILES.keys())
            elif name in by_name:
                seen.add(by_name[name])
        for which in sorted(seen):
            sys.stdout.write(which + "\n")
        sys.stdout.flush()


def main(argv):
    os.umask(0o077)
    if len(argv) == 3 and argv[1] == "read" and argv[2] in FILES:
        cmd_read(argv[2])
    elif len(argv) == 3 and argv[1] == "write" and argv[2] in FILES:
        cmd_write(argv[2])
    elif len(argv) == 2 and argv[1] == "watch":
        cmd_watch()
    else:
        fail("usage: dock-state.py read|write <config|presets|muted> | watch", 2)


if __name__ == "__main__":
    try:
        main(sys.argv)
    except KeyboardInterrupt:
        sys.exit(130)
    except BrokenPipeError:
        sys.exit(0)
