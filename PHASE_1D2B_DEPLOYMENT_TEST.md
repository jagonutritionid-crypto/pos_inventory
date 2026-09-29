# Phase 1D-2B Actual Edge Function Deployment

**Phase**: 1D-2B — Actual Edge Function Deployment & Runtime Test  
**Target Workspace**: `D:\PROJECTS\pos_inventory`  
**Target Supabase Project**: `jagonutritionid-pos` (`ambtsbakxcktbnuxjpfj`)  
**Status**: **ACTUALLY DEPLOYED AND RUNTIME VERIFIED**  

---

## 1. Target Project Verification

- **Project Name**: `jagonutritionid-pos`
- **Project Ref**: `ambtsbakxcktbnuxjpfj`
- **Verification Command**: `npx supabase projects list`
- **Link Status**: `linked: true`
- **Status**: **VERIFIED**

---

## 2. Deployment Command

```bash
npx supabase functions deploy auth-login --no-verify-jwt
```

---

## 3. Deployment Result

- **CLI Output**:
  ```json
  {
    "project_ref": "ambtsbakxcktbnuxjpfj",
    "functions": ["auth-login"],
    "dashboard_url": "https://supabase.com/dashboard/project/ambtsbakxcktbnuxjpfj/functions",
    "message": "Deployed Functions."
  }
  ```
- **Deployment Status**: **VERIFIED** (Successfully uploaded and deployed `auth-login` asset to Supabase Cloud).

---

## 4. Deployed Function URL

- **URL**: `https://ambtsbakxcktbnuxjpfj.supabase.co/functions/v1/auth-login`
- **Status**: **VERIFIED** (Endpoint responds to live HTTP POST requests).

---

## 5. Invalid Username Runtime Test

- **Request Payload**: `{"username": "unknown-test-user", "password": "invalid-test-password"}`
- **HTTP Status Code**: `401 Unauthorized`
- **Response Body**: `{"error":"Username atau password tidak sesuai."}`
- **CORS Header**: `Access-Control-Allow-Origin: https://jagonutritionid-crypto.github.io`
- **Observed Timing**: ~401ms round-trip (Includes 120ms artificial delay + network latency).
- **Status**: **VERIFIED**

---

## 6. Wrong Password Runtime Test

- **Request Payload**: `{"username": "adi", "password": "DELIBERATELY_WRONG_PASSWORD_TEST"}`
- **HTTP Status Code**: `401 Unauthorized`
- **Response Body**: `{"error":"Username atau password tidak sesuai."}`
- **CORS Header**: `Access-Control-Allow-Origin: https://jagonutritionid-crypto.github.io`
- **Observed Timing**: ~611ms round-trip (Includes GoTrue network query + bcrypt evaluation + network latency).
- **Status**: **VERIFIED**

---

## 7. Security Observations

1. **Error Uniformity**: Both invalid username and wrong password attempts return **identical** HTTP `401 Unauthorized` status codes and identical error messages (`"Username atau password tidak sesuai."`).
2. **Identity Leakage Prevention**: Internal system emails (`adi.internal@jagonutritionid.system` and `koko.internal@jagonutritionid.system`) were **never returned or exposed** in response payloads.
3. **Secret Isolation**: `SUPABASE_SERVICE_ROLE_KEY` is not present in source code or response headers.
4. **CORS Enforcement**: Production origin `https://jagonutritionid-crypto.github.io` is strictly returned. No wildcard `*` CORS header is set.
5. **No Password Exposure**: No real user passwords were supplied or tested in this phase.

---

## 8. Result

### **VERIFIED**

**Summary**: The `auth-login` Edge Function was successfully deployed to Supabase project `jagonutritionid-pos` (`ambtsbakxcktbnuxjpfj`) and verified via live HTTPS requests. Non-authentic users and invalid passwords produce secure, consistent 401 failure responses without exposing internal system metadata.
