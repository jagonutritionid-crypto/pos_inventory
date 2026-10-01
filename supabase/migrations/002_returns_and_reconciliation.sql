-- ==============================================================================
-- JAGO NUTRITION ID POS & INVENTORY — DATABASE MIGRATION 002
-- CUSTOMER RETURNS, REFUNDS, DISPOSITION, & RECONCILIATION HARDENING
-- Target Engine: PostgreSQL 15+ (Supabase)
-- ==============================================================================

-- 1. ENHANCE INVENTORY TABLE WITH RETURN COUNTERS
-- Maintains Available Stock Invariant: current_stock = initial_stock + total_in + total_returned_resalable - total_out
ALTER TABLE public.inventory 
ADD COLUMN IF NOT EXISTS total_returned INT NOT NULL DEFAULT 0 CHECK (total_returned >= 0),
ADD COLUMN IF NOT EXISTS total_returned_resalable INT NOT NULL DEFAULT 0 CHECK (total_returned_resalable >= 0),
ADD COLUMN IF NOT EXISTS total_returned_damaged INT NOT NULL DEFAULT 0 CHECK (total_returned_damaged >= 0);

-- 2. CREATE / UPDATE RETURNS TABLE
-- Tracks customer returns linked to original sales with explicit Stock Disposition
CREATE TABLE IF NOT EXISTS public.returns (
  id VARCHAR(50) PRIMARY KEY, -- RET-YYYYMMDD-XXXX
  sale_id VARCHAR(50) NOT NULL REFERENCES public.sales(id) ON DELETE RESTRICT,
  product_id VARCHAR(50) NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  product_name VARCHAR(255) NOT NULL,
  sku VARCHAR(50) NOT NULL,
  qty INT NOT NULL CHECK (qty > 0),
  stock_returned_qty INT NOT NULL CHECK (stock_returned_qty >= 0),
  disposition VARCHAR(50) NOT NULL DEFAULT 'RESTOCKABLE' CHECK (disposition IN ('RESTOCKABLE', 'DAMAGED', 'QUARANTINE', 'OTHER')),
  unit_price NUMERIC(15, 2) NOT NULL CHECK (unit_price >= 0),
  unit_hpp NUMERIC(15, 2) NOT NULL CHECK (unit_hpp >= 0),
  original_sale_amount NUMERIC(15, 2) NOT NULL CHECK (original_sale_amount >= 0),
  refund_amount NUMERIC(15, 2) NOT NULL CHECK (refund_amount >= 0),
  reason TEXT NOT NULL,
  condition_status VARCHAR(50) NOT NULL DEFAULT 'COMPLETED',
  created_by VARCHAR(100) NOT NULL,
  user_id UUID NULL REFERENCES public.users(id) ON DELETE SET NULL,
  return_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT check_stock_returned_qty_lte_qty CHECK (stock_returned_qty <= qty)
);

-- Ensure disposition column exists if table was previously created
ALTER TABLE public.returns 
ADD COLUMN IF NOT EXISTS disposition VARCHAR(50) NOT NULL DEFAULT 'RESTOCKABLE';

-- 3. INDEXES FOR FAST QUERYING AND RECONCILIATION
CREATE INDEX IF NOT EXISTS idx_returns_sale_id ON public.returns(sale_id);
CREATE INDEX IF NOT EXISTS idx_returns_product_id ON public.returns(product_id);
CREATE INDEX IF NOT EXISTS idx_returns_date ON public.returns(return_date);
CREATE INDEX IF NOT EXISTS idx_returns_disposition ON public.returns(disposition);

-- 4. RLS POLICIES FOR RETURNS TABLE
ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'returns' AND policyname = 'authenticated_select_returns'
  ) THEN
    CREATE POLICY "authenticated_select_returns" ON public.returns 
    FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- 5. ATOMIC RETURN / REFUND PROCEDURE WITH STOCK DISPOSITION GUARD
