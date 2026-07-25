import unittest

from bus_tracking_backend.services.websocket_manager_v2 import WebSocketManager


class DummyWebSocket:
    def __init__(self):
        self.messages = []

    async def send_json(self, data):
        self.messages.append(data)
        return True


class WebSocketManagerTest(unittest.TestCase):
    def test_manager_supports_multiple_connections_for_same_user(self):
        import asyncio

        async def run_test():
            manager = WebSocketManager()
            ws1 = DummyWebSocket()
            ws2 = DummyWebSocket()

            await manager.connect(ws1, "same-user", "Alice", "student", 1)
            await manager.connect(ws2, "same-user", "Alice", "student", 1)

            bus_room = manager.buses[1]
            self.assertEqual(len(bus_room.connections["same-user"]), 2)

            await manager.broadcast_to_bus(1, {"type": "LOCATION_UPDATE"})

            self.assertTrue(ws1.messages)
            self.assertTrue(ws2.messages)

        asyncio.run(run_test())


if __name__ == "__main__":
    unittest.main()
