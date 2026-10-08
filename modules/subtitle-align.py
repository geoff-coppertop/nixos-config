import bisect
import hashlib
import json
import os
import re
import shutil
import statistics
import struct
import subprocess
import sys

TOL = 0.35
SPLIT = 8
RANGE = 600
VIDEO_EXT = (".mkv", ".mp4", ".m4v", ".avi", ".mov", ".ts")
TEXT_CODECS = ("subrip", "ass", "ssa", "mov_text", "webvtt", "text")
NAME = re.compile(r"(.+?)\.([A-Za-z]{2,3})(?:\.(?:forced|sdh|cc|hi|default))*\.srt")
CUE = re.compile(r"(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)(.*)")


def secs(h, m, s, f):
    return int(h) * 3600 + int(m) * 60 + int(s) + float("0." + f)


def stamp(t):
    t = max(t, 0.0)
    ms = int(round(t * 1000))
    return "%02d:%02d:%02d,%03d" % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


def srt_cues(text):
    out = []
    for line in text.splitlines():
        m = CUE.fullmatch(line.strip())
        if m:
            g = m.groups()
            out.append(secs(*g[0:4]))
    return out


def sup_starts(data):
    out = []
    i = 0
    while i + 13 <= len(data):
        kind = data[i + 10]
        pts = struct.unpack(">I", data[i + 2:i + 6])[0]
        size = struct.unpack(">H", data[i + 11:i + 13])[0]
        body = data[i + 13:i + 13 + size]
        if kind == 0x16 and len(body) >= 11 and body[10] > 0:
            out.append(pts / 90000)
        i += 13 + size
    return sorted(out)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, stdin=subprocess.DEVNULL, check=True).stdout


def reference(video):
    info = json.loads(run(["ffprobe", "-v", "error", "-select_streams", "s", "-show_entries", "stream=index,codec_name:stream_tags=language", "-of", "json", video]))
    for s in info.get("streams", []):
        if s.get("tags", {}).get("language") not in ("eng", "en"):
            continue
        idx, codec = str(s["index"]), s.get("codec_name")
        if codec == "hdmv_pgs_subtitle":
            return sup_starts(run(["ffmpeg", "-nostdin", "-v", "error", "-i", video, "-map", "0:" + idx, "-c", "copy", "-f", "sup", "-"]))
        if codec in TEXT_CODECS:
            return sorted(srt_cues(run(["ffmpeg", "-nostdin", "-v", "error", "-i", video, "-map", "0:" + idx, "-f", "srt", "-"]).decode("utf-8", "replace")))
        pts = run(["ffprobe", "-v", "error", "-select_streams", idx, "-show_entries", "packet=pts_time", "-of", "csv=p=0", video]).decode().split()
        return sorted(float(p) for p in pts if re.fullmatch(r"-?[0-9.]+", p))
    return None


def nearest(ref, y):
    j = bisect.bisect_left(ref, y)
    return min((ref[k] for k in (j - 1, j) if 0 <= k < len(ref)), key=lambda r: abs(r - y), default=None)


def offsets(ref, starts):
    steps = range(-RANGE, RANGE + 1)
    cost = []
    for x in starts:
        row = []
        for o in steps:
            r = nearest(ref, x - o / 10)
            row.append(0 if r is not None and abs(r - (x - o / 10)) <= TOL else 1)
        cost.append(row)
    best = list(cost[0])
    back = []
    for i in range(1, len(starts)):
        low = min(best)
        arg = best.index(low)
        new, ptr = [], []
        for s, stay in enumerate(best):
            if stay <= low + SPLIT:
                new.append(stay + cost[i][s])
                ptr.append(s)
            else:
                new.append(low + SPLIT + cost[i][s])
                ptr.append(arg)
        best = new
        back.append(ptr)
    s = best.index(min(best))
    path = [s]
    for ptr in reversed(back):
        s = ptr[s]
        path.append(s)
    path.reverse()
    coarse = [(p - RANGE) / 10 for p in path]
    fine = list(coarse)
    i = 0
    while i < len(coarse):
        j = i
        while j < len(coarse) and coarse[j] == coarse[i]:
            j += 1
        d = []
        for k in range(i, j):
            r = nearest(ref, starts[k] - coarse[k])
            if r is not None and abs(r - (starts[k] - coarse[k])) <= TOL:
                d.append(starts[k] - r)
        if len(d) >= 3:
            for k in range(i, j):
                fine[k] = statistics.median(d)
        i = j
    return fine


