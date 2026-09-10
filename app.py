"""YT Channel Scraper — list a channel's videos, pick some, download them."""

import importlib.machinery
import json
import os
import re
import shutil
import socket
import sys
import threading
import time
import urllib.request
import uuid
import webbrowser
import zipfile
from queue import Queue

APP_NAME = "YT Channel Scraper"
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Frozen by PyInstaller, the code and templates sit in a read-only bundle that macOS may
# also relocate on first launch, so nothing writable can be anchored to BASE_DIR.
FROZEN = getattr(sys, "frozen", False)
BUNDLE_DIR = getattr(sys, "_MEIPASS", BASE_DIR)
SUPPORT_DIR = os.path.expanduser(f"~/Library/Application Support/{APP_NAME}")

# Where an in-app yt-dlp upgrade unpacks to. YouTube breaks yt-dlp every few weeks, so a
# version fixed at build time quietly ages out of working and has to be replaceable.
LIB_DIR = os.path.join(SUPPORT_DIR, "lib")


class _OverlayFinder:
    """Load yt-dlp from LIB_DIR in preference to the copy frozen into the bundle.

    Putting LIB_DIR on sys.path is not enough: PyInstaller's importer lives in
    sys.meta_path, which is consulted before any sys.path entry, so the frozen copy would
    always win and an upgrade would appear to work while changing nothing. A finder ahead
    of it in sys.meta_path is what actually takes precedence.

    It has to claim every yt_dlp.* name, not just the top-level package — otherwise the
    frozen importer keeps answering for submodules and the process ends up running an
    upgraded __init__ against build-time internals.
    """

    def find_spec(self, fullname, path=None, target=None):
        if fullname.split(".")[0] != "yt_dlp":
            return None
        return importlib.machinery.PathFinder.find_spec(
            fullname, path if path is not None else [LIB_DIR], target
        )


_overlay = None
if FROZEN:
    os.makedirs(LIB_DIR, exist_ok=True)
    if os.path.isdir(os.path.join(LIB_DIR, "yt_dlp")):
        _overlay = _OverlayFinder()
        sys.meta_path.insert(0, _overlay)

from flask import Flask, jsonify, make_response, render_template, request, send_from_directory

try:
    from yt_dlp import YoutubeDL
    from yt_dlp.version import __version__ as YTDLP_VERSION
except Exception:
    # A half-written or incompatible upgrade would otherwise brick the app on launch with
    # no way back in to fix it. Drop the overlay and fall back to the shipped copy.
    if _overlay is None:
        raise
    sys.meta_path.remove(_overlay)
    _overlay = None
    for _mod in [m for m in sys.modules if m.split(".")[0] == "yt_dlp"]:
        del sys.modules[_mod]
    from yt_dlp import YoutubeDL
    from yt_dlp.version import __version__ as YTDLP_VERSION

# A source checkout keeps its downloads beside the code; the bundle cannot write there.
DOWNLOAD_DIR = os.environ.get("YTCS_DOWNLOAD_DIR") or (
    os.path.expanduser(f"~/Downloads/{APP_NAME}") if FROZEN
    else os.path.join(BASE_DIR, "downloads")
)
os.makedirs(DOWNLOAD_DIR, exist_ok=True)


def _vendored_ffmpeg():
    """The bundled static ffmpeg, or None to fall through to whatever is on PATH.

    ffmpeg both merges the separate video and audio streams and does the mp3 conversion,
    so a missing binary fails every download at the very last step.
    """
    vendor = os.path.join(BUNDLE_DIR, "vendor")
    if not os.path.isfile(os.path.join(vendor, "ffmpeg")):
        return None
    for name in ("ffmpeg", "ffprobe"):
        path = os.path.join(vendor, name)
        if os.path.isfile(path) and not os.access(path, os.X_OK):
            os.chmod(path, 0o755)  # PyInstaller drops the exec bit on data files
    return vendor


FFMPEG_DIR = _vendored_ffmpeg()


