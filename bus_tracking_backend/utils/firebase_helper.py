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
    1. FIREBASE_CREDENTIALS_PATH env variable (absolute or relative to backend directory)
    2. Default files in backend directory ('firebase-key.json', 'serviceAccountKey.json')
    3. FIREBASE_CREDENTIALS_JSON env variable (raw JSON string)
    4. FIREBASE_CREDENTIALS_BASE64 env variable (base64 encoded JSON string)
    """
    backend_dir = Path(__file__).resolve().parent.parent

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
            creds_data = json.loads(base64.b64decode(creds_b64).decode("utf-8"))
            logger.info("Loading Firebase credentials from FIREBASE_CREDENTIALS_BASE64 env var.")
            return credentials.Certificate(creds_data)
        except Exception as exc:
            logger.error("Failed to parse FIREBASE_CREDENTIALS_BASE64 env var: %s", exc)

    logger.warning("No valid Firebase credentials found across files or environment variables.")
    return None
