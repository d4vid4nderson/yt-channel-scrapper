#!/usr/bin/env python3
"""Check Renderers.swift's assumptions against live InnerTube responses.

Renderers.swift reads YouTube's private API, whose response shapes change without
notice — channel tabs moved from `videoRenderer` to `lockupViewModel`, and a search
result keeps the channel handle in a field called `subscriberCountText`. When a listing
comes back empty or a subscriber count goes missing, run this: it performs the same
calls the app makes and checks the same fields, so it says in a few seconds whether the
shapes still hold.

It mirrors the Swift rather than importing it, so a change made here is not a change
made in the app — port anything you fix back into Sources/Engine/Renderers.swift.

    ./check-renderers.py                     # the default channel
    ./check-renderers.py --channel @LofiGirl # somebody else

Needs network. Note that YouTube gates the *player* endpoint far harder than these
listing endpoints, so this passing does not mean stream resolution works — that is a
separate question, and ios/README.md covers it.
"""
import json, re, urllib.request

UA=("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36")
CTX={"client":{"clientName":"WEB","clientVersion":"2.20250312.04.00","hl":"en","gl":"US"}}

def post(ep,p):
    req=urllib.request.Request(f"https://www.youtube.com/youtubei/v1/{ep}",
      data=json.dumps({"context":CTX}|p).encode(),
      headers={"Content-Type":"application/json","User-Agent":UA,"X-YouTube-Client-Name":"1",
               "X-YouTube-Client-Version":"2.20250312.04.00","Origin":"https://www.youtube.com",
               "Referer":"https://www.youtube.com/"})
    return json.load(urllib.request.urlopen(req,timeout=30))

# --- tree walking ---------------------------------------------------------------
def find_all(key, node, out=None):
    out=[] if out is None else out
    if isinstance(node,dict):
        if key in node and isinstance(node[key],dict): out.append(node[key])
        for v in node.values(): find_all(key,v,out)
    elif isinstance(node,list):
        for v in node: find_all(key,v,out)
    return out

def find_first(key, node):
    if isinstance(node,dict):
        if key in node: return node[key]
        for v in node.values():
            r=find_first(key,v)
            if r is not None: return r
    elif isinstance(node,list):
        for v in node:
            r=find_first(key,v)
            if r is not None: return r
    return None

def text(node):
    """The four ways InnerTube writes a string, all live in one response today."""
    if isinstance(node,str): return node or None
    if not isinstance(node,dict): return None
    if node.get("simpleText"): return node["simpleText"]
    if isinstance(node.get("content"),str) and node["content"]: return node["content"]
    if isinstance(node.get("runs"),list):
        j="".join(r.get("text","") for r in node["runs"])
        return j or None
    # {"text": {"content": ...}} — the viewModel wrapper
    if isinstance(node.get("text"),(dict,str)): return text(node["text"])
    return None

def count(display):
    if not display: return None
    low=display.lower()
    if low.startswith("no "): return 0
    m=re.search(r'([\d.,]+)\s*([kmb])?', low)
    if not m: return None
    try: value=float(m.group(1).replace(",",""))
    except ValueError: return None
    mult={"k":1e3,"m":1e6,"b":1e9}.get(m.group(2) or "",1)
    # "4.27 million subscribers" spells the multiplier out.
    if "million" in low: mult=1e6
    elif "billion" in low: mult=1e9
    elif "thousand" in low: mult=1e3
    return int(value*mult)

def seconds(clock):
    if not clock or ":" not in clock: return None
    parts=clock.split(":")
    if not all(p.isdigit() for p in parts) or len(parts)>3: return None
    s=0
    for p in parts: s=s*60+int(p)
    return s

def image(node):
    """Widest of a `thumbnails:[...]` (classic) or `sources:[...]` (viewModel) list."""
    if not isinstance(node,dict): return None
    lst=node.get("thumbnails") or node.get("sources")
    if not isinstance(lst,list) or not lst: return None
    best=max((x for x in lst if x.get("url")), key=lambda x:x.get("width") or 0, default=None)
    if not best: return None
    u=best["url"]
    return ("https:"+u) if u.startswith("//") else u