def _vendored_jsruntime():
    """Put the bundled Deno on PATH and report whether it is there.

    YouTube serves media URLs behind a JavaScript "n challenge"; yt-dlp solves it by
    shelling out to a JS runtime, and without one every format above 360p 403s. yt-dlp
    resolves the runtime by bare name through PATH, and an app launched from Finder
    inherits a minimal PATH that has no Homebrew in it — so pointing PATH at vendor/ is
    what makes the bundled copy findable at all.
    """
    vendor = os.path.join(BUNDLE_DIR, "vendor")
    deno = os.path.join(vendor, "deno")
    if not os.path.isfile(deno):
        return False
    if not os.access(deno, os.X_OK):
        os.chmod(deno, 0o755)  # PyInstaller drops the exec bit on data files
    os.environ["PATH"] = vendor + os.pathsep + os.environ.get("PATH", "")
    return True


HAS_JSRUNTIME = _vendored_jsruntime()

# The solver script itself is fetched from GitHub on first use and cached by yt-dlp; it
# is versioned against the player, so it cannot be frozen in at build time.
REMOTE_COMPONENTS = ["ejs:github"] if HAS_JSRUNTIME else []

# Anything above 360p also needs a signed-in session. Chrome is tried first, then the
# other browsers people actually use; whichever yields cookies wins.
COOKIE_BROWSERS = ("chrome", "brave", "edge", "firefox", "safari")

app = Flask(__name__, template_folder=os.path.join(BUNDLE_DIR, "templates"))
# Debug is off, which would otherwise let Jinja serve a template it compiled at boot —
# so an edit to index.html only showed up after a restart.
app.config["TEMPLATES_AUTO_RELOAD"] = True

# job_id -> {"video_id", "title", "status", "percent", "speed", "eta", "file", "error"}
JOBS = {}
JOBS_LOCK = threading.Lock()
CANCELLED = set()   # job ids the user removed; the worker aborts them mid-download
QUEUE = Queue()

# One scrape at a time; a new one supersedes whatever was running.
SCRAPE = {
    "id": None, "status": "idle", "videos": [], "error": None, "channel": "", "url": "",
    "target": 0, "resume": threading.Event(),
}
SCRAPE_LOCK = threading.Lock()

# Videos per page. The worker pauses at each boundary and keeps its position, so a
# 5,000-video channel finishes a page in seconds instead of grinding through the lot.
PAGE_SIZE = 25
PAUSE_TIMEOUT = 900  # give up holding the thread if nobody asks for more

FORMATS = {
    "best": "bestvideo[height<=?2160]+bestaudio/best",
    "1080": "bestvideo[height<=?1080]+bestaudio/best[height<=?1080]",
    "720": "bestvideo[height<=?720]+bestaudio/best[height<=?720]",
    "480": "bestvideo[height<=?480]+bestaudio/best[height<=?480]",
    "audio": "bestaudio/best",
}

# What the dropdown offers -> the channel tab(s) that hold it, in order of preference.
# Music lives under /releases on artist channels but under /playlists on many others.
TABS = {
    "videos": ["videos"],
    "shorts": ["shorts"],
    "live": ["streams"],
    "music": ["releases", "playlists"],
}
TAB_LABELS = {"videos": "Videos", "shorts": "Shorts", "live": "Live", "music": "Music"}

TAB_RE = re.compile(r"/(videos|shorts|streams|releases|playlists|podcasts|featured)/?$")


def normalize_channel_url(url, tab):
    """Point a bare channel URL at the requested tab; leave playlists alone."""
    url = url.strip()
    if not url:
        raise ValueError("No URL provided")
    if not url.startswith("http"):
        url = "https://www.youtube.com/" + url.lstrip("/")
    if "list=" in url or "/playlist" in url:
        return url
    url = TAB_RE.sub("", url).rstrip("/")
    return f"{url}/{tab}"


