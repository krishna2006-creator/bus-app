import asyncio
import websockets

async def main():
    uri = 'ws://127.0.0.1:8000/api/ws/ws/location/1?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMjAwNiIsImV4cCI6MTc4Mzc2NTkyM30.nnDz5lg90pUrfUi67AGejeK2_kHCP5u81xutsSwWYHQ'
    try:
        async with websockets.connect(uri, open_timeout=5) as ws:
            print('CONNECTED')
            await ws.send('{"type":"PING"}')
            msg = await ws.recv()
            print('MESSAGE', msg)
    except Exception as e:
        print(type(e).__name__, e)

asyncio.run(main())
