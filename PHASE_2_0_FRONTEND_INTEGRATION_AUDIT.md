# Phase 2.0 Frontend Integration Audit & Migration Plan

**Phase**: 2.0 — Frontend Integration Audit  
**Target Workspace**: `D:\PROJECTS\pos_inventory`  
**Target File Inspected**: [`index.html`](file:///D:/PROJECTS/pos_inventory/index.html) (3,714 lines)  
**Status**: **READ-ONLY AUDIT COMPLETE / ZERO CODE MODIFIED**  

---

## 1. Overview & Objectives

The goal of Phase 2.0 is to audit the entire existing single-page web application ([`index.html`](file:///D:/PROJECTS/pos_inventory/index.html)) and establish an exact, line-by-line migration plan.

The application is transitioning from a monolithic `localStorage` + JSON blob synchronization model (`prosupps_shared_state` table with last-write-wins resolution) to a secure, relational Supabase PostgreSQL architecture utilizing native Supabase Auth, Row Level Security (RLS), atomic stored procedures (RPCs), and multi-table Supabase Realtime synchronization.

---

## 2. Comprehensive Component Audit & Migration Specifications

### 2.1 Authentication & Session Management
- **Current Lines**: `L1532-L1562`, `L2116-L2218`
- **Current Behavior**:
  - `SYSTEM_ACCOUNTS` constant holds hardcoded user definitions for `adi` and `koko` with precomputed SHA-256 password hashes for default password `"jago2026"`.
  - `handleUserLogin(e)` computes SHA-256 client-side, attempts an unverified Supabase RPC call `authenticate_user`, and falls back to comparing `computedHash === account.passwordHash`.
  - On success, it creates a synthetic session token in `localStorage` under `JN_AUTH_SESSION_KEY`.
- **Target Behavior**:
  - Delegate authentication entirely to `JNAuthClient.login(username, password)` ([`supabase/auth-client.js`](file:///D:/PROJECTS/pos_inventory/supabase/auth-client.js)), which invokes the `auth-login` Edge Function.
  - Receives native JWT `access_token` and `refresh_token`, and calls `supabaseClient.auth.setSession()`.
  - Remove all client-side SHA-256 hashing and hardcoded `SYSTEM_ACCOUNTS` password hashes.
- **Action**: **`REPLACE`**
- **Migration Order**: **Phase 2.1 (Step 1)**

---

### 2.2 Supabase Client & Monolithic Cloud Adapter
- **Current Lines**: `L1593-L1600`, `L1780-L1904`
- **Current Behavior**:
  - `CloudRepository` initializes `window.supabase.createClient(url, anonKey)` from credentials saved in `localStorage`.
  - Monolithic sync fetches and pushes a single JSON blob (`state_data`) to table `prosupps_shared_state` using `upsert({ id: 'primary', state_data: state })`.
  - `subscribeRealtime()` listens to changes on `prosupps_shared_state` and overwrites the full `appState`.
- **Target Behavior**:
  - Remove all references to `prosupps_shared_state` and full-state JSON pushes (`pushState`).
  - Initialize `supabaseClient` at startup using standard project URL (`https://ambtsbakxcktbnuxjpfj.supabase.co`) and publishable key.
  - Bind `JNAuthClient.init(supabaseClient)` to manage auth state changes natively.
- **Action**: **`REPLACE`**
- **Migration Order**: **Phase 2.1 (Step 2)**

---

### 2.3 Inventory Management & Stock Mutation
- **Current Lines**: `L1166-L1219`, `L3081-L3085`, `L3141`, `L3225`
- **Current Behavior**:
  - Hardcoded array `MASTER_PRODUCTS` seeds initial stock levels in memory (`stokAwal`, `masuk`, `keluar`).
  - Physical stock is calculated in JS: `sisaStok = (product.stokAwal + product.masuk) - product.keluar`.
  - Stock mutations occur via in-memory mutations (`product.keluar += qty`, `product.masuk += qty`) followed by full state `saveState()`.
- **Target Behavior**:
  - Load initial products and warehouse stock from `public.products` and `public.inventory` PostgreSQL tables.
  - Display physical stock: `current_stock = initial_stock + total_in - total_out`.
  - Authoritative stock mutations occur strictly on PostgreSQL via atomic RPC functions (`rpc_create_sale`, `rpc_create_restock`, `rpc_void_sale`) enforcing pessimistic row locking (`FOR UPDATE`).
- **Action**: **`REPLACE`**
- **Migration Order**: **Phase 2.2 (Step 3)**

---

### 2.4 Sales Transaction Creation & Deletion
- **Current Lines**: `L3047-L3171`, `L3248-L3283`
- **Current Behavior**:
  - `handleSaleSubmit` generates client-side transaction IDs (`TRX-YYYYMMDD-XXXX`), calculates Shopee discounts, mutates `product.keluar += qty`, and pushes new record to `appState.sales`.
  - `confirmDeleteSale` deletes sales by filtering `appState.sales` array and manually subtracting `product.keluar -= sale.qty`.
- **Target Behavior**:
  - `handleSaleSubmit` invokes `rpc_create_sale` RPC procedure over Supabase Client.
  - Sales deletion is replaced with status-based void accounting via `rpc_void_sale` RPC procedure (`status = 'VOIDED'`), which automatically and atomically restores stock in PostgreSQL.
- **Action**: **`REPLACE`**
- **Migration Order**: **Phase 2.3 (Step 4)**

---

### 2.5 Restock Management
- **Current Lines**: `L3173-L3246`
- **Current Behavior**:
  - `handleRestockSubmit` validates input, mutates `product.masuk += qty`, pushes record to `appState.restockHistory`, and calls `saveState()`.
- **Target Behavior**:
  - `handleRestockSubmit` invokes `rpc_create_restock` RPC procedure over Supabase Client.
- **Action**: **`REPLACE`**
- **Migration Order**: **Phase 2.3 (Step 5)**

---

### 2.6 Audit Logging
- **Current Lines**: `L1700-L1730`, `L2750-L2800`
- **Current Behavior**:
  - `addAuditLog` pushes event objects to in-memory `appState.auditLogs` array and saves to `localStorage`.
- **Target Behavior**:
  - Audit log entries are generated automatically and immutably inside PostgreSQL SECURITY DEFINER RPC functions (`rpc_create_sale`, `rpc_create_restock`, `rpc_void_sale`).
  - Frontend queries `public.audit_logs` for rendering the audit table.
- **Action**: **`REPLACE`**
- **Migration Order**: **Phase 2.4 (Step 6)**

---

### 2.7 Data Persistence & Export/Import
- **Current Lines**: `L1906-L1930`, `L3366-L3427`, `L3429-L3530`
- **Current Behavior**:
  - `ATOMIC_STORAGE_KEY` (`PROSUPPS_STATE_V2.4`) acts as local offline storage and single source of truth when offline.
  - `exportToCSV` exports sales from `appState.sales`.
  - `exportBackupJSON` and `handleImportFileSelected` dump and restore full JSON blobs.
- **Target Behavior**:
  - `localStorage` functions exclusively as a read-only cache and preferences store.
  - `exportToCSV` filters active transactions from `public.sales`.
  - Full-state JSON import/export is disabled or restricted to read-only backup export to prevent database overwrites.
- **Action**: **`MODIFY`**
- **Migration Order**: **Phase 2.4 (Step 7)**

---

### 2.8 Realtime Multi-Table Synchronization
- **Current Lines**: `L1804-L1835`
- **Current Behavior**:
  - Listens to single table `prosupps_shared_state` via WebSocket.
- **Target Behavior**:
  - Subscribe to Supabase Realtime channels across PostgreSQL tables: `products`, `inventory`, `sales`, `restock_history`, and `audit_logs`.
  - On Postgres change event (`INSERT`, `UPDATE`), update only the relevant local entity array and refresh UI.
- **Action**: **`REPLACE`**
- **Migration Order**: **Phase 2.5 (Step 8)**

---

### 2.9 Roles & UI Permissions
- **Current Lines**: `L1534-L1555`, `L3251`
- **Current Behavior**:
  - UI checks `currentUser.role` (`ADMIN` or `OWNER`) to enable/disable specific buttons (e.g., delete transaction).
- **Target Behavior**:
  - Retain UI role checks for view rendering.
  - Authoritative role enforcement is guaranteed at the database layer by Row Level Security (RLS) policies and RPC identity derivation (`auth.uid()`).
- **Action**: **`RETAIN`**
- **Migration Order**: **Phase 2.2 (Step 9)**

---

### 2.10 Language & User Profile (i18n)
- **Current Lines**: `L1221-L1529`, `L1950-L2050`
- **Current Behavior**:
  - Complete bilingual translation system (`I18N.id` and `I18N.en`), `t(key)` helper, and `setLanguage()` language switcher.
- **Target Behavior**:
  - Retain 100% without modification.
- **Action**: **`RETAIN`**
- **Migration Order**: **Phase 2.0 (No Change)**

---

### 2.11 Product Master Data Loading
- **Current Lines**: `L1166-L1219`, `L2300-L2400`
- **Current Behavior**:
  - `MASTER_PRODUCTS` array initializes product dropdowns and tables.
- **Target Behavior**:
  - Fetch product definitions from `public.products` JOIN `public.inventory` on app load.
- **Action**: **`REPLACE`**
- **Migration Order**: **Phase 2.2 (Step 10)**

---

### 2.12 Obsolete Architecture Removal Summary

| Obsolete Component | Approximate Lines | Reason for Removal / Bypass | Replacement Component |
| :--- | :--- | :--- | :--- |
| `SYSTEM_ACCOUNTS` | `L1534-L1562` | Contains hardcoded plain password hashes. | `JNAuthClient` Edge Function authentication. |
| Client SHA-256 Hashing | `L2130` | Insecure client-side password evaluation. | Server-side GoTrue authentication. |
| `prosupps_shared_state` Sync | `L1780-L1904` | Monolithic JSON blob push with last-write-wins conflicts. | Relational tables + RPCs + Realtime. |
| Client Stock Mutations | `L3141`, `L3225` | In-memory `keluar += qty` allows race conditions. | PostgreSQL `FOR UPDATE` RPC locks. |
| Hardcoded Sales Deletion | `L3269-L3272` | Array filtering loses transaction audit trail. | `rpc_void_sale` status-based accounting (`VOIDED`). |

---

## 3. Risk & Impact Analysis on Existing UI Features

1. **Dashboard Analytics (`updateDashboard`)**:
   - *Risk*: Calculating gross revenue, net profit, and total items sold from `sales` array must exclude `status = 'VOIDED'` transactions.
   - *Mitigation*: Filter `appState.sales.filter(s => s.status !== 'VOIDED')` before calculating dashboard metrics.
2. **Inventory Stock Status Table (`renderInventoryTable`)**:
   - *Risk*: Inventory view must show accurate current stock.
   - *Mitigation*: Bind stock directly to `current_stock` returned from `public.inventory`.
3. **Shopee Discount & Pricing Tracker (`handleSaleSubmit`)**:
   - *Risk*: Shopee pricing calculations (`shopeeCatalogPrice`, `shopeeNetPrice`, `discountPercent`) must match backend constraint `check_shopee_pricing_rules`.
   - *Mitigation*: Client calculations preserved exactly; parameters passed to `rpc_create_sale`.
4. **Bilingual UI & Mobile Layout**:
   - *Risk*: Zero risk. HTML structure, CSS Tailwind classes, and `I18N` dictionaries remain 100% intact.
5. **CSV Export (`exportToCSV`)**:
   - *Risk*: CSV export should not include voided transactions unless requested.
   - *Mitigation*: Filter active sales (`s.status === 'ACTIVE'`) before generating CSV content.

---

## 4. Phase 2 Sequential Implementation Plan

- **Phase 2.1**: Script & Module Inclusions (Include `supabase/auth-client.js` in `<head>`).
- **Phase 2.2**: Auth Integration (`handleUserLogin` delegating to `JNAuthClient.login()`).
- **Phase 2.3**: Data Loading (`fetchProductsAndInventory`, `fetchSalesHistory`, `fetchRestockHistory`).
- **Phase 2.4**: RPC Mutations (`handleSaleSubmit` → `rpc_create_sale`, `handleRestockSubmit` → `rpc_create_restock`, `confirmDeleteSale` → `rpc_void_sale`).
- **Phase 2.5**: Realtime Multi-Table Subscriptions & UI Polish.

---

## 5. Final Audit Status

- **FILES MODIFIED**: **NONE**
- **SQL EXECUTED**: **NO**
- **SUPABASE FUNCTIONS MODIFIED**: **NO**
- **COMMIT**: **NO**
- **PUSH**: **NO**