@app.route("/")
def index():
    # The page carries no cache validators, so a browser is free to keep serving the
    # copy it already has — which reads as "the fix didn't work" when the edit is
    # sitting on disk. The build id is the template's mtime: the console prints it,
    # so a page can be checked against `ls -l templates/index.html`.
    tpl = os.path.join(app.template_folder, "index.html")
    resp = make_response(render_template("index.html", build=int(os.path.getmtime(tpl))))
    resp.headers["Cache-Control"] = "no-store, must-revalidate"
    return resp


@app.post("/api/scrape")
def scrape():
    """Kick off a scrape in the background; results stream out via /api/scrape/status."""
    data = request.get_json(force=True)
    tab_key = data.get("tab", "videos")
    if tab_key not in TABS:
        tab_key = "videos"
    try:
        targets = []
        for tab in TABS[tab_key]:
            url = normalize_channel_url(data.get("url", ""), tab)
            if url not in targets:
                targets.append(url)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    target = targets[0]

    limit = int(data.get("limit") or 0)
    scrape_id = uuid.uuid4().hex[:12]
    with SCRAPE_LOCK:
        SCRAPE.update(
            id=scrape_id, status="running", videos=[], error=None, channel="", url=target,
            target=(min(limit, PAGE_SIZE) if limit else PAGE_SIZE), resume=threading.Event(),
        )
    threading.Thread(
        target=_scrape_worker, args=(scrape_id, targets, tab_key, limit), daemon=True
    ).start()
    return jsonify({"scrape_id": scrape_id, "url": target})


@app.get("/api/scrape/status")
def scrape_status():
    """Return videos found since index `since`, plus whether the scrape is still going."""
    since = max(0, int(request.args.get("since", 0)))
    with SCRAPE_LOCK:
        return jsonify(
            {
                "id": SCRAPE["id"],
                "status": SCRAPE["status"],
                "error": SCRAPE["error"],
                "channel": SCRAPE["channel"],
                "total": len(SCRAPE["videos"]),
                "videos": SCRAPE["videos"][since:],
            }
        )


@app.post("/api/scrape/stop")
def scrape_stop():
    with SCRAPE_LOCK:
        if SCRAPE["status"] in ("running", "paused"):
            SCRAPE["status"] = "stopping"
        resume = SCRAPE["resume"]
    resume.set()  # wake a paused worker so it can exit
    return jsonify({"ok": True})


@app.post("/api/scrape/more")
def scrape_more():
    """Let a paused scrape run on for another page, continuing where it left off."""
    with SCRAPE_LOCK:
        if SCRAPE["status"] != "paused":
            return jsonify({"error": "Nothing paused to continue"}), 400
        SCRAPE["target"] = len(SCRAPE["videos"]) + PAGE_SIZE
        SCRAPE["status"] = "running"
        resume = SCRAPE["resume"]
    resume.set()
    return jsonify({"ok": True})


def _as_video(entry):
    if not entry or not entry.get("id"):
        return None
    vid = entry["id"]
    return {
        "id": vid,
        "title": entry.get("title") or vid,
        "duration": entry.get("duration"),
        "views": entry.get("view_count"),
        "url": entry.get("url") or f"https://www.youtube.com/watch?v={vid}",
        "thumbnail": f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg",
    }


def _iter_videos(ydl, entries, depth=0):
    """Flatten a channel tab into video entries.

    Most tabs list videos directly (ie_key "Youtube"), but the Music tab lists albums
    (ie_key "YoutubeTab") whose tracks only appear once the album itself is opened, so
    nested playlists get expanded — depth-capped, since these cost a request each.
    """
    for entry in entries or []:
        if not entry:
            continue
        if entry.get("ie_key") == "YoutubeTab" or entry.get("_type") == "playlist":
            if depth >= 2:
                continue
            nested = entry.get("entries")
            if nested is None:
                try:
                    sub = ydl.extract_info(
                        entry.get("url") or entry.get("id"), download=False, process=False
                    )
                except Exception:
                    continue
                nested = (sub or {}).get("entries")
            yield from _iter_videos(ydl, nested, depth + 1)
        else:
            yield entry


