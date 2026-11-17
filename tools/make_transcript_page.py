#!/data/data/com.termux/files/usr/bin/python3 -I
"""Turns a Claude Code session file (.jsonl) into docs/transcript.json + docs/img/*, which
docs/index.html renders like the terminal: prompts, replies, and fold-out tool calls.

usage: tools/make_transcript_page.py SESSION.jsonl docs/ [TAIL_FROM [LAST]]
  TAIL_FROM: first words of a user message; after it only the user's own messages are kept
  LAST:      first words of the final user message to include (defaults to TAIL_FROM)

Left out on purpose: Claude's hidden reasoning, system context (it carries private settings and
contact details), image-size notes, and portrait phone screenshots (home screen / app drawer)."""
import base64, json, os, re, struct, sys

src, out = sys.argv[1], sys.argv[2]
tail_from = sys.argv[3] if len(sys.argv) > 3 else None
last_msg = sys.argv[4] if len(sys.argv) > 4 else tail_from
tail = False   # after tail_from: user messages only
img_dir = os.path.join(out, "img")
os.makedirs(img_dir, exist_ok=True)
for f in os.listdir(img_dir):
    os.remove(os.path.join(img_dir, f))

REDACT = [
    (re.compile(r"<system-reminder>.*?</system-reminder>", re.S), ""),
    (re.compile(r"[\w.+-]+@gmail\.com"), "[email removed]"),
]
MAX = 40000


def clean(s):
    for pat, rep in REDACT:
        s = pat.sub(rep, s)
    s = s.strip()
    if len(s) > MAX:
        s = s[:MAX] + f"\n… [{len(s) - MAX} more characters not shown]"
    return s


def img_size(b):
    """(width, height) of a PNG or JPEG, or None."""
    if b[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", b[16:24])
    if b[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(b):
            if b[i] != 0xFF:
                i += 1
                continue
            marker = b[i + 1]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", b[i + 5:i + 9])
                return (w, h)
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                i += 2
                continue
            i += 2 + struct.unpack(">H", b[i + 2:i + 4])[0]
    return None


events, tools, n_img = [], {}, 0
done = False


def add_image(src_obj):
    global n_img
    data = base64.b64decode(src_obj.get("data", ""))
    size = img_size(data)
    if size is None or size[1] > size[0] * 1.5:
        return None  # portrait phone screenshot: personal home screen, left out
    ext = "png" if "png" in src_obj.get("media_type", "png") else "jpg"
    n_img += 1
    name = f"img/{n_img:03d}.{ext}"
    open(os.path.join(out, name), "wb").write(data)
    return name


for line in open(src):
    if done:
        break
    d = json.loads(line)
    t = d.get("type")
    ts = d.get("timestamp", "")
    if t == "attachment":
        a = d.get("attachment", {})
        if a.get("type") == "queued_command" and isinstance(a.get("prompt"), str):
            txt = clean(a["prompt"])
            if txt:
                events.append({"k": "user", "text": txt, "mid": True, "ts": ts})
                tail = tail or bool(tail_from and txt.startswith(tail_from))
                if last_msg and txt.startswith(last_msg):
                    done = True
        continue
    if t not in ("user", "assistant"):
        continue
    m = d.get("message") or {}
    c = m.get("content")
    if t == "user" and isinstance(c, str):
        txt = clean(c)
        if txt and not txt.startswith("[Image: original") and not txt.startswith("<command-"):
            events.append({"k": "user", "text": txt, "ts": ts})
            tail = tail or bool(tail_from and txt.startswith(tail_from))
            if last_msg and txt.startswith(last_msg):
                done = True
        continue
    if not isinstance(c, list):
        continue
    if tail:
        continue   # only the user's own messages from here on
    for b in c:
        if not isinstance(b, dict):
            continue
        bt = b.get("type")
        if t == "assistant" and bt == "text":
            txt = clean(b.get("text", ""))
            if txt:
                events.append({"k": "say", "text": txt, "ts": ts})
        elif t == "assistant" and bt in ("tool_use", "server_tool_use"):
            inp = b.get("input") or {}
            ev = {"k": "tool", "name": b.get("name", "?"), "ts": ts, "out": "", "imgs": [], "err": False}
            name = ev["name"]
            if name == "Bash":
                ev["title"] = inp.get("description") or inp.get("command", "")[:80]
                ev["body"] = clean(inp.get("command", ""))
            elif name in ("Write",):
                ev["title"] = inp.get("file_path", "").split("ClaudeProjects/")[-1]
                ev["body"] = clean(inp.get("content", ""))
            elif name in ("Read",):
                ev["title"] = inp.get("file_path", "").split("ClaudeProjects/")[-1].split("/files/home/")[-1]
                ev["body"] = ""
            elif name == "Edit":
                ev["title"] = inp.get("file_path", "").split("ClaudeProjects/")[-1]
                ev["body"] = clean("- " + inp.get("old_string", "") + "\n+ " + inp.get("new_string", ""))
            elif name == "advisor":
                ev["title"] = "asking a reviewer model for a second opinion"
                ev["body"] = ""
            elif name == "AskUserQuestion":
                ev["title"] = "question for Jazzy"
                ev["body"] = clean("\n".join(q.get("question", "") for q in inp.get("questions", [])))
            else:
                ev["title"] = ""
                ev["body"] = clean(json.dumps(inp, indent=1))
            tools[b.get("id")] = ev
            events.append(ev)
        elif bt in ("tool_result", "advisor_tool_result"):
            ev = tools.get(b.get("tool_use_id"))
            if ev is None:
                continue
            rc = b.get("content")
            parts = []
            if isinstance(rc, str):
                parts.append(rc)
            elif isinstance(rc, list):
                for x in rc:
                    if x.get("type") == "text":
                        parts.append(x.get("text", ""))
                    elif x.get("type") == "image":
                        name = add_image(x.get("source", {}))
                        if name:
                            ev["imgs"].append(name)
                        else:
                            parts.append("[phone home-screen screenshot left out of the public page]")
            elif isinstance(rc, dict) and rc.get("type") == "advisor_result":
                parts.append(rc.get("text", ""))
            ev["out"] = clean("\n".join(parts))
            ev["err"] = bool(b.get("is_error"))

# Optional private rules (not in the repo): anonymise mentions of other projects and of Claude's
# own notes. Tool calls that touch them keep only a neutral title, with no command or output.
rules_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".private_redact.json")
if os.path.exists(rules_path):
    R = json.load(open(rules_path))
    kw = re.compile(R["keywords"], re.I)
    for ev in events:
        for pat, rep in R.get("body_replace", []):
            for f in ("body", "out", "title"):
                if ev.get(f):
                    ev[f] = re.sub(pat, rep, ev[f])
        if ev["k"] in ("say", "user"):
            for a, b in R.get("text_replace", []):
                ev["text"] = ev["text"].replace(a, b)
        if ev["k"] != "tool":
            continue
        if ev["name"] == "AskUserQuestion":
            ev["out"] = R.get("ask_out", "")
        if any(kw.search(ev.get(f) or "") for f in ("title", "body", "out")):
            new = next((t for o, t in R["titles"] if ev.get("title", "").startswith(o)), None)
            if new is None:
                new = R["default_commit_title"] if "commit" in ev.get("title", "").lower() else R["default_title"]
            ev.update(title=new, body="", out="", imgs=[], err=False)

json.dump(events, open(os.path.join(out, "transcript.json"), "w"), ensure_ascii=False)
print(f"{len(events)} events, {n_img} images -> {out}")