# --- videos ---------------------------------------------------------------------
CLASSIC_VIDEO=["videoRenderer","gridVideoRenderer","playlistVideoRenderer",
               "reelItemRenderer","compactVideoRenderer"]

def video_from_lockup(lv, channel):
    if lv.get("contentType") not in (None,"LOCKUP_CONTENT_TYPE_VIDEO",
                                     "LOCKUP_CONTENT_TYPE_SHORT"): return None
    vid=lv.get("contentId")
    if not vid: return None
    meta=find_first("lockupMetadataViewModel",lv) or {}
    title=text(meta.get("title")) or vid
    # views / age sit in metadataParts as plain content strings
    views=None
    for row in find_all("contentMetadataViewModel",lv):
        for mr in row.get("metadataRows",[]):
            for part in mr.get("metadataParts",[]):
                t=text(part)
                if t and "view" in t.lower(): views=count(t)
    # duration is a badge on the thumbnail
    dur=None
    for badge in find_all("thumbnailBadgeViewModel",lv):
        d=seconds(badge.get("text"))
        if d: dur=d
    return dict(id=vid,title=title,duration=dur,views=views,
                channelName=(channel or {}).get("title"),
                channelId=(channel or {}).get("id"))

def video_from_classic(r, channel):
    vid=r.get("videoId") or find_first("videoId",r)
    if not vid: return None
    return dict(id=vid,
        title=text(r.get("title")) or text(r.get("headline")) or vid,
        duration=seconds(text(r.get("lengthText"))) or
                 (int(r["lengthSeconds"]) if str(r.get("lengthSeconds","")).isdigit() else None),
        views=count(text(r.get("viewCountText")) or text(r.get("shortViewCountText"))),
        channelName=text(r.get("ownerText")) or text(r.get("longBylineText"))
                    or (channel or {}).get("title"),
        channelId=find_first("browseId",r.get("ownerText") or {}) or (channel or {}).get("id"))

def video_from_shorts_lockup(sl, channel):
    """Shorts are their own shape: no duration, and title/views in an overlay block."""
    vid=find_first("videoId", sl.get("onTap") or {})
    if not vid:
        eid=sl.get("entityId") or ""
        vid=eid.rsplit("-",1)[-1] if eid.startswith("shorts-shelf-item-") else None
    if not vid: return None
    ov=sl.get("overlayMetadata") or {}
    return dict(id=vid,
        title=text(ov.get("primaryText")) or vid,
        duration=None,                       # YouTube gives none for a Short here
        views=count(text(ov.get("secondaryText"))),
        channelName=(channel or {}).get("title"),
        channelId=(channel or {}).get("id"))

def videos(node, channel=None):
    seen,out=set(),[]
    for sl in find_all("shortsLockupViewModel",node):
        v=video_from_shorts_lockup(sl,channel)
        if v and v["id"] not in seen: seen.add(v["id"]); out.append(v)
    for lv in find_all("lockupViewModel",node):
        v=video_from_lockup(lv,channel)
        if v and v["id"] not in seen: seen.add(v["id"]); out.append(v)
    for name in CLASSIC_VIDEO:
        for r in find_all(name,node):
            v=video_from_classic(r,channel)
            if v and v["id"] not in seen: seen.add(v["id"]); out.append(v)
    return out

