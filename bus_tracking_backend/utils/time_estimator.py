def estimate_eta_minutes(distance_km: float, speed_kmh: float) -> int:
    if speed_kmh <= 0:
        return 0 # Unknown or stopped
    
    hours = distance_km / speed_kmh
    return int(hours * 60)