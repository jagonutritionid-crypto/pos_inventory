-- ==============================================================================
-- JAGO NUTRITION ID POS & INVENTORY — PHASE 1A DATABASE MIGRATION (FINAL HARDENED PASS)
-- File: supabase/migrations/001_initial_schema.sql
-- Status: DRAFT / NOT EXECUTED (FOR REVIEW AND HUMAN APPROVAL ONLY)
-- Author: Advanced Agentic AI Coding Assistant
-- ==============================================================================

-- Enable required PostgreSQL extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 1. USERS TABLE
-- Stores system users (Adi - ADMIN / Indonesia, Koko - OWNER / Malaysia)
-- Maps to Supabase auth.users via nullable FK auth_user_id for authentic security
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username VARCHAR(50) UNIQUE NOT NULL,
  auth_user_id UUID UNIQUE NULL REFERENCES auth.users(id) ON DELETE SET NULL, -- Nullable FK to auth.users for Supabase Auth compatibility
  name VARCHAR(100) NOT NULL,
  role VARCHAR(20) NOT NULL CHECK (role IN ('OWNER', 'ADMIN')),
  country VARCHAR(50) NOT NULL CHECK (country IN ('Indonesia', 'Malaysia')),
  country_code VARCHAR(2) NOT NULL CHECK (country_code IN ('ID', 'MY')),
  default_language VARCHAR(2) NOT NULL DEFAULT 'id' CHECK (default_language IN ('id', 'en')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==============================================================================
-- 2. PRODUCTS MASTER TABLE
-- Stores product definitions, prices, HPPs, and buffer configuration
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.products (
  id VARCHAR(50) PRIMARY KEY, -- SKU identifier (e.g. WHEY-ISO-DC)
  sku VARCHAR(50) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  category VARCHAR(100) NOT NULL DEFAULT 'Supplement',
  size VARCHAR(50) NOT NULL,
  sale_price NUMERIC(15, 2) NOT NULL CHECK (sale_price >= 0),
  shopee_catalog_price NUMERIC(15, 2) NOT NULL CHECK (shopee_catalog_price >= 0),
  hpp NUMERIC(15, 2) NOT NULL CHECK (hpp >= 0),
  initial_stock INT NOT NULL DEFAULT 0 CHECK (initial_stock >= 0),
  min_buffer INT NOT NULL DEFAULT 5 CHECK (min_buffer >= 0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==============================================================================
-- 3. INVENTORY STATE TABLE
-- Maintains physical stock level with DB-enforced CHECK (current_stock >= 0)
-- Guaranteed Invariant: current_stock = initial_stock + total_in - total_out
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.inventory (
  product_id VARCHAR(50) PRIMARY KEY REFERENCES public.products(id) ON DELETE RESTRICT,
  initial_stock INT NOT NULL DEFAULT 0 CHECK (initial_stock >= 0),
  total_in INT NOT NULL DEFAULT 0 CHECK (total_in >= 0),
  total_out INT NOT NULL DEFAULT 0 CHECK (total_out >= 0),
  current_stock INT NOT NULL CHECK (current_stock >= 0), -- HARD DB OVERSELLING GUARD
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==============================================================================
-- 4. SALES TRANSACTIONS TABLE
-- Preserves immutable historical snapshots of prices, HPPs, and Shopee discounts.
-- Implements Status-based Accounting (ACTIVE / VOIDED) for full ledger auditability.
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.sales (
  id VARCHAR(50) PRIMARY KEY, -- TRX-YYYYMMDD-XXXX
  date DATE NOT NULL,
  channel VARCHAR(50) NOT NULL CHECK (channel IN ('Shopee', 'Store / Offline', 'Tokopedia', 'TikTok Shop', 'WhatsApp')),
  product_id VARCHAR(50) NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  product_name VARCHAR(255) NOT NULL, -- Historical Snapshot
  sku VARCHAR(50) NOT NULL,          -- Historical Snapshot
  qty INT NOT NULL CHECK (qty > 0),
  unit_price NUMERIC(15, 2) NOT NULL CHECK (unit_price >= 0),
  unit_hpp NUMERIC(15, 2) NOT NULL CHECK (unit_hpp >= 0), -- Historical Snapshot
  shopee_catalog_price NUMERIC(15, 2) NULL CHECK (shopee_catalog_price IS NULL OR shopee_catalog_price >= 0),
  shopee_net_price NUMERIC(15, 2) NULL CHECK (shopee_net_price IS NULL OR shopee_net_price >= 0),
  discount NUMERIC(15, 2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
  discount_percent NUMERIC(5, 2) NOT NULL DEFAULT 0 CHECK (discount_percent >= 0 AND discount_percent <= 100),
  gross_total NUMERIC(15, 2) NOT NULL CHECK (gross_total >= 0),
  net_total NUMERIC(15, 2) NOT NULL CHECK (net_total >= 0),
  profit NUMERIC(15, 2) NOT NULL,
  payment_method VARCHAR(50) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'VOIDED')), -- VOIDED ACCOUNTING
  voided_at TIMESTAMPTZ NULL,
  voided_by VARCHAR(100) NULL,
  void_reason TEXT NULL,
  voided_by_user_id UUID NULL REFERENCES public.users(id) ON DELETE SET NULL,
  created_by VARCHAR(100) NOT NULL,
  user_id UUID NULL REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT check_shopee_pricing_rules CHECK (
    (channel = 'Shopee' AND shopee_catalog_price IS NOT NULL AND shopee_net_price IS NOT NULL AND shopee_net_price <= shopee_catalog_price AND shopee_net_price > 0) OR
    (channel <> 'Shopee')
  )
);

-- ==============================================================================
-- 5. RESTOCK HISTORY TABLE
-- Ledger of inbound goods added to warehouse stock
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.restock_history (
  id VARCHAR(50) PRIMARY KEY, -- RST-YYYYMMDD-XXXX
  product_id VARCHAR(50) NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  product_name VARCHAR(255) NOT NULL,
  qty INT NOT NULL CHECK (qty > 0),
  date DATE NOT NULL,
  note TEXT NULL,
  created_by VARCHAR(100) NOT NULL,
  user_id UUID NULL REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==============================================================================
-- 6. AUDIT LOGS TABLE
-- Immutable append-only audit trail for security and accountability
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id VARCHAR(100) PRIMARY KEY, -- AUD-TIMESTAMP-RANDOM
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_id VARCHAR(100) NOT NULL,
  user_name VARCHAR(100) NOT NULL,
  user_role VARCHAR(50) NOT NULL,
  user_country VARCHAR(50) NOT NULL,
  action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(100) NOT NULL,
  entity_id VARCHAR(100) NOT NULL,
  details TEXT NULL
);

-- ==============================================================================
-- 7. INDEXES FOR PERFORMANCE OPTIMIZATION
-- ==============================================================================
CREATE INDEX IF NOT EXISTS idx_sales_date ON public.sales(date);
CREATE INDEX IF NOT EXISTS idx_sales_channel ON public.sales(channel);
CREATE INDEX IF NOT EXISTS idx_sales_product_id ON public.sales(product_id);
CREATE INDEX IF NOT EXISTS idx_sales_status ON public.sales(status);
CREATE INDEX IF NOT EXISTS idx_restock_product_id ON public.restock_history(product_id);
CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON public.audit_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_products_active ON public.products(is_active);
CREATE INDEX IF NOT EXISTS idx_users_auth_id ON public.users(auth_user_id);

-- ==============================================================================
-- 8. INITIAL MASTER DATA SEEDING (IDEMPOTENT & EXACT DATA PRESERVATION)
-- ==============================================================================

-- Seed Logical Users
INSERT INTO public.users (username, name, role, country, country_code, default_language)
VALUES 
  ('adi', 'Adi', 'ADMIN', 'Indonesia', 'ID', 'id'),
  ('koko', 'Koko', 'OWNER', 'Malaysia', 'MY', 'en')
ON CONFLICT (username) DO UPDATE SET
  name = EXCLUDED.name,
  role = EXCLUDED.role,
  country = EXCLUDED.country,
  country_code = EXCLUDED.country_code,
  default_language = EXCLUDED.default_language;

-- Seed Product Master (4 SKUs - Total Initial Stock = 28)
INSERT INTO public.products (id, sku, name, category, size, sale_price, shopee_catalog_price, hpp, initial_stock, min_buffer)
VALUES
  ('WHEY-ISO-DC', 'WHEY-ISO-DC', 'Whey Hydro Isolate - Dutch Chocolate', 'Protein Powder', '1 kg', 549250, 650000, 380000, 12, 5),
  ('WHEY-ISO-CC', 'WHEY-ISO-CC', 'Whey Hydro Isolate - Cookies & Cream', 'Protein Powder', '1 kg', 549250, 650000, 380000, 5, 5),
  ('WHEY-ISO-ML', 'WHEY-ISO-ML', 'Whey Hydro Isolate - Mocha Latte', 'Protein Powder', '1 kg', 549250, 650000, 380000, 5, 5),
  ('CREA-MP-300', 'CREA-MP-300', 'MonoPure 100% Creatine Monohydrate', 'Creatine', '300 g', 350000, 450000, 210000, 6, 5)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  size = EXCLUDED.size,
  sale_price = EXCLUDED.sale_price,
  shopee_catalog_price = EXCLUDED.shopee_catalog_price,
  hpp = EXCLUDED.hpp,
  min_buffer = EXCLUDED.min_buffer;

-- Seed Inventory Initial State (Matches Physical Warehouse Stock)
INSERT INTO public.inventory (product_id, initial_stock, total_in, total_out, current_stock)
VALUES
  ('WHEY-ISO-DC', 12, 0, 0, 12),
  ('WHEY-ISO-CC', 5, 0, 0, 5),
  ('WHEY-ISO-ML', 5, 0, 0, 5),
  ('CREA-MP-300', 6, 0, 0, 6)
ON CONFLICT (product_id) DO NOTHING;

-- ==============================================================================
-- 9. HARDENED ROW LEVEL SECURITY (RLS) POLICIES
-- Zero USING (true) or WITH CHECK (true) for anon/public role.
-- All access strictly locked to authenticated sessions.
-- ==============================================================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restock_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- RLS POLICIES FOR AUTHENTICATED USERS (READ ACCESS)
-- ------------------------------------------------------------------------------
CREATE POLICY "Authenticated users can select products" 
  ON public.products FOR SELECT TO authenticated
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can select inventory" 
  ON public.inventory FOR SELECT TO authenticated
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can select sales" 
  ON public.sales FOR SELECT TO authenticated
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can select restock_history" 
  ON public.restock_history FOR SELECT TO authenticated
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can select audit_logs" 
  ON public.audit_logs FOR SELECT TO authenticated
  USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can select users profile" 
  ON public.users FOR SELECT TO authenticated
  USING (auth.role() = 'authenticated');

-- Note: No direct INSERT/UPDATE/DELETE policies are granted on sales, inventory, or restock_history for clients.
-- All sensitive mutations MUST be executed via atomic SECURITY DEFINER RPC functions.

-- ==============================================================================
-- 10. HARDENED ATOMIC STORED PROCEDURES (RPCs)
-- - Fixed search_path = public, pg_temp
-- - Derived user identity from auth.uid() -> public.users.auth_user_id
-- - Strict locks on inventory & sales rows
-- - Explicit REVOKE EXECUTE FROM PUBLIC, anon
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- RPC 1: ATOMIC SALE CREATION WITH OVERSELLING LOCK & AUDIT
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_create_sale(
  p_id VARCHAR,
  p_date DATE,
  p_channel VARCHAR,
  p_product_id VARCHAR,
  p_qty INT,
  p_unit_price NUMERIC,
  p_shopee_catalog_price NUMERIC,
  p_shopee_net_price NUMERIC,
  p_discount NUMERIC,
  p_payment_method VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user RECORD;
  v_product RECORD;
  v_current_stock INT;
  v_gross_total NUMERIC;
  v_net_total NUMERIC;
  v_discount_pct NUMERIC;
  v_profit NUMERIC;
  v_audit_id VARCHAR;
BEGIN
  -- 1. Verify Authenticated Session (PHASE 1B AUTH REQUIREMENT)
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Access Denied: Authentication required.';
  END IF;

  SELECT * INTO v_user 
  FROM public.users 
  WHERE auth_user_id = auth.uid() AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Access Denied: Valid user profile not found for active session.';
  END IF;

  -- 2. Fetch Product Master
  SELECT * INTO v_product FROM public.products WHERE id = p_product_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product SKU % not found or inactive.', p_product_id;
  END IF;

  -- 3. Row Locking on Inventory to Prevent Concurrent Race Conditions
  SELECT current_stock INTO v_current_stock 
  FROM public.inventory 
  WHERE product_id = p_product_id 
  FOR UPDATE;

  IF v_current_stock IS NULL OR v_current_stock < p_qty THEN
    RAISE EXCEPTION 'Insufficient stock for SKU %. Available: %, Requested: %', 
      p_product_id, COALESCE(v_current_stock, 0), p_qty;
  END IF;

  -- 4. Calculate Totals & Profit
  v_gross_total := p_unit_price * p_qty;
  v_net_total := v_gross_total - p_discount;
  
  IF v_gross_total > 0 AND p_discount > 0 THEN
    v_discount_pct := ROUND(((p_discount / v_gross_total) * 100)::numeric, 2);
  ELSE
    v_discount_pct := 0;
  END IF;

  v_profit := v_net_total - (v_product.hpp * p_qty);

  -- 5. Deduct Stock Atomically (Preserves Invariant: current_stock = initial_stock + total_in - total_out)
  UPDATE public.inventory
  SET 
    total_out = total_out + p_qty,
    current_stock = current_stock - p_qty,
    updated_at = NOW()
  WHERE product_id = p_product_id;

  -- 6. Record Immutable Sales Snapshot
  INSERT INTO public.sales (
    id, date, channel, product_id, product_name, sku, qty,
    unit_price, unit_hpp, shopee_catalog_price, shopee_net_price,
    discount, discount_percent, gross_total, net_total, profit,
    payment_method, status, created_by, user_id, created_at
  ) VALUES (
    p_id, p_date, p_channel, v_product.id, v_product.name, v_product.sku, p_qty,
    p_unit_price, v_product.hpp, p_shopee_catalog_price, p_shopee_net_price,
    p_discount, v_discount_pct, v_gross_total, v_net_total, v_profit,
    p_payment_method, 'ACTIVE', v_user.name, v_user.id, NOW()
  );

  -- 7. Record Audit Log with Trusted Session User Identity
  v_audit_id := 'AUD-' || EXTRACT(EPOCH FROM NOW())::TEXT || '-' || FLOOR(RANDOM() * 1000)::TEXT;
  INSERT INTO public.audit_logs (
    id, timestamp, user_id, user_name, user_role, user_country,
    action, entity_type, entity_id, details
  ) VALUES (
    v_audit_id, NOW(), v_user.id::TEXT, v_user.name, v_user.role, v_user.country,
    'CREATE_SALE', 'TRANSACTION', p_id,
    'Recorded sale of ' || p_qty || ' pcs ' || v_product.name || ' via ' || p_channel
  );

  RETURN jsonb_build_object('success', true, 'sale_id', p_id, 'remaining_stock', v_current_stock - p_qty);
END;
$$;

-- ------------------------------------------------------------------------------
-- RPC 2: ATOMIC RESTOCK CREATION
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_create_restock(
  p_id VARCHAR,
  p_product_id VARCHAR,
  p_qty INT,
  p_date DATE,
  p_note TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user RECORD;
  v_product RECORD;
  v_current_stock INT;
  v_new_stock INT;
  v_audit_id VARCHAR;
BEGIN
  -- 1. Verify Authenticated Session
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Access Denied: Authentication required.';
  END IF;

  SELECT * INTO v_user 
  FROM public.users 
  WHERE auth_user_id = auth.uid() AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Access Denied: Valid user profile not found for active session.';
  END IF;

  -- 2. Fetch Product Master
  SELECT * INTO v_product FROM public.products WHERE id = p_product_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product SKU % not found or inactive.', p_product_id;
  END IF;

  -- 3. Row Locking on Inventory to Prevent Race Conditions during Concurrent Restocks
  SELECT current_stock INTO v_current_stock
  FROM public.inventory
  WHERE product_id = p_product_id
  FOR UPDATE;

  -- 4. Update Inventory Atomically (Preserves Invariant)
  UPDATE public.inventory
  SET 
    total_in = total_in + p_qty,
    current_stock = current_stock + p_qty,
    updated_at = NOW()
  WHERE product_id = p_product_id
  RETURNING current_stock INTO v_new_stock;

  -- 5. Record Restock Entry
  INSERT INTO public.restock_history (
    id, product_id, product_name, qty, date, note, created_by, user_id, created_at
  ) VALUES (
    p_id, v_product.id, v_product.name, p_qty, p_date, p_note, v_user.name, v_user.id, NOW()
  );

  -- 6. Record Audit Log
  v_audit_id := 'AUD-' || EXTRACT(EPOCH FROM NOW())::TEXT || '-' || FLOOR(RANDOM() * 1000)::TEXT;
  INSERT INTO public.audit_logs (
    id, timestamp, user_id, user_name, user_role, user_country,
    action, entity_type, entity_id, details
  ) VALUES (
    v_audit_id, NOW(), v_user.id::TEXT, v_user.name, v_user.role, v_user.country,
    'RESTOCK', 'PRODUCT', p_product_id,
    'Restocked +' || p_qty || ' pcs ' || v_product.name || ' (' || p_id || ')'
  );

  RETURN jsonb_build_object('success', true, 'restock_id', p_id, 'new_stock', v_new_stock);
END;
$$;

-- ------------------------------------------------------------------------------
-- RPC 3: ATOMIC SALE VOID / REVERSAL (STRICT DATA INTEGRITY & DOUBLE-VOID GUARD)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_void_sale(
  p_sale_id VARCHAR,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user RECORD;
  v_sale RECORD;
  v_current_stock INT;
  v_total_out INT;
  v_new_stock INT;
  v_audit_id VARCHAR;
BEGIN
  -- 1. Verify Authenticated Session
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Access Denied: Authentication required.';
  END IF;

  SELECT * INTO v_user 
  FROM public.users 
  WHERE auth_user_id = auth.uid() AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Access Denied: Valid user profile not found for active session.';
  END IF;

  -- 2. Lock & Fetch Sale Record
  SELECT * INTO v_sale FROM public.sales WHERE id = p_sale_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sale transaction % not found.', p_sale_id;
  END IF;

  -- 3. DOUBLE-VOID GUARD: Ensure transaction is currently ACTIVE
  IF v_sale.status = 'VOIDED' THEN
    RAISE EXCEPTION 'Transaction % has already been voided. Reversal aborted.', p_sale_id;
  END IF;

  -- 4. Lock & Verify Inventory Record Sanity
  SELECT current_stock, total_out INTO v_current_stock, v_total_out
  FROM public.inventory
  WHERE product_id = v_sale.product_id
  FOR UPDATE;

  -- HARD DATA INTEGRITY SANITY CHECK: total_out must be >= v_sale.qty
  IF v_total_out < v_sale.qty THEN
    RAISE EXCEPTION 'Database inconsistency: total_out (%) is less than sale quantity (%) for SKU %. Transaction aborted.',
      v_total_out, v_sale.qty, v_sale.product_id;
  END IF;

  -- 5. Revert Stock Atomically in Inventory (Preserves Invariant)
  UPDATE public.inventory
  SET 
    total_out = total_out - v_sale.qty,
    current_stock = current_stock + v_sale.qty,
    updated_at = NOW()
  WHERE product_id = v_sale.product_id
  RETURNING current_stock INTO v_new_stock;

  -- 6. Mark Sale Status as VOIDED (Preserves historical accounting record)
  UPDATE public.sales
  SET 
    status = 'VOIDED',
    voided_at = NOW(),
    voided_by = v_user.name,
    void_reason = COALESCE(p_reason, 'Transaction voided by user'),
    voided_by_user_id = v_user.id
  WHERE id = p_sale_id;

  -- 7. Record Audit Log
  v_audit_id := 'AUD-' || EXTRACT(EPOCH FROM NOW())::TEXT || '-' || FLOOR(RANDOM() * 1000)::TEXT;
  INSERT INTO public.audit_logs (
    id, timestamp, user_id, user_name, user_role, user_country,
    action, entity_type, entity_id, details
  ) VALUES (
    v_audit_id, NOW(), v_user.id::TEXT, v_user.name, v_user.role, v_user.country,
    'VOID_SALE', 'TRANSACTION', p_sale_id,
    'Voided transaction ' || p_sale_id || ' (' || v_sale.qty || ' pcs ' || v_sale.product_name || '). Reason: ' || COALESCE(p_reason, '-')
  );

  RETURN jsonb_build_object('success', true, 'voided_sale_id', p_sale_id, 'restored_stock', v_new_stock);
END;
$$;

-- ==============================================================================
-- 11. STRICT EXECUTION PRIVILEGE HARDENING
-- Revoke all function execution privileges from PUBLIC and anon roles.
-- Grant execution privileges exclusively to authenticated users.
-- ==============================================================================
REVOKE EXECUTE ON FUNCTION public.rpc_create_sale(VARCHAR, DATE, VARCHAR, VARCHAR, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, VARCHAR) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.rpc_create_restock(VARCHAR, VARCHAR, INT, DATE, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.rpc_void_sale(VARCHAR, TEXT) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.rpc_create_sale(VARCHAR, DATE, VARCHAR, VARCHAR, INT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_restock(VARCHAR, VARCHAR, INT, DATE, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_void_sale(VARCHAR, TEXT) TO authenticated;

-- ==============================================================================
-- 12. SUPABASE REALTIME PUBLICATION SETUP
-- ==============================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.inventory;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sales;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.restock_history;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.audit_logs;
  END IF;
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;
