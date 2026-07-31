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
    Robust helper to load Firebase credentials from multiple sources,
    checked in priority order:
    1. FIREBASE_KEY env variable (raw JSON string – the user's preferred method)
    2. FIREBASE_CREDENTIALS_PATH env variable (absolute or relative file path)
    3. Local files ('firebase-key.json', 'serviceAccountKey.json')
    4. FIREBASE_CREDENTIALS_JSON env variable (raw JSON string)
    5. FIREBASE_CREDENTIALS_BASE64 env variable (base64 encoded JSON string)
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

    # ------------------------------------------------------------------
    # 1. FIREBASE_KEY – raw JSON content of the service-account key
    #    This is the user's preferred approach: paste the full
    #    firebase-key.json content directly into this env variable.
    # ------------------------------------------------------------------
    firebase_key_raw = os.getenv("FIREBASE_KEY")
    if firebase_key_raw:
        try:
            creds_data = json.loads(firebase_key_raw)
            logger.info("Loading Firebase credentials from FIREBASE_KEY env var.")
            return credentials.Certificate(creds_data)
        except Exception as exc:
            logger.error("Failed to parse FIREBASE_KEY env var: %s", exc)

    # ------------------------------------------------------------------
    # 2. FIREBASE_CREDENTIALS_PATH – file path pointing to a JSON key file
    # ------------------------------------------------------------------
    creds_path_env = os.getenv("FIREBASE_CREDENTIALS_PATH")
    candidate_paths = []

    if creds_path_env:
        candidate_paths.append(Path(creds_path_env))
        candidate_paths.append(backend_dir / creds_path_env)
        candidate_paths.append(backend_dir / Path(creds_path_env).name)

    cwd = Path(os.getcwd())

    # 3. All locations where firebase-key.json could exist
    for fname in ["firebase-key.json", "serviceAccountKey.json"]:
        candidate_paths += [
            backend_dir / fname,           # bus_tracking_backend/firebase-key.json
            cwd / fname,                   # current working directory
            cwd / "bus_tracking_backend" / fname,
            Path("/etc/secrets") / fname,  # Render secret files default location
            Path("/opt/render/project/src") / fname,
            Path("/opt/render/project/src/bus_tracking_backend") / fname,
        ]

    for path in candidate_paths:
        try:
            if path and path.exists() and path.is_file():
                logger.info("Loading Firebase credentials from file: %s", path)
                return credentials.Certificate(str(path))
        except Exception as exc:
            logger.warning("Failed to load Firebase credentials from file %s: %s", path, exc)

    # 4. Check FIREBASE_CREDENTIALS_JSON env var (raw JSON string)
    creds_json_str = os.getenv("FIREBASE_CREDENTIALS_JSON")
    if creds_json_str:
        try:
            creds_data = json.loads(creds_json_str)
            logger.info("Loading Firebase credentials from FIREBASE_CREDENTIALS_JSON env var.")
            return credentials.Certificate(creds_data)
        except Exception as exc:
            logger.error("Failed to parse FIREBASE_CREDENTIALS_JSON env var: %s", exc)

    # 5. Check FIREBASE_CREDENTIALS_BASE64 env var (base64 string)
    creds_b64 = os.getenv("FIREBASE_CREDENTIALS_BASE64")
    if creds_b64:
        try:
            creds_b64_clean = creds_b64.strip()
            decoded_str = base64.b64decode(creds_b64_clean).decode("utf-8")
            creds_data = json.loads(decoded_str)
            logger.info("Loading Firebase credentials from FIREBASE_CREDENTIALS_BASE64 env var.")
            return credentials.Certificate(creds_data)
        except Exception as exc:
            logger.error("Failed to parse FIREBASE_CREDENTIALS_BASE64 env var: %s", exc)

    logger.error(
        "No Firebase credentials found! Set the FIREBASE_KEY environment variable "
        "with the full JSON content of your firebase-key.json file. "
        "Alternatively, set FIREBASE_CREDENTIALS_PATH to a key file path, "
        "FIREBASE_CREDENTIALS_JSON for raw JSON, or FIREBASE_CREDENTIALS_BASE64 "
        "for a base64-encoded key."
    )
    return None
