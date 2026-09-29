# Phase 1D-1 Authentication User Provisioning

**Phase**: 1D-1 — Staging Auth User Provisioning  
**Target Workspace**: `D:\PROJECTS\pos_inventory`  
**Status**: **PROVISIONING SPECIFICATION & ADMINISTRATIVE PROCEDURE PREPARED**  

---

## 1. Objective

The objective of Phase 1D-1 is to define and prepare the exact user identities and administrative provisioning procedures for **JagoNutritionID POS & INVENTORY** without exposing passwords, modifying source code, or committing secrets.

The system requires exactly two internal auth identities corresponding to the application's authorized users:
1. **`adi`** (ADMIN / Indonesia 🇮🇩)
2. **`koko`** (OWNER / Malaysia 🇲🇾)

The login interface remains strictly **Username + Password**. The internal email addresses are backend implementation details used solely by Supabase Auth (GoTrue) and are never exposed to or entered by end users.

---

## 2. User: adi

- **Username**: `adi`
- **Role**: `ADMIN`
- **Country**: `Indonesia`
- **Internal Auth Identity**: `adi.internal@jagonutritionid.system`
- **Auth UUID**: `<ASSIGNED_UPON_DASHBOARD_OR_ADMIN_PROVISIONING>`
- **Email Confirmed**: `true` (`email_confirmed_at` populated immediately)
- **Status**: `READY_FOR_PROVISIONING`

### Provisioning Steps (Supabase Dashboard)
1. Open **Supabase Dashboard** → Select Project → **Authentication** → **Users**.
2. Click **Add User** → **Create User**.
3. Enter Email: `adi.internal@jagonutritionid.system`.
4. Enter Secure Password (set securely by administrator).
5. Ensure **Auto Confirm User?** checkbox is **checked** (`email_confirm: true`).
6. Click **Create User** and record the generated `User UID` (UUID).

---

## 3. User: koko

- **Username**: `koko`
- **Role**: `OWNER`
- **Country**: `Malaysia`
- **Internal Auth Identity**: `koko.internal@jagonutritionid.system`
- **Auth UUID**: `<ASSIGNED_UPON_DASHBOARD_OR_ADMIN_PROVISIONING>`
- **Email Confirmed**: `true` (`email_confirmed_at` populated immediately)
- **Status**: `READY_FOR_PROVISIONING`

### Provisioning Steps (Supabase Dashboard)
1. Open **Supabase Dashboard** → Select Project → **Authentication** → **Users**.
2. Click **Add User** → **Create User**.
3. Enter Email: `koko.internal@jagonutritionid.system`.
4. Enter Secure Password (set securely by administrator).
5. Ensure **Auto Confirm User?** checkbox is **checked** (`email_confirm: true`).
6. Click **Create User** and record the generated `User UID` (UUID).

---

## 4. Administrative Script Provisioning Alternative

If provisioning via Supabase Management Client (Node.js / Deno script), run the following administrative snippet locally with project environment variables:

```typescript
import { createClient } from "@supabase/supabase-js";

const supabaseAdmin = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
  { auth: { autoRefreshToken: false, persistSession: false } }
);

async function provisionUser(email: string, pass: string) {
  // 1. Duplicate Check
  const { data: existingUsers } = await supabaseAdmin.auth.admin.listUsers();
  const existing = existingUsers.users.find(u => u.email === email);
  
  if (existing) {
    console.log(`[EXISTING] ${email} already exists with UUID: ${existing.id}`);
    return existing.id;
  }

  // 2. Create User if Not Found
  const { data, error } = await supabaseAdmin.auth.admin.createUser({
    email: email,
    password: pass,
    email_confirm: true
  });

  if (error) throw error;
  console.log(`[CREATED] ${email} provisioned with UUID: ${data.user.id}`);
  return data.user.id;
}
```

---

## 5. Duplicate Check Procedure

Before creating an account:
1. Search the **Authentication → Users** table for `adi.internal@jagonutritionid.system` and `koko.internal@jagonutritionid.system`.
2. If an identity already exists:
   - Do **NOT** create a duplicate account.
   - Reuse the existing User UUID.
   - Do **NOT** reset the user's password unless explicitly requested by the administrator.

---

## 6. Security Verification Checklist

- [x] **Email Confirmation**: `email_confirm: true` guarantees `email_confirmed_at` is set immediately, preventing auth blocking due to unconfirmed email states.
- [x] **Zero Password Exposure**: No plaintext passwords appear in markdown files, source code, Git history, or console logs.
- [x] **Service Role Key Protection**: `SUPABASE_SERVICE_ROLE_KEY` is never committed to repository files or exposed to browser code.
- [x] **Repository Cleanliness**: No credentials or environment secrets appear in git diff.

---

## 7. Next Step

The next step is **Phase 1D-2: Edge Function Deployment & Live Runtime Authentication Testing**, where the `auth-login` Edge Function will be deployed to Supabase and verified end-to-end against the provisioned Auth users.