def _scrape_worker(scrape_id, targets, tab_key, limit):
    opts = {
        "extract_flat": "in_playlist",
        "skip_download": True,
        "quiet": True,
        "no_warnings": True,
        "ignoreerrors": True,
    }

    def still_mine():
        """False once this scrape is superseded or the user hit Stop."""
        with SCRAPE_LOCK:
            return SCRAPE["id"] == scrape_id and SCRAPE["status"] == "running"

    try:
        with YoutubeDL(opts) as ydl:
            # process=False keeps `entries` a lazy generator: pages arrive as they load
            # instead of after the whole channel has been walked.
            # Try each candidate tab in turn; yt-dlp returns None for a tab the
            # channel doesn't have (ignoreerrors swallows the 404).
            info = None
            for candidate in targets:
                try:
                    info = ydl.extract_info(candidate, download=False, process=False)
                except Exception:
                    info = None
                if info:
                    break
            if not info:
                label = TAB_LABELS.get(tab_key, tab_key)
                raise ValueError(
                    f"No {label} found for that channel — it may not have a {label} tab. "
                    f"Check the URL, or try a different type."
                )
            with SCRAPE_LOCK:
                if SCRAPE["id"] == scrape_id:
                    SCRAPE["channel"] = info.get("channel") or info.get("title") or ""

            count = 0
            for item in _iter_videos(ydl, info.get("entries")):
                if not still_mine():
                    break
                video = _as_video(item)
                if not video:
                    continue
                with SCRAPE_LOCK:
                    if SCRAPE["id"] != scrape_id:
                        return
                    SCRAPE["videos"].append(video)
                count += 1
                if limit and count >= limit:
                    break

                # Page boundary: park here, holding the generator's position, until
                # someone asks for more.
                with SCRAPE_LOCK:
                    at_boundary = SCRAPE["id"] == scrape_id and count >= SCRAPE["target"]
                    if at_boundary:
                        SCRAPE["status"] = "paused"
                        resume = SCRAPE["resume"]
                        resume.clear()
                if at_boundary:
                    if not resume.wait(timeout=PAUSE_TIMEOUT):
                        return
                    if not still_mine():
                        return

    except ValueError as exc:  # our own, already user-facing
        with SCRAPE_LOCK:
            if SCRAPE["id"] == scrape_id:
                SCRAPE.update(status="error", error=str(exc))
        return
    except Exception as exc:  # yt-dlp raises a wide range of errors
        with SCRAPE_LOCK:
            if SCRAPE["id"] == scrape_id:
                SCRAPE.update(status="error", error=f"Could not read that channel: {exc}")
        return

    with SCRAPE_LOCK:
        if SCRAPE["id"] == scrape_id:
            SCRAPE["status"] = "stopped" if SCRAPE["status"] == "stopping" else "done"


@app.post("/api/download")
def download():
    data = request.get_json(force=True)
    videos = data.get("videos") or []
    fmt = FORMATS.get(data.get("quality", "1080"), FORMATS["1080"])
    audio_only = data.get("quality") == "audio"
    if not videos:
        return jsonify({"error": "No videos selected"}), 400

    created = []
    with JOBS_LOCK:
        for v in videos:
            job_id = uuid.uuid4().hex[:12]
            JOBS[job_id] = {
                "id": job_id,
                "video_id": v.get("id"),
                "title": v.get("title") or v.get("id"),
                "status": "queued",
                "percent": 0,
                "speed": None,
                "eta": None,
                "file": None,
                "error": None,
            }
            created.append(job_id)
            QUEUE.put((job_id, v.get("id"), fmt, audio_only))

    return jsonify({"jobs": created})


@app.get("/api/status")
def status():
    with JOBS_LOCK:
        return jsonify({"jobs": list(JOBS.values())})


@app.delete("/api/jobs/<job_id>")
def delete_job(job_id):
    """Remove a single job. If it's still running, the worker aborts it."""
    with JOBS_LOCK:
        if job_id not in JOBS:
            return jsonify({"error": "No such job"}), 404
        unfinished = JOBS[job_id]["status"] not in ("done", "error")
        del JOBS[job_id]
        if unfinished:
            CANCELLED.add(job_id)
    return jsonify({"ok": True})


