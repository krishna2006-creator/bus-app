import os, sys, json
from pathlib import Path

output = []

env_path = Path(__file__).parent / ".env"
output.append(f"ENV EXISTS: {env_path.exists()}")

if env_path.exists():
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                os.environ[key.strip()] = val.strip()

creds_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
output.append(f"FIREBASE_CREDENTIALS_PATH: {repr(creds_path)}")
output.append(f"FCM_PROJECT_ID: {repr(os.getenv('FCM_PROJECT_ID'))}")
output.append(f"FCM_SENDER_ID: {repr(os.getenv('FCM_SENDER_ID'))}")

p = Path(creds_path) if creds_path else None
output.append(f"CREDS PATH EXISTS: {p.exists() if p else 'NO PATH'}")

if p and p.exists():
    d = json.load(open(p))
    output.append(f"PROJECT IN CREDS: {d.get('project_id')}")
    output.append(f"CLIENT EMAIL: {d.get('client_email')}")

# Now try firebase init
import firebase_admin
from firebase_admin import credentials, messaging
output.append("firebase_admin imported")

try:
    firebase_admin.get_app()
    output.append("Firebase already initialized.")
except ValueError:
    try:
        cred = credentials.Certificate(creds_path)
        app = firebase_admin.initialize_app(cred)
        output.append("Firebase initialized successfully!")
        output.append(f"App name: {app.name}")
        output.append(f"Project ID: {app.project_id}")
        output.append("Messaging module loaded.")
    except Exception as exc:
        output.append(f"Firebase initialization FAILED: {exc}")

# Write to file
result_path = Path(__file__).parent / "diag_result.txt"
with open(result_path, "w") as f:
    f.write("\n".join(output))

print("\n".join(output))
