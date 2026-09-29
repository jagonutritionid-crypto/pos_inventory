# Phase 1D-2A Actual Runtime Authentication Test

**Phase**: 1D-2A — Actual Deployment and Runtime Verification  
**Target Workspace**: `D:\PROJECTS\pos_inventory`  
**Target Supabase Project**: `jagonutritionid-pos`  
**Status**: **PENDING SUPABASE CLI ACCESS TOKEN / RUNTIME DEPLOYMENT**  

---

## 1. Project Verification

- **Command Attempted**: `npx supabase projects list`
- **Result**: `AccessTokenRequiredError` (Access token not provided).
- **Status**: **NOT VERIFIED** (Awaiting `SUPABASE_ACCESS_TOKEN` or `npx supabase login`).

---

## 2. Edge Function Deployment

- **Function Name**: `auth-login`
- **Target File**: [`supabase/functions/auth-login/index.ts`](file:///D:/PROJECTS/pos_inventory/supabase/functions/auth-login/index.ts)
- **Deployment Command**: `npx supabase functions deploy auth-login --no-verify-jwt`
- **Status**: **NOT VERIFIED** (Pending CLI authentication).

---

## 3. Invalid Username Test

- **Test**: `POST /functions/v1/auth-login` with `{"username": "unknown-test-user", "password": "invalid-test-password"}`
- **Expected**: `HTTP 401 Unauthorized` (`{"error": "Username atau password tidak sesuai."}`)
- **Status**: **REQUIRES MANUAL TEST**

---

## 4. Wrong Password Test

- **Test**: `POST /functions/v1/auth-login` with `{"username": "adi", "password": "WRONG_PASSWORD"}`
- **Expected**: `HTTP 401 Unauthorized` (`{"error": "Username atau password tidak sesuai."}`)
- **Status**: **REQUIRES MANUAL TEST**

---

## 5. ADI Login

- **Target User**: `adi`
- **Expected UUID**: `11c4289d-4300-407e-a106-b7f384561634`
- **Status**: **REQUIRES MANUAL TEST**

---

## 6. KOKO Login

- **Target User**: `koko`
- **Expected UUID**: `223448d1-8d2b-4770-a5f3-8d44df8497fd`
- **Status**: **REQUIRES MANUAL TEST**

---

## 7. setSession

- **Test**: `supabase.auth.setSession({ access_token, refresh_token })`
- **Status**: **REQUIRES MANUAL TEST**

---

## 8. getUser

- **Test**: `supabase.auth.getUser()`
- **Status**: **REQUIRES MANUAL TEST**

---

## 9. Logout

- **Test**: `supabase.auth.signOut()`
- **Status**: **REQUIRES MANUAL TEST**

---

## 10. Browser Reload

- **Test**: Session restoration on page reload via `onAuthStateChange`
- **Status**: **REQUIRES MANUAL TEST**

---

## 11. Rate Limit

- **Test**: Controlled series of invalid authentication attempts to observe GoTrue rate-limit headers
- **Status**: **UNVERIFIED**

---

## 12. Internal Identity Leakage

- **Test**: Confirm `adi.internal@jagonutritionid.system` & `koko.internal@jagonutritionid.system` are not exposed in browser HTTP responses
- **Status**: **VERIFIED** (By code inspection of `auth-login/index.ts` response payload)

---

## 13. Secret Exposure

- **Test**: Confirm `SUPABASE_SERVICE_ROLE_KEY` is not present in frontend code or Edge Function source
- **Status**: **VERIFIED** (Absent from `auth-login/index.ts` and `auth-client.js`)

---

## 14. Final Result

### **UNVERIFIED**

**Reason**: Supabase CLI deployment requires active authentication via `SUPABASE_ACCESS_TOKEN` or `npx supabase login`. Runtime HTTP tests cannot be executed until the Edge Function is live on Supabase Cloud.