@app.post("/api/clear")
def clear():
    """Drop finished/failed jobs from the list (running ones stay)."""
    with JOBS_LOCK:
        for job_id in [k for k, j in JOBS.items() if j["status"] in ("done", "error")]:
            del JOBS[job_id]
    return jsonify({"ok": True})


@app.get("/downloads/<path:name>")
def serve_download(name):
    return send_from_directory(DOWNLOAD_DIR, name, as_attachment=True)


@app.get("/api/health")
def health():
    """Lets a second launch recognise a server of ours that is already up."""
    return jsonify({"app": APP_NAME, "ytdlp": YTDLP_VERSION})


@app.post("/api/quit")
def quit_app():
    """The bundled app has no window of its own, so the page is what shuts it down."""
    def bye():
        time.sleep(0.4)  # let this response reach the browser first
        os._exit(0)

    threading.Thread(target=bye, daemon=True).start()
    return jsonify({"ok": True})


# --- keeping yt-dlp current ----------------------------------------------------------
# yt-dlp is pure Python, so an upgrade is just its PyPI wheel unzipped into LIB_DIR —
# no pip, no compiler, and the bundled copy stays in place as a fallback. The running
# process imported the old module at boot, so a swap only takes effect on next launch.
PYPI_URL = "https://pypi.org/pypi/yt-dlp/json"
PENDING_FILE = os.path.join(SUPPORT_DIR, "pending.json")
UPGRADE_LOCK = threading.Lock()


def _version_tuple(v):
    """yt-dlp versions are dates (2026.7.4), so a plain numeric compare orders them."""
    return tuple(int(c) if c.isdigit() else 0 for c in re.split(r"[.\-+]", v))


def _pending_version():
    """A version the updater unpacked that this process is not running yet.

    Compared numerically, not as strings: PyPI publishes 2026.7.4 while the package's own
    __version__ zero-pads it to 2026.07.04, so a string compare reads the version we are
    already running as still pending and the UI asks for a restart forever.
    """
    try:
        with open(PENDING_FILE) as fh:
            version = json.load(fh).get("version")
        if version and _version_tuple(version) > _version_tuple(YTDLP_VERSION):
            return version
    except Exception:
        pass
    return None


def _latest_version():
    with urllib.request.urlopen(PYPI_URL, timeout=20) as resp:
        return json.load(resp)


@app.get("/api/ytdlp")
def ytdlp_info():
    """What we are running, and — with ?check=1 — what PyPI has."""
    info = {
        "current": YTDLP_VERSION,
        "pending": _pending_version(),
        "can_upgrade": FROZEN,
    }
    if not request.args.get("check"):
        return jsonify(info)
    try:
        info["latest"] = _latest_version()["info"]["version"]
    except Exception as exc:
        return jsonify({**info, "error": f"Could not reach PyPI: {exc}"[:200]}), 502
    # An already-unpacked upgrade counts as installed, so checking twice does not offer
    # the same version again while the restart is still pending.
    info["outdated"] = _version_tuple(info["latest"]) > _version_tuple(
        info["pending"] or info["current"]
    )
    return jsonify(info)


