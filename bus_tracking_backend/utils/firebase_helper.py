import os
import json
import base64
import logging
from pathlib import Path
from typing import Optional
from firebase_admin import credentials

logger = logging.getLogger(__name__)

DEFAULT_FIREBASE_B64 = "ew0KICAidHlwZSI6ICJzZXJ2aWNlX2FjY291bnQiLA0KICAicHJvamVjdF9pZCI6ICJidXN0cmFja2VyLWFmYjNjIiwNCiAgInByaXZhdGVfa2V5X2lkIjogIjcwNWQ0ZTk5YzQ5MGZlZjY0NzYxMGIyOTA5ZGY2N2IzMzc4ZDNlZTEiLA0KICAicHJpdmF0ZV9rZXkiOiAiLS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tXG5NSUlFdlFJQkFEQU5CZ2txaGtpRzl3MEJBUUVGQUFTQ0JLY3dnZ1NqQWdFQUFvSUJBUUNZdHFPMnpFMTd5clhsXG5aZ1N1ak9oV25TbFArT3ZGT3BSMGpTRWNBY1BEOTZpcTAxMFIzaXBGR0FzYzRJeHRxN0JVd0p0bitoZm5wSU1FXG5wR3lrR2xyQ1Biem9nczNtTi9qc3lDSmNBcEdaVXBncEw1MnRUKzlWWnBIRDdIWlJueXh2L3lwaDY0NHY2MU90XG5WTVlOcC9QYVRsbGV1ZzczYlZYTGowRno5dzdueTdleHMxSnQ4aVhkc0JQRTBOYktXZjcvTTc1aFIwVTZtOENFXG5Cc1J0RVdUNjcycXlrUzJqS1ZITTJJMVI0aHdER1ZTMjZjcWJ1T1N5dmpmazcwZ2NpU3pqNThLODJ4LzE1YmJPXG5XLzdVWnA4R2szSG9SdDJicE5VYlJIVWF5NzVhampHdk5IUGQzejVuZERrcXpyQnhab0xoSU9ZS2R0bmFZL0ZUXG5ubVdjRnpIUEFnTUJBQUVDZ2dFQUZLN0h4WDR1RUZJSUNLV2toSzk0MkNJNDhpZllac0hrVVZTNzR6c3A5R1NhXG5aMmh3OW5hTWF3Y3ltaHFmYWtzU2VxZ0xaQzJ2QnlSMHlqQXF0cDhMSTd1UTFqekEvaWtlZ1pNcGRDUzA2M3NRXG5PS1BHU3k3RVQyQ3c1VVFsVWpDb3FCSjYvd0FVSmRGTlovQlBVcElvcUt4cjFqU0V5bVg0ZExWV1BBcDk3azZuXG5aS09aVDlxcW45OXoySUVnMnFNYkhLaWhKTDNXRENYSERzZUdzYzdaUzlmdktWbUlPQjFMN2pGL1lzeER1UHVyXG5jL2xreEdDU3B4VVdxYUFCNTA5V3A0V0JVUmRIajJSckY5QkRqNnQ3RE9ZNWdMWExRMzFaV3B2SFBlR2M5RXVwXG5tMkdoV0lSVW5CSFRuaitpWVdmRDY4ZXlRODA0YUgrdzRkRURLbUdRUVFLQmdRREp4K1RyblpDcVZlcmpLRkNHXG5RNXphVEUvK1ByL0lkMlYvS3c0VDdzb2hKTGk0ZnU3aTd5MzNWemxockhjMUZqcitjQmxmYjVjenZSVm13RHNKXG5uZFU5UGlLc25KVEhqSFdRS21lRklXbzRiQXUzU3VmQ1gyTmdHOE8vQlM1SVJZbWNKcWtObGVZWUhaYXR5Vno3XG5GN0tQcXZPMzlUaTlucDVnVklsUGNWUWJWd0tCZ1FEQnYzN2JkMUZmLyt4T3VUTVlPOTNiY29Xc21TZi9pQ1lnXG5jNm1CUlFMK1R0b3pRcm9ncVhDUXNtRU9yaklSa3o3akNQUHVMYlZHSTdMTnVDNk1DcHVKZHdxZzlCSnBTelpsXG5SemZlTDV3NHJTN1RyaDY3Y1ltbkVaVXhlc1I5TGdqcHgzRVRKNTgrOXpFeDJueHJYcmVhZ2Q1VFB1ZXhzeXlNXG5yekdOMGdZS1NRS0JnRlNLUGExQjdOU1Evc0tCcDRzNVZNUlphTUo3QTlzM3V2eVd5MlVxak9GcUEwSzVXOWtVXG5vTXVhYmQ0d1pobUY0TjJ0bGRQWWF4OHdQNEUzVlFUb2Jla2syVjQ4bEZFdTFpcTZ1WGliMFdjbVRacFQ5ZG9JXG5JUmlwU1ZBRkdha0tDV2UxQXV0QVBKRXFCSEYzaGs5bFZGakJKUytUdkZ3bDB2RkZPZXBnN3Y0dEFvR0FHVW5QXG5Xd0hsNHl2YVFpUTJJUkdmVVlkUEgwb1dTR29TMytWNDJHQ1RsWEhoVlJOK2k4alI0bkVGN2c2YWhtUzdycEo2XG5sRG52RVNxVHFmcENTUkVSWUEzam0wS0FMTEllZFhXb094M252QllPcUo1dmNIUFBUYmtqeWdPR0pmaWVQVFZFXG44d1VXNmZjRnVzWVR1MGZ2bXdFY2JhMG1QTEZ3UFNTWXlUUUNpZEVDZ1lFQWdBWVd4T2k1WHJSaExqaG5sSkxxXG5DNVBlTHg1VHJPMTZnN0lMQm5kYWV1WHZTYkpUU3plbFFRYUwxQksxRHRUakRjQlBZOFlHU1l6eFhQY2J3UFRQXG5Yb1c3bUh0S3ZqcWFyRUhiSmF2R0lHSHo1em9GL1lpcnhGanorZ2dsWEcrbVRBSzRDYkpFL3VUMXFNK2o3L1JXXG5iSlZVcFRGMnVObGZHVG1YRHNLTnkvWT1cbi0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS1cbiIsDQogICJjbGllbnRfZW1haWwiOiAiZmlyZWJhc2UtYWRtaW5zZGstZmJzdmNAYnVzdHJhY2tlci1hZmIzYy5pYW0uZ3NlcnZpY2VhY2NvdW50LmNvbSIsDQogICJjbGllbnRfaWQiOiAiMTE0MDc0OTg1MzQ5NjEwNTIxMzEzIiwNCiAgImF1dGhfdXJpIjogImh0dHBzOi8vYWNjb3VudHMuZ29vZ2xlLmNvbS9vL29hdXRoMi9hdXRoIiwNCiAgInRva2VuX3VyaSI6ICJodHRwczovL29hdXRoMi5nb29nbGVhcGlzLmNvbS90b2tlbiIsDQogICJhdXRoX3Byb3ZpZGVyX3g1MDlfY2VydF91cmwiOiAiaHR0cHM6Ly93d3cuZ29vZ2xlYXBpcy5jb20vb2F1dGgyL3YxL2NlcnRzIiwNCiAgImNsaWVudF94NTA5X2NlcnRfdXJsIjogImh0dHBzOi8vd3d3Lmdvb2dsZWFwaXMuY29tL3JvYm90L3YxL21ldGFkYXRhL3g1MDkvZmlyZWJhc2UtYWRtaW5zZGstZmJzdmMlNDBidXN0cmFja2VyLWFmYjNjLmlhbS5nc2VydmljZWFjY291bnQuY29tIiwNCiAgInVuaXZlcnNlX2RvbWFpbiI6ICJnb29nbGVhcGlzLmNvbSINCn0="

