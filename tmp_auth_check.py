from bus_tracking_backend.utils.auth_utils import get_current_user
from bus_tracking_backend.database.database import SessionLocal

db = SessionLocal()
token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMjAwNiIsImV4cCI6MTc4Mzc2NTkyM30.nnDz5lg90pUrfUi67AGejeK2_kHCP5u81xutsSwWYHQ'
try:
    user = get_current_user(token, db)
    print('USER', user.id, user.role)
except Exception as e:
    print(type(e).__name__, e)
finally:
    db.close()
