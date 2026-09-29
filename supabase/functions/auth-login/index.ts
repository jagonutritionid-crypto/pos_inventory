// ==============================================================================
// JAGO NUTRITION ID POS & INVENTORY — PHASE 1C.2 AUTHENTICATION EDGE FUNCTION
// File: supabase/functions/auth-login/index.ts
// Runtime: Deno TypeScript (Supabase Edge Functions)
// Author: Advanced Agentic AI Coding Assistant
// ==============================================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// Allowed Production Origin (GitHub Pages)
const ALLOWED_ORIGIN_PROD = "https://jagonutritionid-crypto.github.io";

// Maximum Allowed Input Lengths for Early Rejection
const MAX_PAYLOAD_BYTES = 4096; // 4 KB limit
const MAX_USERNAME_LENGTH = 50;
const MAX_PASSWORD_LENGTH = 128;

// Target Artificial Delay for Unmapped Usernames (ms) to Match GoTrue bcrypt Latency
const TIMING_NORMALIZATION_MS = 120;

// Secure CORS Headers Helper
function getCorsHeaders(requestOrigin: string | null): HeadersInit {
  let origin = ALLOWED_ORIGIN_PROD;
  if (requestOrigin) {
    if (
      requestOrigin === ALLOWED_ORIGIN_PROD ||
      requestOrigin.startsWith("http://localhost:") ||
      requestOrigin.startsWith("http://127.0.0.1:")
    ) {
      origin = requestOrigin;
    }
  }

  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-forwarded-for",
    "Access-Control-Max-Age": "86400",
    "Content-Type": "application/json",
  };
}

// System Username Resolution Map
// Internal emails are implementation details managed strictly inside the Edge Function.
const USERNAME_MAP: Record<string, { internalEmail: string; name: string; role: string; country: string }> = {
  adi: {
    internalEmail: "adi.internal@jagonutritionid.system",
    name: "Adi",
    role: "ADMIN",
    country: "Indonesia",
  },
  koko: {
    internalEmail: "koko.internal@jagonutritionid.system",
    name: "Koko",
    role: "OWNER",
    country: "Malaysia",
  },
};

serve(async (req: Request) => {
  const requestOrigin = req.headers.get("origin");
  const corsHeaders = getCorsHeaders(requestOrigin);

  // 1. Handle Preflight OPTIONS Request
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 2. Enforce HTTP POST Method Only
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method Not Allowed. HTTP POST required." }),
      { status: 405, headers: corsHeaders }
    );
  }

  // 3. Early Rejection for Excessively Large Payloads
  const contentLength = req.headers.get("content-length");
  if (contentLength && parseInt(contentLength, 10) > MAX_PAYLOAD_BYTES) {
    return new Response(
      JSON.stringify({ error: "Payload Too Large." }),
      { status: 400, headers: corsHeaders }
    );
  }

  try {
    // 4. Parse Request Payload safely
    const body = await req.json().catch(() => null);
    if (!body || typeof body !== "object") {
      return new Response(
        JSON.stringify({ error: "Invalid JSON request payload." }),
        { status: 400, headers: corsHeaders }
      );
    }

    const { username, password } = body;

    // 5. Validate & Bound Input Parameters
    if (!username || typeof username !== "string" || !username.trim()) {
      return new Response(
        JSON.stringify({ error: "Username is required." }),
        { status: 400, headers: corsHeaders }
      );
    }

    if (!password || typeof password !== "string" || !password) {
      return new Response(
        JSON.stringify({ error: "Password is required." }),
        { status: 400, headers: corsHeaders }
      );
    }

    const trimmedUsername = username.trim();
    if (trimmedUsername.length > MAX_USERNAME_LENGTH || password.length > MAX_PASSWORD_LENGTH) {
      return new Response(
        JSON.stringify({ error: "Invalid username or password format." }),
        { status: 400, headers: corsHeaders }
      );
    }

    // 6. Normalize & Resolve Username
    const normalizedUsername = trimmedUsername.toLowerCase();
    const userMapping = USERNAME_MAP[normalizedUsername];

    if (!userMapping) {
      // Timing Normalization: Artificial delay to match GoTrue password evaluation time (~120ms)
      // Prevents username enumeration via response time analysis without CPU spinloops
      await new Promise((resolve) => setTimeout(resolve, TIMING_NORMALIZATION_MS));

      return new Response(
        JSON.stringify({ error: "Username atau password tidak sesuai." }),
        { status: 401, headers: corsHeaders }
      );
    }

    // 7. Read Environment Variables
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseAnonKey) {
      console.error("Missing SUPABASE_URL or SUPABASE_ANON_KEY in Edge Function environment variables.");
      return new Response(
        JSON.stringify({ error: "System configuration error. Please contact system administrator." }),
        { status: 500, headers: corsHeaders }
      );
    }

    // 8. Extract Client IP for Header Forwarding
    const clientIp = req.headers.get("x-forwarded-for") || req.headers.get("cf-connecting-ip") || "";

    // 9. Instantiate Supabase Client with Client IP Header Propagation
    const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false },
      global: {
        headers: clientIp ? { "x-forwarded-for": clientIp } : {},
      },
    });

    // 10. Authenticate with Internal Identity using Supabase Auth (GoTrue)
    const { data: authData, error: authError } = await supabaseClient.auth.signInWithPassword({
      email: userMapping.internalEmail,
      password: password,
    });

    if (authError || !authData.session) {
      return new Response(
        JSON.stringify({ error: "Username atau password tidak sesuai." }),
        { status: 401, headers: corsHeaders }
      );
    }

    // 11. Construct Sanitized Session Response
    const responsePayload = {
      session: {
        access_token: authData.session.access_token,
        refresh_token: authData.session.refresh_token,
        expires_in: authData.session.expires_in,
        expires_at: authData.session.expires_at,
        token_type: authData.session.token_type,
      },
      user: {
        id: authData.session.user.id,
        username: normalizedUsername,
        name: userMapping.name,
        role: userMapping.role,
        country: userMapping.country,
      },
    };

    return new Response(JSON.stringify(responsePayload), {
      status: 200,
      headers: corsHeaders,
    });

  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : "Internal Error";
    console.error("Auth-Login Edge Function Error:", errorMessage);

    return new Response(
      JSON.stringify({ error: "Terjadi kendala pada server autentikasi." }),
      { status: 500, headers: corsHeaders }
    );
  }
});

