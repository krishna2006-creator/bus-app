from bus_tracking_backend.main import app

for route in app.router.routes:
    if getattr(route, 'path', None) and 'ws' in getattr(route, 'path', ''):
        print(route.path, type(route).__name__)
