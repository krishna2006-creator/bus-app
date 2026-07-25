# Production plan for the bus tracking app

## Roles
- admin
- staff
- student
- driver

## Core requirements
- Authentication with role-based access
- Live location sharing from drivers
- Real-time viewing for students/staff/admin
- Push-style notifications through WebSocket and local notifications
- Admin controls for buses, routes, users, and announcements

## Backend stack
- FastAPI
- SQLAlchemy
- SQLite for local development, PostgreSQL for production
- WebSockets for real-time location updates
- Firebase Cloud Messaging for push notifications in production

## Next steps
1. Connect a real PostgreSQL database.
2. Add Firebase Cloud Messaging token registration.
3. Deploy the backend behind HTTPS.
4. Test driver-to-student live tracking on real devices.
