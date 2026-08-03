cd /d c:\busappvictory
git add -A
git commit -m "fix: resolve column users.custom_boarding_lat does not exist (login/register 500 error)

Add robust schema migration utility with retry logic + startup event handler.
- New migrations.py: ensure_schema_columns() with 3 retries, ensure_user_columns_safe() per-request self-heal
- main.py: _ensure_columns() delegates to robust utility; @app.on_event('startup') re-checks after app init
- auth_utils.py: authenticate_user() catches ProgrammingError, self-heals, retries
- services/auth.py: register() same self-healing pattern
- init_db.py, init_postgres.py: use ensure_schema_columns() instead of inline ALTER TABLE"
git push
pause
