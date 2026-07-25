-- 1. Create a table for all college bus stops
CREATE TABLE stops (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL, -- e.g., "T Nagar", "Velachery"
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(10, 8) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. Link buses to stops with a sequence (Order matters for ETA)
CREATE TABLE route_stops (
    id INT AUTO_INCREMENT PRIMARY KEY,
    bus_id INT NOT NULL,
    stop_id INT NOT NULL,
    stop_sequence INT NOT NULL, -- 1 for first stop, 2 for second...
    avg_time_from_start INT, -- Historical average minutes from start
    FOREIGN KEY (bus_id) REFERENCES buses(id),
    FOREIGN KEY (stop_id) REFERENCES stops(id)
);

-- 3. Seed some sample data
INSERT INTO stops (name, latitude, longitude) VALUES 
('T Nagar', 13.0418, 80.2341),
('Velachery', 12.9815, 80.2180),
('Agni College', 12.9716, 77.5946); -- Replace with actual college coords

-- Link Bus 1 to T Nagar (Stop 1) and College (Stop 2)
INSERT INTO route_stops (bus_id, stop_id, stop_sequence, avg_time_from_start) VALUES (1, 1, 1, 0), (1, 3, 2, 45);