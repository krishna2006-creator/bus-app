import asyncio
import json
import websockets
from bus_tracking_backend.utils.auth_utils import create_access_token

async def main():
    token = create_access_token({'sub': 'user2006'})
    uri = f'ws://127.0.0.1:8000/api/ws/ws/location/1?token={token}'
    print('connecting', uri)
    async with websockets.connect(uri) as ws:
        await ws.send(json.dumps({'type': 'PING'}))
        reply = await ws.recv()
        print('reply', reply)
        await ws.close()

asyncio.run(main())