# --- channels -------------------------------------------------------------------
def channel_from_renderer(r):
    cid=r.get("channelId") or find_first("browseId",r)
    if not isinstance(cid,str) or not cid.startswith("UC"): return None
    # The search renderer puts the HANDLE in subscriberCountText and the SUBSCRIBER
    # COUNT in videoCountText. Verified live — reading them by name gives the handle
    # as the subscriber count and loses the count entirely.
    sub_field=text(r.get("subscriberCountText"))
    vid_field=(find_first("label", r.get("videoCountText") or {})
               or text(r.get("videoCountText")))
    handle=sub_field if (sub_field or "").startswith("@") else None
    subs=count(vid_field) if vid_field and "subscriber" in (vid_field or "").lower() else None
    if subs is None and sub_field and "subscriber" in sub_field.lower():
        subs=count(sub_field)
    if handle is None:
        cb=find_first("canonicalBaseUrl",r)
        if isinstance(cb,str) and cb.lstrip("/").startswith("@"): handle=cb.lstrip("/")
    return dict(id=cid,title=text(r.get("title")) or cid,handle=handle,
                subscribers=subs,avatar=image(r.get("thumbnail")))

def channels(node):
    seen,out=set(),[]
    for name in ("channelRenderer","gridChannelRenderer"):
        for r in find_all(name,node):
            c=channel_from_renderer(r)
            if c and c["id"] not in seen: seen.add(c["id"]); out.append(c)
    for lv in find_all("lockupViewModel",node):
        if lv.get("contentType")!="LOCKUP_CONTENT_TYPE_CHANNEL": continue
        cid=lv.get("contentId")
        if not (isinstance(cid,str) and cid.startswith("UC")) or cid in seen: continue
        meta=find_first("lockupMetadataViewModel",lv) or {}
        seen.add(cid)
        out.append(dict(id=cid,title=text(meta.get("title")) or cid,handle=None,
                        subscribers=None,avatar=image(find_first("image",lv) or {})))
    return out

def details(node):
    meta=find_first("channelMetadataRenderer",node) or {}
    header=find_first("pageHeaderViewModel",node) or find_first("c4TabbedHeaderRenderer",node) or {}
    vanity=meta.get("vanityChannelUrl") or ""
    handle=vanity.rstrip("/").split("/")[-1] if "@" in vanity else None
    subs=None
    for mr in find_all("contentMetadataViewModel",header):
        for row in mr.get("metadataRows",[]):
            for part in row.get("metadataParts",[]):
                t=text(part)
                if t and "subscriber" in t.lower(): subs=count(t)
    if subs is None: subs=count(text(header.get("subscriberCountText")))
    return dict(avatar=image(meta.get("avatar")) or image(find_first("avatar",header) or {}),
                subscribers=subs,handle=handle,
                title=meta.get("title") or text(header.get("title")))

def continuation(node):
    c=find_first("continuationCommand",node)
    if isinstance(c,dict) and c.get("token"): return c["token"]
    c=find_first("nextContinuationData",node)
    if isinstance(c,dict) and c.get("continuation"): return c["continuation"]
    return None


# --- the check ----------------------------------------------------------------------

TABS = {
    "videos": ["EgZ2aWRlb3PyBgQKAjoA"],
    "shorts": ["EgZzaG9ydHPyBgUKA5oBAA=="],
    "live":   ["EgdzdHJlYW1z8gYECgJ6AA=="],
    "music":  ["EghyZWxlYXNlc/IGBQoDsgEA", "EglwbGF5bGlzdHPyBgQKAkIA"],
}


def report(label, passed, detail=""):
    print(f"  {'ok  ' if passed else 'FAIL'}  {label:<34} {detail}")
    return passed


