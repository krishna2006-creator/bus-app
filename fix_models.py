f='bus_tracking_backend/database/models.py'
t=open(f,encoding='utf-8').read()
t=t.rstrip()+'\n\n'
t+='''
class LiveLocation(Base):
    __tablename__ = 'live_locations'
    id = Column(Integer, primary_key=True, index=True)
    entity_id = Column(String, nullable=False, index=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    bearing = Column(Float, nullable=True)
    speed = Column(Float, nullable=True)
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

class DeviceToken(Base):
    __tablename__ = 'device_tokens'
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, ForeignKey('users.id'), nullable=False)
    token = Column(String, nullable=False, unique=True)
    platform = Column(String, nullable=True)
    created_at = Column(DateTime, default=func.now())
'''
open(f,'w',encoding='utf-8').write(t)
print('Done - LiveLocation and DeviceToken added')