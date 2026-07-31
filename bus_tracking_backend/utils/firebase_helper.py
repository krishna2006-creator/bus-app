import os
import json
import base64
import logging
from pathlib import Path
from typing import Optional
from firebase_admin import credentials

logger = logging.getLogger(__name__)


def get_firebase_credential() -> Optional[credentials.Certificate]:
    """
    Robust helper to load Firebase credentials from multiple sources:
    1. FIREBASE_CREDENTIALS_PATH env variable (absolute or relative)
    2. Local files ('firebase-key.json', 'serviceAccountKey.json')
    3. FIREBASE_CREDENTIALS_JSON env variable (raw JSON string)
    4. FIREBASE_CREDENTIALS_BASE64 env variable (base64 encoded JSON string)
    """
    backend_dir = Path(__file__).resolve().parent.parent

    # Try loading .env if environment variables aren't loaded yet
    env_path = backend_dir / ".env"
    if env_path.exists():
        try:
            with open(env_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, v = line.split("=", 1)
                        k = k.strip()
                        v = v.strip().strip("'").strip('"')
                        if k and k not in os.environ:
                            os.environ[k] = v
        except Exception as exc:
            logger.warning("Failed to load .env file: %s", exc)

    # 1. Try FIREBASE_CREDENTIALS_PATH
    creds_path_env = os.getenv("FIREBASE_CREDENTIALS_PATH")
    candidate_paths = []

    if creds_path_env:
        candidate_paths.append(Path(creds_path_env))
        candidate_paths.append(backend_dir / creds_path_env)
        candidate_paths.append(backend_dir / Path(creds_path_env).name)

    # 2. Standard fallback filenames in backend folder
    candidate_paths.append(backend_dir / "firebase-key.json")
    candidate_paths.append(backend_dir / "serviceAccountKey.json")

    for path in candidate_paths:
        try:
            if path and path.exists() and path.is_file():
                logger.info("Loading Firebase credentials from file: %s", path)
                return credentials.Certificate(str(path))
        except Exception as exc:
            logger.warning("Failed to load Firebase credentials from file %s: %s", path, exc)

    # 3. Check FIREBASE_CREDENTIALS_JSON env var (raw JSON string)
    creds_json_str = os.getenv("FIREBASE_CREDENTIALS_JSON")
    if creds_json_str:
        try:
            creds_data = json.loads(creds_json_str)
            logger.info("Loading Firebase credentials from FIREBASE_CREDENTIALS_JSON env var.")
            return credentials.Certificate(creds_data)
        except Exception as exc:
            logger.error("Failed to parse FIREBASE_CREDENTIALS_JSON env var: %s", exc)

    # 4. Check FIREBASE_CREDENTIALS_BASE64 env var (base64 string)
    creds_b64 = os.getenv("FIREBASE_CREDENTIALS_BASE64")
    if creds_b64:
        try:
            # Strip any whitespace/newlines that may be added by env var editors
            creds_b64_clean = creds_b64.strip()
            creds_data = json.loads(base64.b64decode(creds_b64_clean).decode("utf-8"))
            # Fix private_key: ensure \n are real newlines (not escaped)
            if "private_key" in creds_data:
                creds_data["private_key"] = creds_data["private_key"].replace("\\n", "\n")
            logger.info("Loading Firebase credentials from FIREBASE_CREDENTIALS_BASE64 env var.")
            return credentials.Certificate(creds_data)
        except Exception as exc:
            logger.error("Failed to parse FIREBASE_CREDENTIALS_BASE64 env var: %s", exc)

    logger.error(
        "No Firebase credentials found! Set FIREBASE_CREDENTIALS_BASE64 in Render environment variables. "
        "Run: python bus_tracking_backend/print_firebase_b64.py to get the value."
    )
    return None