def main():
    import argparse
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--channel", default="@fireship",
                    help="handle or URL to exercise (default: @fireship)")
    args = ap.parse_args()
    ok = True

    print(f"resolve_url  {args.channel}")
    r = post("navigation/resolve_url", {"url": f"https://www.youtube.com/{args.channel.lstrip('/')}"})
    ids = [b for b in find_all_values(r, "browseId") if isinstance(b, str) and b.startswith("UC")]
    bid = ids[0] if ids else None
    ok &= report("browseId resolved", bool(bid), bid or "")

    if not bid:
        print("\ncannot continue without a browseId")
        return 1

    print("\nbrowse  (Videos tab)")
    r = post("browse", {"browseId": bid, "params": TABS["videos"][0]})
    d = details(r)
    ok &= report("channel title", bool(d["title"]), d["title"] or "")
    ok &= report("channel avatar", bool(d["avatar"]), (d["avatar"] or "")[:46])
    ok &= report("subscriber count", bool(d["subscribers"]), str(d["subscribers"]))
    ok &= report("handle", bool(d["handle"]), d["handle"] or "")

    ch = dict(id=bid, title=d["title"])
    vs = videos(r, ch)
    ok &= report("videos parsed", len(vs) >= 10, f"{len(vs)} items")
    if vs:
        titled = sum(1 for v in vs if v["title"] and v["title"] != v["id"])
        viewed = sum(1 for v in vs if v["views"])
        timed = sum(1 for v in vs if v["duration"])
        ok &= report("titles", titled == len(vs), f"{titled}/{len(vs)}")
        ok &= report("view counts", viewed >= len(vs) * 0.8, f"{viewed}/{len(vs)}")
        ok &= report("durations", timed >= len(vs) * 0.8, f"{timed}/{len(vs)}")
        print(f"        e.g. {vs[0]['id']}  {vs[0]['duration']}s  "
              f"{vs[0]['views']} views  {vs[0]['title'][:44]}")

    tok = continuation(r)
    ok &= report("continuation token", bool(tok), (tok or "")[:24] + "...")
    if tok:
        r2 = post("browse", {"continuation": tok})
        vs2 = videos(r2, ch)
        fresh = not (set(v["id"] for v in vs2) & set(v["id"] for v in vs))
        ok &= report("page 2 parsed", len(vs2) >= 10, f"{len(vs2)} items")
        # The decisive one: six tokens live in a tab response and only the grid's pages
        # forward. A wrong pick re-serves page 1 or a different shelf.
        ok &= report("page 2 is not page 1", fresh,
                     "no overlap" if fresh else "OVERLAP - wrong continuation picked")

    print("\nother tabs")
    for tab, params in TABS.items():
        if tab == "videos":
            continue
        got = []
        for prm in params:
            got = videos(post("browse", {"browseId": bid, "params": prm}), ch)
            if got:
                break
        titled = sum(1 for v in got if v["title"] and v["title"] != v["id"])
        print(f"  {'ok  ' if got else '--  '}  {tab:<34} {len(got)} items"
              + (f", all titled" if got and titled == len(got) else ""))

    print("\nsearch  (channels)")
    r = post("search", {"query": args.channel.lstrip("@"), "params": "EgIQAg=="})
    cs = channels(r)
    ok &= report("channels parsed", len(cs) >= 5, f"{len(cs)} results")
    if cs:
        withsubs = sum(1 for c in cs if c["subscribers"])
        withav = sum(1 for c in cs if c["avatar"])
        withh = sum(1 for c in cs if c["handle"])
        # This is the field swap: the count lives in `videoCountText`, the handle in
        # `subscriberCountText`. Reading them by name silently loses both.
        ok &= report("subscriber counts", withsubs >= len(cs) * 0.6, f"{withsubs}/{len(cs)}")
        ok &= report("handles", withh >= len(cs) * 0.6, f"{withh}/{len(cs)}")
        ok &= report("avatars", withav >= len(cs) * 0.6, f"{withav}/{len(cs)}")
        print(f"        e.g. {cs[0]['id']}  {cs[0]['handle']}  "
              f"{cs[0]['subscribers']} subs  {cs[0]['title'][:28]}")

    print("\n" + ("PASS" if ok else "FAIL - port fixes back into Renderers.swift"))
    return 0 if ok else 1


def find_all_values(node, key, out=None):
    out = [] if out is None else out
    if isinstance(node, dict):
        if key in node:
            out.append(node[key])
        for v in node.values():
            find_all_values(v, key, out)
    elif isinstance(node, list):
        for v in node:
            find_all_values(v, key, out)
    return out


if __name__ == "__main__":
    import sys
    sys.exit(main())
