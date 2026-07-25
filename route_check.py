from bus_tracking_backend.main import app
for route in app.router.routes:
    path = getattr(route, 'path', None)
    if path and 'location' in path:
        print(path)
