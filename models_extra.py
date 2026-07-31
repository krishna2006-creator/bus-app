class BusStop(Base):  
    __tablename__ = 'bus_stops'  
    id = Column(Integer, primary_key=True, index=True)  
    bus_id = Column(Integer, ForeignKey('buses.id'), nullable=True)  
    name = Column(String, nullable=False)  
    latitude = Column(Float, nullable=False)  
    longitude = Column(Float, nullable=False)  
    order = Column(Integer, default=0)  
    bus = relationship('Bus', back_populates='stops')  
  
