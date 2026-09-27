#!/usr/bin/env python3
"""A stand-in for Supabase Realtime, for testing the room-code relay offline:
speaks the same Phoenix channel messages (phx_join -> phx_reply ok, heartbeat
-> phx_reply, "broadcast" -> sent on to everyone else on the topic).

    python3 tests/tools/fake_realtime.py 24780
    ST_RELAY=ws://127.0.0.1:24780 ROLE=host RELAY=1 godot ... -s tests/net_test.gd
"""
import asyncio, json, sys
import websockets

rooms = {}  # topic -> set of sockets


async def handler(ws):
    joined = set()
    try:
        async for raw in ws:
            msg = json.loads(raw)
            topic, event, ref = msg.get("topic"), msg.get("event"), msg.get("ref")
            if event == "phx_join":
                rooms.setdefault(topic, set()).add(ws)
                joined.add(topic)
                await ws.send(json.dumps({"topic": topic, "event": "phx_reply", "ref": ref, "payload": {"status": "ok", "response": {}}}))
            elif event == "heartbeat":
                await ws.send(json.dumps({"topic": "phoenix", "event": "phx_reply", "ref": ref, "payload": {"status": "ok", "response": {}}}))
            elif event == "broadcast" and topic in joined:
                out = json.dumps({"topic": topic, "event": "broadcast", "ref": None, "payload": msg.get("payload")})
                for other in list(rooms.get(topic, ())):
                    if other is not ws:
                        try:
                            await other.send(out)
                        except Exception:
                            pass
    finally:
        for t in joined:
            rooms.get(t, set()).discard(ws)


async def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 24780
    async with websockets.serve(handler, "127.0.0.1", port, max_size=2 ** 22):
        await asyncio.Future()

asyncio.run(main())
