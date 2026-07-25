import os
import redis
import json

REDIS_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')
_redis = None

def get_redis():
    global _redis
    if _redis is None:
        _redis = redis.Redis.from_url(REDIS_URL, decode_responses=True)
    return _redis

def set_latest_location(entity_key: str, payload: dict):
    r = get_redis()
    r.hset('latest_locations', entity_key, json.dumps(payload))
    # Also publish to channel for subscribers
    r.publish('locations', json.dumps({"key": entity_key, "payload": payload}))

def get_latest_location(entity_key: str):
    r = get_redis()
    data = r.hget('latest_locations', entity_key)
    if not data:
        return None
    try:
        return json.loads(data)
    except Exception:
        return None