def matched(ref, starts, offs):
    n = 0
    for x, o in zip(starts, offs):
        r = nearest(ref, x - o)
        if r is not None and abs(r - (x - o)) <= TOL:
            n += 1
    return n / len(starts)


def rewrite(text, offs):
    k = 0
    out = []
    for line in text.splitlines(keepends=True):
        body = line.rstrip("\r\n")
        m = CUE.fullmatch(body.strip())
        if m and k < len(offs):
            g = m.groups()
            a = secs(*g[0:4]) - offs[k]
            b = secs(*g[4:8]) - offs[k]
            out.append("%s --> %s%s%s" % (stamp(a), stamp(b), g[8], line[len(body):]))
            k += 1
        else:
            out.append(line)
    return "".join(out)


def decode(raw):
    for enc in ("utf-8", "cp1252"):
        try:
            return raw.decode(enc), enc
        except UnicodeDecodeError:
            pass
    return raw.decode("latin-1"), "latin-1"


def process(path, video, refs):
    if video not in refs:
        refs[video] = reference(video)
    ref = refs[video]
    raw = open(path, "rb").read()
    if not ref:
        print("%s: no embedded English subtitle to align against" % path)
        return raw
    text, enc = decode(raw)
    starts = srt_cues(text)
    if len(starts) < 20:
        print("%s: too few cues to align" % path)
        return raw
    before = matched(ref, starts, [0.0] * len(starts))
    offs = offsets(ref, starts)
    after = matched(ref, starts, offs)
    if before >= 0.9 or after < 0.5 or after < before + 0.1:
        print("%s: left as is (matched %.0f%% before, %.0f%% after)" % (path, before * 100, after * 100))
        return raw
    print("%s: aligned (matched %.0f%% before, %.0f%% after, offsets %+.1f..%+.1f s)" % (path, before * 100, after * 100, min(offs), max(offs)))
    return rewrite(text, offs).encode(enc)


def segments(starts, offs):
    out, last = [], None
    for x, o in zip(starts, offs):
        if last is None or abs(o - last) > 0.25:
            out.append("@%dm%+.1fs" % (x // 60, o))
            last = o
    return out


def library(tops):
    for top in tops:
        for root, _, files in os.walk(top):
            for name in sorted(files):
                m = NAME.fullmatch(name)
                if not m:
                    continue
                video = next((os.path.join(root, m.group(1) + e) for e in VIDEO_EXT if os.path.exists(os.path.join(root, m.group(1) + e))), None)
                yield os.path.join(root, name), video


def dry_run(tops):
    refs = {}
    for path, video in library(tops):
        label = os.path.basename(path)[:44]
        if video is None:
            print("%-46s no video next to it" % label)
            continue
        try:
            if video not in refs:
                refs[video] = reference(video)
            ref = refs[video]
            if not ref:
                print("%-46s NO embedded English subtitle: would be skipped" % label)
                continue
            text, _ = decode(open(path, "rb").read())
            starts = srt_cues(text)
            if len(starts) < 20:
                print("%-46s too few cues" % label)
                continue
            before = matched(ref, starts, [0.0] * len(starts))
            offs = offsets(ref, starts)
            after = matched(ref, starts, offs)
            verdict = "LEAVE" if (before >= 0.9 or after < 0.5 or after < before + 0.1) else "ALIGN"
            print("%-46s ref=%d cues=%d matched %.0f%% -> %.0f%%  %s  %s" % (label, len(ref), len(starts), before * 100, after * 100, verdict, " ".join(segments(starts, offs)[:8])))
        except Exception as e:
            print("%-46s failed: %r" % (label, e))


def main():
    if sys.argv[1] == "--dry-run":
        dry_run(sys.argv[2:])
        return
    conf = json.load(open(sys.argv[1]))
    state_path = os.path.join(os.environ["STATE_DIRECTORY"], "state.json")
    state = json.load(open(state_path)) if os.path.exists(state_path) else {}
    refs = {}
    for path, video in library(conf["mediaDirs"]):
        digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
        if state.get(path) == digest or video is None:
            continue
        try:
            new = process(path, video, refs)
        except Exception as e:
            print("%s: failed: %r" % (path, e), file=sys.stderr)
            continue
        if new != open(path, "rb").read():
            if not os.path.exists(path + ".orig"):
                shutil.copyfile(path, path + ".orig")
            tmp = path + ".tmp"
            open(tmp, "wb").write(new)
            os.chmod(tmp, os.stat(path).st_mode & 0o7777)
            os.replace(tmp, path)
        state[path] = hashlib.sha256(new).hexdigest()
    json.dump(state, open(state_path, "w"))


main()
