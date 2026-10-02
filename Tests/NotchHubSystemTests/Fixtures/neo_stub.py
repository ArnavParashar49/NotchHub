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

    neo_stub.py PORT TOKEN [drop | confirm]

With `drop`, the first connection is closed by the server after the script,
so the client's reconnect can be watched; later connections stay open.

With `confirm`, the stub plays a core that is waiting for an OK, as
neo2/core/agent/confirm.py and ws.py do it: the `hello` carries the card
still pending (`confirm`), a newer card then supersedes it (`confirm_done`
for the old id, `confirm` for the new), and a client's
`{"cmd":"confirm","yes":…,"action_id":…}` for the card that is pending is
answered with `confirm_done` — to every client, as the bus does. An answer
naming any other id closes nothing.
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
CARD_A = {"action_id": "trash:4d15b0099e5a9d0a", "tool": "trash", "summary": "move report.pdf to the Trash",
          "detail": "/Users/me/Documents/report.pdf", "scopes": [], "app": ""}
CARD_B = {"action_id": "shell:b7f034d65f0f4e1a", "tool": "shell", "summary": "run a command",
          "detail": "mv '/Users/me/Documents/report.pdf' ~/.Trash/", "scopes": ["task"], "app": "Finder"}
ALLOWED_ORIGINS = {"tauri://localhost", "neo://app"}

connections = 0


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

    sender = asyncio.create_task(confirm_script() if CONFIRM else script())
    try:
        if DROP and n == 1:
            await sender
            await asyncio.sleep(0.2)
            await ws.close()
            return
        async for raw in ws:
            if isinstance(raw, str):
                say(f"CMD {raw}")
                if not CONFIRM:
                    continue
                try:
                    cmd = json.loads(raw)
                except ValueError:
                    continue
                if cmd.get("cmd") == "confirm" and cmd.get("action_id") == pending["id"]:
                    pending["id"] = None
                    outcome = "confirmed" if cmd.get("yes") is True else "user cancelled"
                    await send("confirm_done", {"action_id": cmd["action_id"], "outcome": outcome})
                    await send("state", {"state": "idle", "job": "j4"})
    finally:
        if not sender.done():
            sender.cancel()


async def main():
    async with serve(handle, "127.0.0.1", PORT, process_request=admit):
        say("READY")
        await asyncio.Future()


asyncio.run(main())