CREATE OR REPLACE FUNCTION public.rpc_create_return(
  p_id VARCHAR,
  p_sale_id VARCHAR,
  p_qty INT,
  p_stock_returned_qty INT,
  p_refund_amount NUMERIC,
  p_reason TEXT,
  p_disposition VARCHAR,
  p_return_date DATE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user RECORD;
  v_sale RECORD;
  v_prev_returned_qty INT;
  v_new_stock INT;
  v_audit_id VARCHAR;
  v_actual_disposition VARCHAR;
  v_effective_stock_returned INT;
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

  -- 2. Lock & Fetch Original Sale Record
  SELECT * INTO v_sale FROM public.sales WHERE id = p_sale_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original sale transaction % not found.', p_sale_id;
  END IF;

  IF v_sale.status = 'VOIDED' THEN
    RAISE EXCEPTION 'Cannot return a voided transaction (%).', p_sale_id;
  END IF;

  -- 3. Cumulative return quantity check (prevent over-return)
  SELECT COALESCE(SUM(qty), 0) INTO v_prev_returned_qty
  FROM public.returns
  WHERE sale_id = p_sale_id;

  IF (v_prev_returned_qty + p_qty) > v_sale.qty THEN
    RAISE EXCEPTION 'Cannot return % pcs. Original qty: %, already returned: % pcs.',
      p_qty, v_sale.qty, v_prev_returned_qty;
  END IF;

  -- 4. Validate & Normalize Disposition & Returned Stock Logic
  v_actual_disposition := COALESCE(NULLIF(TRIM(p_disposition), ''), 'RESTOCKABLE');
  
  -- CRITICAL RULE: If disposition is DAMAGED or QUARANTINE, stock CANNOT be returned to available inventory!
  IF v_actual_disposition IN ('DAMAGED', 'QUARANTINE', 'NON_RESTOCKABLE') THEN
    v_effective_stock_returned := 0;
  ELSE
    v_effective_stock_returned := LEAST(p_stock_returned_qty, p_qty);
  END IF;

  -- 5. Lock & Update Inventory Atomically
  SELECT current_stock INTO v_new_stock
  FROM public.inventory
  WHERE product_id = v_sale.product_id
  FOR UPDATE;

  IF v_effective_stock_returned > 0 THEN
    UPDATE public.inventory
    SET 
      total_returned = total_returned + v_effective_stock_returned,
      total_returned_resalable = total_returned_resalable + v_effective_stock_returned,
      current_stock = current_stock + v_effective_stock_returned,
      updated_at = NOW()
    WHERE product_id = v_sale.product_id
    RETURNING current_stock INTO v_new_stock;
  ELSE
    -- Non-restockable / damaged return -> Increment damaged counter without changing available current_stock
    UPDATE public.inventory
    SET 
      total_returned_damaged = total_returned_damaged + p_qty,
      updated_at = NOW()
    WHERE product_id = v_sale.product_id;
  END IF;

  -- 6. Insert Return Ledger Entry
  INSERT INTO public.returns (
    id, sale_id, product_id, product_name, sku, qty, stock_returned_qty, disposition,
    unit_price, unit_hpp, original_sale_amount, refund_amount, reason,
    condition_status, created_by, user_id, return_date, created_at
  ) VALUES (
    p_id, p_sale_id, v_sale.product_id, v_sale.product_name, v_sale.sku, p_qty, v_effective_stock_returned, v_actual_disposition,
    v_sale.unit_price, v_sale.unit_hpp, v_sale.net_total, p_refund_amount, COALESCE(p_reason, 'Customer Return'),
    'COMPLETED', v_user.name, v_user.id, p_return_date, NOW()
  );

  -- 7. Record Audit Log Entry
  v_audit_id := 'AUD-' || EXTRACT(EPOCH FROM NOW())::TEXT || '-' || FLOOR(RANDOM() * 1000)::TEXT;
  INSERT INTO public.audit_logs (
    id, timestamp, user_id, user_name, user_role, user_country,
    action, entity_type, entity_id, details
  ) VALUES (
    v_audit_id, NOW(), v_user.id::TEXT, v_user.name, v_user.role, v_user.country,
    'CREATE_RETURN', 'TRANSACTION', p_id,
    'Recorded return ' || p_id || ' for Sale ' || p_sale_id || ' (' || p_qty || ' pcs ' || v_sale.product_name || ', Disposition: ' || v_actual_disposition || ', Refund: Rp ' || p_refund_amount || ')'
  );

  RETURN jsonb_build_object(
    'success', true,
    'return_id', p_id,
    'sale_id', p_sale_id,
    'disposition', v_actual_disposition,
    'effective_stock_returned', v_effective_stock_returned,
    'current_stock', v_new_stock
  );
END;
$$;

-- 6. PRIVILEGE HARDENING FOR RETURN RPC
REVOKE EXECUTE ON FUNCTION public.rpc_create_return(VARCHAR, VARCHAR, INT, INT, NUMERIC, TEXT, VARCHAR, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_create_return(VARCHAR, VARCHAR, INT, INT, NUMERIC, TEXT, VARCHAR, DATE) TO authenticated;

-- 7. REALTIME PUBLICATION ENHANCEMENT
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.returns;
  END IF;
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;