@app.post("/api/ytdlp/upgrade")
def ytdlp_upgrade():
    if not FROZEN:
        return jsonify({"error": "Running from source — use pip install -U yt-dlp"}), 400
    if not UPGRADE_LOCK.acquire(blocking=False):
        return jsonify({"error": "An upgrade is already running"}), 409
    staging = os.path.join(SUPPORT_DIR, "lib.incoming")
    try:
        data = _latest_version()
        version = data["info"]["version"]
        wheel = next((u for u in data["urls"] if u["filename"].endswith(".whl")), None)
        if not wheel:
            return jsonify({"error": f"yt-dlp {version} has no wheel on PyPI"}), 502

        shutil.rmtree(staging, ignore_errors=True)
        os.makedirs(staging, exist_ok=True)
        archive = os.path.join(staging, wheel["filename"])
        urllib.request.urlretrieve(wheel["url"], archive)
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(staging)
        os.remove(archive)
        if not os.path.isdir(os.path.join(staging, "yt_dlp")):
            return jsonify({"error": "Downloaded wheel contained no yt_dlp package"}), 502

        # Only swap once the unpack has fully succeeded, so a failed download can never
        # leave LIB_DIR holding a partial package that then fails to import.
        retired = os.path.join(SUPPORT_DIR, "lib.old")
        shutil.rmtree(retired, ignore_errors=True)
        if os.path.isdir(LIB_DIR):
            os.rename(LIB_DIR, retired)
        os.rename(staging, LIB_DIR)
        shutil.rmtree(retired, ignore_errors=True)

        with open(PENDING_FILE, "w") as fh:
            json.dump({"version": version}, fh)
        return jsonify({
            "ok": True,
            "version": version,
            "restart_required": _version_tuple(version) != _version_tuple(YTDLP_VERSION),
        })
    except Exception as exc:
        shutil.rmtree(staging, ignore_errors=True)
        return jsonify({"error": str(exc)[:300]}), 500
    finally:
        UPGRADE_LOCK.release()


def _update(job_id, **fields):
    with JOBS_LOCK:
        if job_id in JOBS:
            JOBS[job_id].update(fields)


def _worker():
    while True:
        job_id, video_id, fmt, audio_only = QUEUE.get()

        # A merged download runs two passes (video stream, then audio), each reporting
        # 0-100% of its own file. Summing bytes against the combined expected size keeps
        # the ring filling once. `expected` is filled in from a probe extraction below.
        expected = {"total": 0}
        got = {}

        def hook(d, job_id=job_id):
            with JOBS_LOCK:
                if job_id in CANCELLED:
                    raise RuntimeError("cancelled")
            name = d.get("filename") or ""
            if d["status"] == "downloading":
                got[name] = d.get("downloaded_bytes", 0)
                total = expected["total"] or d.get("total_bytes") or d.get("total_bytes_estimate")
                pct = (sum(got.values()) / total * 100) if total else 0
                _update(
                    job_id,
                    status="downloading",
                    percent=round(min(pct, 100), 1),
                    speed=d.get("speed"),
                    eta=d.get("eta"),
                )
            elif d["status"] == "finished":
                got[name] = d.get("total_bytes") or got.get(name, 0)
                total = expected["total"]
                # Only the last stream landing means the file is really done; earlier
                # ones just hand over to the next pass.
                if not total or sum(got.values()) >= total * 0.995:
                    _update(job_id, status="processing", percent=100)

        base_opts = {
            "format": fmt,
            "outtmpl": os.path.join(DOWNLOAD_DIR, "%(title).150B [%(id)s].%(ext)s"),
            "progress_hooks": [hook],
            "quiet": True,
            "no_warnings": True,
            "noprogress": True,
            "restrictfilenames": True,
            "retries": 5,
            "fragment_retries": 5,
            "extractor_retries": 3,
        }
        if FFMPEG_DIR:
            base_opts["ffmpeg_location"] = FFMPEG_DIR
        if audio_only:
            base_opts["postprocessors"] = [
                {"key": "FFmpegExtractAudio", "preferredcodec": "mp3", "preferredquality": "192"}
            ]
        else:
            base_opts["merge_output_format"] = "mp4"

        # A plain extraction now 403s on every format above 360p: YouTube gates those
        # behind both a solved JS challenge and a signed-in session. Retrying identical
        # options cannot clear either, so the attempts step down in capability instead:
        #
        #   1. cookies + JS challenge solver  -> full requested quality
        #   2. no cookies, solver only        -> works when the video is not gated
        #   3. android client                 -> no auth and no challenge, but 360p only
        #
        # The last rung always downloads something, which beats erroring out entirely.
        attempts = []
        if HAS_JSRUNTIME:
            for browser in COOKIE_BROWSERS:
                attempts.append(
                    ("cookies", {"remote_components": REMOTE_COMPONENTS,
                                 "cookiesfrombrowser": (browser, None, None, None)})
                )
            attempts.append(("solver", {"remote_components": REMOTE_COMPONENTS}))
        attempts.append(
            ("android", {"extractor_args": {"youtube": {"player_client": ["android"]}}})
        )

        url = f"https://www.youtube.com/watch?v={video_id}"
        _update(job_id, status="downloading")
        last_error = None
        for attempt, (rung, extra) in enumerate(attempts, 1):
            opts = {**base_opts, **extra}
            try:
                # Probe first purely to learn the combined size of the streams that will
                # be fetched; without it the first stream alone would read as 100%.
                try:
                    with YoutubeDL({**opts, "progress_hooks": [], "skip_download": True}) as probe:
                        pinfo = probe.extract_info(url, download=False)
                    streams = (pinfo or {}).get("requested_formats") or [pinfo or {}]
                    expected["total"] = sum(
                        f.get("filesize") or f.get("filesize_approx") or 0 for f in streams
                    )
                except Exception:
                    expected["total"] = 0  # fall back to per-stream totals
                got.clear()

                with YoutubeDL(opts) as ydl:
                    info = ydl.extract_info(url)
                    path = info.get("requested_downloads", [{}])[0].get("filepath")
                    if audio_only and path:
                        path = os.path.splitext(path)[0] + ".mp3"
                _update(
                    job_id,
                    status="done",
                    percent=100,
                    error=None,
                    file=os.path.basename(path) if path else None,
                )
                last_error = None
                break
            except Exception as exc:
                with JOBS_LOCK:
                    if job_id in CANCELLED:
                        CANCELLED.discard(job_id)
                        last_error = None
                        break
                last_error = str(exc)[:300]
                if attempt < len(attempts):
                    _update(job_id, status="retrying", percent=0, error=last_error)
                    # A browser with no YouTube cookies fails instantly and costs nothing;
                    # only back off once a rung has actually talked to YouTube.
                    if rung != "cookies":
                        time.sleep(2)

        if last_error:
            _update(job_id, status="error", error=last_error)
        QUEUE.task_done()


