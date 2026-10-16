"""A stand-in for NEO's core websocket, for NeoListenerTests.

Mirrors the parts of neo2/core/server/ws.py the listener depends on: the
token in the query string, the Origin rule (a request with an Origin header
that is not NEO's own overlay or the notch's page is refused with 403), the
role rule (`role=host` beside the token makes a client a host — the only
kind the core takes NEO.app's menu actions from — and is refused, 403, to
anything that sent an Origin: no page is ever a host), the `hello` first
(with what NEO.app's shell reported, `shell`), then a scripted run of state /
transcript / note / error / card messages and one `shell_status`. Every
command a client sends is echoed to stdout as `CMD <json>`, each connection
as `OPEN <n>`, the Origin it came with as `ORIGIN <origin>` and its role as
`ROLE <role>` (`-` for none), so the test can check what a client said.

    neo_stub.py PORT TOKEN [drop | confirm | settings | timers | brains]

With `drop`, the first connection is closed by the server after the script,
so the client's reconnect can be watched; later connections stay open.

With `confirm`, the stub plays a core that is waiting for an OK, as
neo2/core/agent/confirm.py and ws.py do it: the `hello` carries the card
still pending (`confirm`), a newer card then supersedes it (`confirm_done`
for the old id, `confirm` for the new), and a client's
`{"cmd":"confirm","yes":…,"action_id":…}` for the card that is pending is
answered with `confirm_done` — to every client, as the bus does. An answer
naming any other id closes nothing.

With `settings`, the stub plays a core whose "Listen for 'Neo'" can be
switched, as neo2/core/server/ws.py and app.py do it: the `hello` says where
it stands (`wake_word`), and a `{"cmd":"set","name":"wake_word","value":bool}`
from a host is applied, told to every client in a `settings` event, and
answered to the sender with `set_result`. From anything that is not a host
it is refused (`forbidden`); a name it does not know is `unknown`, a value
that is not a boolean `invalid` — and nothing changes. (The other modes'
hello says `wake_word` too, except `confirm`'s: an older core, which has no
such setting.)

With `timers`, the stub plays a core with timers running, as
neo2/core/tools/system.py and ws.py announce them: the `hello` lists the
timers counting down now (`timers`, soonest first), then `activity` events
start one (`op: present`), say one went off (`op: end`, `done: true`) and
cancel one (`op: end`, `done: false`), with an activity of a later kind in
between that is not the island's. Nothing a client sends is answered.

With `brains`, the stub plays a core with Brains & Keys, as
neo2/core/brains.py and ws.py report it to every client: the `hello` carries
`brains` (no model yet: NEO does only simple commands), then a key is saved
in NEO.app's window and everyone hears a `brains` event (Claude doing NEO's
tasks), then a `brains` event that is not NEO's (no `ready`), which says
nothing, and a `brains_detail` — the window's own, which a real core never
sends a host — that must not count either. No key, no last 4, ever: only
which providers have one. Nothing a client sends is answered. (No other
mode's hello has `brains`: an older core, from before Brains & Keys.)
"""
import asyncio
import json
import sys
from urllib.parse import parse_qs, urlparse

from websockets.asyncio.server import serve

PORT = int(sys.argv[1])
TOKEN = sys.argv[2]
DROP = len(sys.argv) > 3 and sys.argv[3] == "drop"
CONFIRM = len(sys.argv) > 3 and sys.argv[3] == "confirm"
SETTINGS = len(sys.argv) > 3 and sys.argv[3] == "settings"
TIMERS = len(sys.argv) > 3 and sys.argv[3] == "timers"
BRAINS = len(sys.argv) > 3 and sys.argv[3] == "brains"
CARD_A = {"action_id": "trash:4d15b0099e5a9d0a", "tool": "trash", "summary": "move report.pdf to the Trash",
          "detail": "/Users/me/Documents/report.pdf", "scopes": [], "app": ""}
CARD_B = {"action_id": "shell:b7f034d65f0f4e1a", "tool": "shell", "summary": "run a command",
          "detail": "mv '/Users/me/Documents/report.pdf' ~/.Trash/", "scopes": ["task"], "app": "Finder"}