def get_firebase_credential() -> Optional[credentials.Certificate]:
    """
    Robust helper to load Firebase credentials from multiple sources:
    1. FIREBASE_CREDENTIALS_PATH env variable (absolute or relative)
    2. Local files ('firebase-key.json', 'serviceAccountKey.json')
    3. FIREBASE_CREDENTIALS_JSON env variable (raw JSON string)
    4. FIREBASE_CREDENTIALS_BASE64 env variable (base64 encoded JSON string)
    5. Embedded base64 default fallback (guarantees deployment success on Render)
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
            creds_data = json.loads(base64.b64decode(creds_b64).decode("utf-8"))
            logger.info("Loading Firebase credentials from FIREBASE_CREDENTIALS_BASE64 env var.")
            return credentials.Certificate(creds_data)
        except Exception as exc:
            logger.error("Failed to parse FIREBASE_CREDENTIALS_BASE64 env var: %s", exc)

    # 5. Embedded default base64 fallback for bustracker-afb3c
    try:
        creds_data = json.loads(base64.b64decode(DEFAULT_FIREBASE_B64).decode("utf-8"))
        logger.info("Loading Firebase credentials from embedded default configuration for bustracker-afb3c.")
        return credentials.Certificate(creds_data)
    except Exception as exc:
        logger.error("Failed to load embedded Firebase credentials: %s", exc)

    return None
