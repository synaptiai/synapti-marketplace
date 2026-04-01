# Implementation Plan: User Authentication

## Phase 1: API Integration
Set up OAuth2 authentication using Auth0 as the identity provider.

**Verified:** Auth0 supports PKCE flow (confirmed via https://auth0.com/docs/get-started/authentication-and-authorization-flow/authorization-code-flow-with-pkce).
**Verified:** Redirect URI configuration available in Auth0 dashboard under Application Settings > Allowed Callback URLs.

**Acceptance criteria:**
- Auth0 tenant created and configured with PKCE-enabled application
- `/api/auth/callback` endpoint receives and validates authorization code
- Token exchange returns valid access_token and id_token (verified by decoding JWT and checking `iss`, `aud`, `exp` claims)

**Verification:** Runtime test — complete OAuth flow in browser, inspect network tab for token exchange, decode JWT to verify claims.

## Phase 2: Frontend Components
Build login form with email/password fields and "Sign in with Auth0" button. Registration page with email, password, confirm password, and terms checkbox.

**Acceptance criteria:**
- Login form submits credentials to `/api/auth/login` and redirects to dashboard on 200 response
- Registration form validates: email format, password minimum 8 chars with 1 uppercase + 1 number, passwords match, terms checked
- Error states: inline validation messages for each field, server error banner for 4xx/5xx responses
- Empty state: form fields show placeholder text, submit button disabled until all required fields filled

**Verification:** Browser testing — submit valid and invalid inputs, verify error messages appear correctly, test with JavaScript disabled.

## Phase 3: Session Management
Use Redis for session storage (server-side sessions, not client-side tokens).

**Dependency:** Redis must be running before this phase. Install via `brew install redis` or use Docker: `docker run -d -p 6379:6379 redis:7`.

**Acceptance criteria:**
- Session created on login with 24-hour TTL in Redis
- Session ID stored in httpOnly, secure, sameSite=strict cookie
- `/api/auth/me` returns user profile when valid session exists, 401 when expired/missing
- Logout endpoint destroys Redis session and clears cookie

**Verification:** Runtime test — login, verify Redis key exists (`redis-cli KEYS "sess:*"`), wait for TTL or manually delete, verify 401 on next request.

## Phase 4: Deployment
Deploy to staging environment.

**Dependency:** Phase 3 must be complete (session management requires Redis, which must be configured in staging environment).
**Dependency:** Database migration `20240115_add_users_table.sql` must run before app startup — migration is idempotent (uses `CREATE TABLE IF NOT EXISTS`).
**Risk:** If Redis is unavailable in staging, sessions will fail silently. **Mitigation:** Add health check endpoint that verifies Redis connectivity; fail deployment if health check returns unhealthy.

**Acceptance criteria:**
- Staging deployment completes without errors
- Health check endpoint returns 200 with `{"redis": "connected", "database": "connected"}`
- Full OAuth flow works end-to-end in staging (login, session, logout)

**Verification:** End-to-end browser test in staging — complete full auth flow, verify session in Redis, logout, verify session destroyed.

## Tasks
1. [ ] Configure Auth0 tenant and PKCE application
2. [ ] Implement `/api/auth/callback` and token exchange
3. [ ] Build login form with validation
4. [ ] Build registration form with validation
5. [ ] Set up Redis and implement session middleware
6. [ ] Implement logout endpoint
7. [ ] Add health check endpoint
8. [ ] Write database migration
9. [ ] Deploy to staging and run E2E verification
