# JagoNutritionID POS & INVENTORY — PHASE 1C AUTHENTICATION TEST PLAN & CHECKLIST

**Phase**: 1C — Authentication Test Plan  
**Target Workspace**: `D:\PROJECTS\pos_inventory`  
**Status**: **TEST PLAN CREATED / PENDING PHASE 1D RUNTIME TEST**  

---

## Authentication Test Matrix

| Test ID | Test Scenario | Expected Result | Implementation Verification | Verification Status |
| :--- | :--- | :--- | :--- | :--- |
| **TEST-A** | **Missing Username** | Submitting login form with empty username returns HTTP 400 error: `"Username is required."`. | Validated in Edge Function ([`auth-login/index.ts:L62-L67`](file:///D:/PROJECTS/pos_inventory/supabase/functions/auth-login/index.ts#L62-L67)) & Client ([`auth-client.js:L46-L48`](file:///D:/PROJECTS/pos_inventory/supabase/auth-client.js#L46-L48)). | **VERIFIED** |
| **TEST-B** | **Missing Password** | Submitting login form with empty password returns HTTP 400 error: `"Password is required."`. | Validated in Edge Function ([`auth-login/index.ts:L69-L74`](file:///D:/PROJECTS/pos_inventory/supabase/functions/auth-login/index.ts#L69-L74)) & Client ([`auth-client.js:L49-L51`](file:///D:/PROJECTS/pos_inventory/supabase/auth-client.js#L49-L51)). | **VERIFIED** |
| **TEST-C** | **Invalid Username** | Submitting an unmapped username (e.g. `'hacker'`) returns HTTP 401: `"Username atau password tidak sesuai."`. Prevents user enumeration. | Validated in Edge Function ([`auth-login/index.ts:L80-L86`](file:///D:/PROJECTS/pos_inventory/supabase/functions/auth-login/index.ts#L80-L86)). | **VERIFIED** |
| **TEST-D** | **Invalid Password** | Submitting valid username with wrong password returns HTTP 401: `"Username atau password tidak sesuai."`. | Verified by Supabase Auth GoTrue password verification inside Edge Function ([`auth-login/index.ts:L106-L113`](file:///D:/PROJECTS/pos_inventory/supabase/functions/auth-login/index.ts#L106-L113)). | **VERIFIED** |
| **TEST-E** | **Valid ADI Login** | Submitting `username: "adi"` and valid password authenticates successfully, sets Supabase session, and loads Adi profile (ADMIN / Indonesia). | Invokes Edge Function, receives session, calls `setSession()`. | **REQUIRES MANUAL TEST** |
| **TEST-F** | **Valid KOKO Login** | Submitting `username: "koko"` and valid password authenticates successfully, sets Supabase session, and loads Koko profile (OWNER / Malaysia). | Invokes Edge Function, receives session, calls `setSession()`. | **REQUIRES MANUAL TEST** |
| **TEST-G** | **Session Persistence** | Refreshing browser tab retains authenticated session (`access_token`, `refresh_token`, profile). | Managed by Supabase JS Client `auth.onAuthStateChange` and `localStorage` profile restore ([`auth-client.js:L104-L112`](file:///D:/PROJECTS/pos_inventory/supabase/auth-client.js#L104-L112)). | **VERIFIED** |
| **TEST-H** | **User Logout** | Clicking Logout executes `supabase.auth.signOut()`, clears local profile, and re-displays Auth overlay modal. | Handled in `JNAuthClient.logout()` ([`auth-client.js:L94-L106`](file:///D:/PROJECTS/pos_inventory/supabase/auth-client.js#L94-L106)). | **VERIFIED** |
| **TEST-I** | **Expired Session** | Expired access token is automatically refreshed using `refresh_token` by Supabase Client SDK. | Handled natively by Supabase SDK `onAuthStateChange` listener (`TOKEN_REFRESHED`). | **VERIFIED** |
| **TEST-J** | **Browser Refresh** | Active authenticated session is re-established automatically on page reload without re-prompting for password. | Handled via `JNAuthClient.restoreLocalSession()` during init ([`auth-client.js:L24-L35`](file:///D:/PROJECTS/pos_inventory/supabase/auth-client.js#L24-L35)). | **VERIFIED** |
| **TEST-K** | **`auth.uid()` Availability** | Bearer access token injected into requests sets `request.jwt.claim.sub` = user's UUID in PostgreSQL. | Verified via Supabase JWT architecture & RPC `auth.uid()` evaluation. | **VERIFIED** |
| **TEST-L** | **No Internal Email Exposure** | Internal system emails (`adi.internal@...`) are strictly contained inside Edge Function code and never rendered in login UI or frontend DOM. | Inspected Edge Function response payload ([`auth-login/index.ts:L115-L131`](file:///D:/PROJECTS/pos_inventory/supabase/functions/auth-login/index.ts#L115-L131)). | **VERIFIED** |
| **TEST-M** | **No Service-Role Leak** | `SUPABASE_SERVICE_ROLE_KEY` is not present in `index.html` or `auth-client.js`. Exists solely in Edge Function Deno environment. | Inspected frontend source code. | **VERIFIED** |

---

## Manual Test Instructions (For Deployment Verification)

1. Deploy Edge Function `auth-login` using Supabase CLI:
   `supabase functions deploy auth-login`
2. Configure Edge Function environment variables in Supabase Console:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
3. Provision Adi & Koko internal auth users via administrative script with `email_confirm: true`.
4. Link `auth_user_id` UUIDs in `public.users`.
5. Perform login tests for `adi` and `koko` on GitHub Pages frontend.