for _ in range(int(os.environ.get("WORKERS", "3"))):
    threading.Thread(target=_worker, daemon=True).start()


PORT_FILE = os.path.join(SUPPORT_DIR, "port")


def _free_port():
    """A hardcoded port collides with a leftover copy of ourselves or an unrelated app."""
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _already_serving():
    """The port of a copy of this app that is already running, if there is one."""
    try:
        with open(PORT_FILE) as fh:
            port = int(fh.read().strip())
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=1) as resp:
            if json.load(resp).get("app") == APP_NAME:
                return port
    except Exception:
        pass
    return None


if __name__ == "__main__":
    # Opening the app from Finder a second time should surface the tab it already has,
    # not stand up a rival server with its own separate job list.
    if FROZEN and (running := _already_serving()):
        webbrowser.open(f"http://127.0.0.1:{running}/")
        sys.exit(0)

    port = int(os.environ.get("PORT", 0)) or (_free_port() if FROZEN else 5005)
    os.makedirs(SUPPORT_DIR, exist_ok=True)
    with open(PORT_FILE, "w") as fh:
        fh.write(str(port))

    pending = _pending_version()
    print(f"\n  {APP_NAME} -> http://127.0.0.1:{port}")
    print(f"  Saving to {DOWNLOAD_DIR}")
    print(f"  yt-dlp {YTDLP_VERSION}" + (f" (restart to load {pending})" if pending else ""))
    print()
    if FROZEN:
        # There is no terminal to read the URL from, so the browser has to be handed it.
        threading.Timer(0.7, webbrowser.open, args=(f"http://127.0.0.1:{port}/",)).start()
    app.run(host="127.0.0.1", port=port, debug=False, threaded=True)
