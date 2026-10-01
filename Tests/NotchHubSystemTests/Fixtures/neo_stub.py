"""A stand-in for NEO's core websocket, for NeoListenerTests.

Mirrors the parts of neo2/core/server/ws.py the listener depends on: the
token in the query string, the Origin rule (a request with an Origin header
that is not NEO's own overlay is refused with 403), the `hello` first, then
a scripted run of state / transcript / note / error messages. Every command
a client sends is echoed to stdout as `CMD <json>`, and each connection as
`OPEN <n>`, so the test can check what the listener said.

    neo_stub.py PORT TOKEN [drop]

With `drop`, the first connection is closed by the server after the script,
so the client's reconnect can be watched; later connections stay open.
"""
import asyncio
import json
import sys
from urllib.parse import parse_qs, urlparse

from websockets.asyncio.server import serve

PORT = int(sys.argv[1])
TOKEN = sys.argv[2]
DROP = len(sys.argv) > 3 and sys.argv[3] == "drop"
ALLOWED_ORIGINS = {"tauri://localhost"}

connections = 0


def say(line: str) -> None:
    print(line, flush=True)


def admit(connection, request):
    origin = request.headers.get("Origin")
    if origin is not None and origin not in ALLOWED_ORIGINS:
        say(f"REJECT origin={origin}")
        return connection.respond(403, "Forbidden origin\n")
    given = (parse_qs(urlparse(request.path).query).get("token") or [""])[0]
    if given != TOKEN:
        say("REJECT token")
        return connection.respond(401, "Missing or wrong token\n")
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
        })
        await asyncio.sleep(0.05)
        await send("transcript", {"role": "user", "text": "hello neo", "final": False, "job": ""})
        await send("state", {"state": "thinking", "job": ""})
        await send("tool_start", {"name": "web", "job": ""})  # not the lane's business
        await send("transcript", {"role": "assistant", "text": "Hi there", "final": True, "job": ""})
        await send("note", {"text": "quiet result"})
        await send("error", {"message": "boom"})
        await send("state", {"state": "idle", "job": ""})
        await ws.send(b"\x00\x01\x02")  # a binary frame: ignored

    sender = asyncio.create_task(script())
    try:
        if DROP and n == 1:
            await sender
            await asyncio.sleep(0.2)
            await ws.close()
            return
        async for raw in ws:
            if isinstance(raw, str):
                say(f"CMD {raw}")
    finally:
        if not sender.done():
            sender.cancel()


async def main():
    async with serve(handle, "127.0.0.1", PORT, process_request=admit):
        say("READY")
        await asyncio.Future()


asyncio.run(main())