ALLOWED_ORIGINS = {"tauri://localhost", "neo://app"}

connections = 0
wake_word = {"on": True}
clients = set()


def say(line: str) -> None:
    print(line, flush=True)


def admit(connection, request):
    origin = request.headers.get("Origin")
    say(f"ORIGIN {origin or '-'}")
    if origin is not None and origin not in ALLOWED_ORIGINS:
        say(f"REJECT origin={origin}")
        return connection.respond(403, "Forbidden origin\n")
    query = parse_qs(urlparse(request.path).query)
    given = (query.get("token") or [""])[0]
    if given != TOKEN:
        say("REJECT token")
        return connection.respond(401, "Missing or wrong token\n")
    role = (query.get("role") or [""])[0]
    say(f"ROLE {role or '-'}")
    if role not in ("", "host") or (role and origin is not None):
        say(f"REJECT role={role}")
        return connection.respond(403, "Forbidden role\n")
    return None


async def handle(ws):
    global connections
    connections += 1
    n = connections
    say(f"OPEN {n}")

    async def send(type_, data):
        await ws.send(json.dumps({"type": type_, "data": data, "ts": 1.0}))

    async def script():
        # The hello: NEO is listening, and the replay holds an OLD transcript
        # line the island must never show.
        await send("hello", {
            "state": "listening",
            "recent": [{"type": "transcript", "data": {"role": "assistant", "text": "stale reply", "final": True}, "ts": 0.5}],
            "confirm": None,
            "problems": [],
            "host_attached": True,
            "wake_word": wake_word["on"],
            # NEO.app's shell has reported: Screen Recording is not allowed yet.
            "shell": {"running": True, "app": True, "accessibility": True, "screen_recording": False,
                      "open_at_login": True, "version": "2.1.0", "hotkey": "⌥⌘"},
        })
        await asyncio.sleep(0.05)
        await send("transcript", {"role": "user", "text": "hello neo", "final": False, "job": ""})
        await send("state", {"state": "thinking", "job": ""})
        await send("tool_start", {"name": "web", "job": ""})  # not the lane's business
        await send("browser_open", {"sid": "s1", "job": "j1"})  # a card: the panel's business
        await send("browser_state", {"sid": "s1", "url": "https://example.com"})  # the card's own
        await send("browser_close", {"sid": "s1", "reason": "done"})
        await send("transcript", {"role": "assistant", "text": "Hi there", "final": True, "job": ""})
        await send("note", {"text": "quiet result"})
        await send("error", {"message": "boom"})
        # The user allowed Screen Recording: NEO.app's shell says so, the core tells everyone.
        await send("shell_status", {"running": True, "app": True, "accessibility": True, "screen_recording": True,
                                    "open_at_login": True, "version": "2.1.0", "hotkey": "⌥⌘"})
        await send("shell_result", {"action": "restart", "ok": True})  # an answer to a host: not a fact
        await send("host_attached", {"attached": True})  # NEO.app's business
        await send("state", {"state": "idle", "job": ""})
        await ws.send(b"\x00\x01\x02")  # a binary frame: ignored

    pending = {"id": CARD_A["action_id"]}

    async def confirm_script():
        await send("hello", {"state": "idle", "recent": [], "confirm": CARD_A, "problems": [], "host_attached": True})
        await asyncio.sleep(0.05)
        await send("confirm_done", {"action_id": CARD_A["action_id"], "outcome": "superseded"})
        pending["id"] = CARD_B["action_id"]
        await send("state", {"state": "confirming", "job": "j4"})
        await send("confirm", CARD_B)

    async def settings_script():
        await send("hello", {"state": "idle", "recent": [], "confirm": None, "problems": [], "host_attached": True,
                             "wake_word": wake_word["on"]})

    async def timers_script():
        await send("hello", {"state": "thinking", "recent": [], "confirm": None, "problems": [], "host_attached": True,
                             "timers": [{"id": "timer:3f2a9c1b7d4e", "title": "Pasta", "ends_at": 1760270252.0},
                                        {"id": "timer:a1b2c3d4e5f6", "title": "Timer", "ends_at": 1760270900.5}]})
        await asyncio.sleep(0.05)

        def activity(op, id_, title, ends_at, done, kind="timer"):
            return {"op": op, "id": id_, "kind": kind, "title": title, "ends_at": ends_at, "done": done}

        await send("activity", activity("present", "timer:0123456789ab", "Eggs", 1760270400.0, False))
        await send("activity", activity("end", "timer:3f2a9c1b7d4e", "Pasta", 1760270252.0, True))
        await send("activity", activity("present", "reminder:1", "Call mum", 1760270500.0, False, kind="reminder"))
        await send("activity", activity("end", "timer:0123456789ab", "Eggs", 1760270400.0, False))
        await send("state", {"state": "idle", "job": ""})

    async def brains_script():
        def role(ref, provider, label, ok):
            return {"ref": ref, "provider": provider, "label": label, "ok": ok}

        await send("hello", {"state": "idle", "recent": [], "confirm": None, "problems": [
            "NEO has no AI model yet, so it can only do simple commands. Open Brains & Keys to connect one."],
            "host_attached": True, "wake_word": True,
            "brains": {"ready": False, "brain": role("gemini", "gemini", "Gemini 3.8 Flash", False),
                       "quick": role("gemini", "gemini", "Gemini 3.8 Flash", False), "eyes": None, "voice": "local",
                       "providers": {"gemini": False, "anthropic": False, "openai": False}, "restart_needed": False}})
        await asyncio.sleep(0.05)
        await send("brains", {"ready": True, "brain": role("claude@claude-opus-5-5", "anthropic", "Claude Opus 5.5", True),
                              "quick": role("claude@claude-haiku-5-5", "anthropic", "Claude Haiku 5.5", True),
                              "eyes": None, "voice": "local",
                              "providers": {"gemini": False, "anthropic": True, "openai": False}, "restart_needed": False})
        await send("problems", {"problems": []})
        await send("brains", {"brain": "not NEO's"})
        await send("brains_detail", {"ready": False, "brain": "a window's"})
        await send("state", {"state": "idle", "job": ""})

    async def set_(cmd):
        """`set`, as the core answers it."""
        name, value = str(cmd.get("name") or ""), cmd.get("value")
        role = (parse_qs(urlparse(ws.request.path).query).get("role") or [""])[0]
        error = ""
        if role != "host":
            error = "forbidden"
        elif name != "wake_word":
            error = "unknown"
        elif not isinstance(value, bool):
            error = "invalid"
        if not error:
            wake_word["on"] = value
            for other in list(clients):
                await other.send(json.dumps({"type": "settings", "data": {"wake_word": value}, "ts": 1.0}))
        await send("set_result", {"name": name, "ok": not error, **({"error": error} if error else {})})

    clients.add(ws)
    sender = asyncio.create_task(
        confirm_script() if CONFIRM else settings_script() if SETTINGS else timers_script() if TIMERS
        else brains_script() if BRAINS else script())
    try:
        if DROP and n == 1:
            await sender
            await asyncio.sleep(0.2)
            await ws.close()
            return
        async for raw in ws:
            if isinstance(raw, str):
                say(f"CMD {raw}")
                if not (CONFIRM or SETTINGS):
                    continue
                try:
                    cmd = json.loads(raw)
                except ValueError:
                    continue
                if SETTINGS:
                    if isinstance(cmd, dict) and cmd.get("cmd") == "set":
                        await set_(cmd)
                    continue
                if cmd.get("cmd") == "confirm" and cmd.get("action_id") == pending["id"]:
                    pending["id"] = None
                    outcome = "confirmed" if cmd.get("yes") is True else "user cancelled"
                    await send("confirm_done", {"action_id": cmd["action_id"], "outcome": outcome})
                    await send("state", {"state": "idle", "job": "j4"})
    finally:
        clients.discard(ws)
        if not sender.done():
            sender.cancel()


async def main():
    async with serve(handle, "127.0.0.1", PORT, process_request=admit):
        say("READY")
        await asyncio.Future()


asyncio.run(main())
