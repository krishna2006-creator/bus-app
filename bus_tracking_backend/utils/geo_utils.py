import httpx
from geopy.distance import geodesic

async def get_osrm_route(start_lat: float, start_lon: float, end_lat: float, end_lon: float):
    """
    Core road-based routing using OSRM.
    Returns (distance_km, duration_minutes)
    """
    url = f"https://router.project-osrm.org/route/v1/driving/{start_lon},{start_lat};{end_lon},{end_lat}?overview=false"
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(url, timeout=5.0)
            if response.status_code == 200:
                data = response.json()
                if data.get("code") == "Ok" and data.get("routes"):
                    route = data["routes"][0]
                    return route["distance"] / 1000.0, route["duration"] / 60.0
    except Exception as e:
        print(f"OSRM Routing Error: {e}")
    return 0.0, 0.0

def calculate_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Straight-line fallback using Haversine/Geodesic."""
    return geodesic((lat1, lon1), (lat2, lon2)).km

def estimate_eta_minutes(distance_km: float, speed_kmph: float) -> int:
    """Math-based fallback for ETA."""
    effective_speed = max(speed_kmph, 20.0) # Assume 20km/h if stationary
    return int((distance_km / effective_speed) * 60)
