/**
 * JAGO NUTRITION ID POS & INVENTORY — AUTHENTICATION CLIENT MODULE
 * File: supabase/auth-client.js
 * Architecture: Pure Vanilla JS / Static Browser Compatible
 * Author: Advanced Agentic AI Coding Assistant
 */

(function (window) {
  'use strict';

  const AUTH_SESSION_STORAGE_KEY = 'JN_AUTH_USER_PROFILE';

  class AuthClientManager {
    constructor() {
      this.currentUserProfile = null;
      this.supabaseClient = null;
      this.listeners = [];
    }

    /**
     * Bind Supabase JS Client Instance
     * @param {Object} client Supabase JS Client instance created via window.supabase.createClient
     */
    init(client) {
      this.supabaseClient = client;

      // Listen to Supabase Auth State Changes
      if (this.supabaseClient && this.supabaseClient.auth) {
        this.supabaseClient.auth.onAuthStateChange((event, session) => {
          if (typeof window.logAuthDebug === 'function') {
            window.logAuthDebug("[12]", "auth state event", { event, hasSession: !!session });
          }
          if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') {
            this.syncUserProfileFromStorage();
          } else if (event === 'SIGNED_OUT') {
            this.handleSignOutCleanup();
          }
        });
      }

      this.restoreLocalSession();
    }

    /**
     * Execute Secure Username + Password Login via Supabase Edge Function
     * @param {string} username Username ('adi' or 'koko')
     * @param {string} password User password
     * @returns {Promise<Object>} User profile object on success
     */
    async login(username, password) {
      if (typeof window.logAuthDebug === 'function') {
        window.logAuthDebug("[02]", "JNAuthClient.login invoked", { username });
      }

      if (!username || typeof username !== 'string' || !username.trim()) {
        throw new Error('Username wajib diisi.');
      }
      if (!password || typeof password !== 'string' || !password) {
        throw new Error('Password wajib diisi.');
      }

      const isClientInit = !!this.supabaseClient;
      if (typeof window.logAuthDebug === 'function') {
        window.logAuthDebug("[03]", "Supabase client initialized?", { initialized: isClientInit });
      }

      if (!this.supabaseClient) {
        const url = window.SUPABASE_PROJECT_URL || "https://ambtsbakxcktbnuxjpfj.supabase.co";
        const key = window.SUPABASE_PUBLISHABLE_KEY || "sb_publishable_N0ZJ3fozzwg4T9sgb5kRNA_RaOB0i0u";
        if (window.supabase && window.supabase.createClient) {
          this.supabaseClient = window.supabase.createClient(url, key, { auth: { persistSession: true } });
          if (typeof window.logAuthDebug === 'function') {
            window.logAuthDebug("[03]", "Supabase client auto-initialized fallback OK");
          }
        } else {
          if (typeof window.logAuthDebug === 'function') {
            window.logAuthDebug("[ERR]", "Supabase client missing and window.supabase unavailable");
          }
          throw new Error('Koneksi Supabase belum diinisialisasi.');
        }
      }

      if (typeof window.logAuthDebug === 'function') {
        window.logAuthDebug("[04]", "auth-login request started", { endpoint: "/functions/v1/auth-login" });
      }

      // 1. Invoke Supabase Edge Function 'auth-login' with Direct Fetch Fallback
      let data = null;
      let error = null;

      try {
        const res = await this.supabaseClient.functions.invoke('auth-login', {
          body: {
            username: username.trim().toLowerCase(),
            password: password
          }
        });
        data = res.data;
        error = res.error;
        if (typeof window.logAuthDebug === 'function') {
          window.logAuthDebug("[05]", "SDK functions.invoke completed", { hasData: !!data, hasError: !!error, errorMsg: error ? error.message : null });
        }
      } catch (errInvoke) {
        if (typeof window.logAuthDebug === 'function') {
          window.logAuthDebug("[05]", "SDK functions.invoke exception", { message: errInvoke.message });
        }
      }

      if (error || !data || !data.session) {
        if (typeof window.logAuthDebug === 'function') {
          window.logAuthDebug("[05]", "Attempting direct fetch fallback to Edge Function");
        }
        try {
          const fetchRes = await fetch("https://ambtsbakxcktbnuxjpfj.supabase.co/functions/v1/auth-login", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "apikey": "sb_publishable_N0ZJ3fozzwg4T9sgb5kRNA_RaOB0i0u"
            },
            body: JSON.stringify({
              username: username.trim().toLowerCase(),
              password: password
            })
          });
          if (typeof window.logAuthDebug === 'function') {
            window.logAuthDebug("[05]", "auth-login direct fetch HTTP status", { status: fetchRes.status, ok: fetchRes.ok, statusText: fetchRes.statusText });
          }
          const parsed = await fetchRes.json();
          if (fetchRes.ok && parsed && parsed.session) {
            data = parsed;
            error = null;
            if (typeof window.logAuthDebug === 'function') {
              window.logAuthDebug("[06]", "auth-login response parsed successfully", { hasSession: true, user_id: parsed.user ? parsed.user.id : null });
            }
          } else {
            const msg = (parsed && parsed.error) ? parsed.error : (error ? error.message : 'Username atau password tidak sesuai.');
            if (typeof window.logAuthDebug === 'function') {
              window.logAuthDebug("[ERR]", "auth-login direct fetch error response", { status: fetchRes.status, message: msg });
            }
            throw new Error(msg);
          }
        } catch (fetchErr) {
          if (!data || !data.session) {
            const message = (data && data.error) ? data.error : (error ? error.message : fetchErr.message);
            if (typeof window.logAuthDebug === 'function') {
              window.logAuthDebug("[ERR]", "auth-login fetch network exception", { message: fetchErr.message, name: fetchErr.name });
            }
            throw new Error(message || 'Username atau password tidak sesuai.');
          }
        }
      }

      const sessionReceived = !!(data && data.session);
      const accessPresent = !!(data && data.session && data.session.access_token);
      const refreshPresent = !!(data && data.session && data.session.refresh_token);

      if (typeof window.logAuthDebug === 'function') {
        window.logAuthDebug("[07]", "session received?", { sessionReceived });
        window.logAuthDebug("[08]", "access token present?", { accessToken: accessPresent ? "YES" : "NO" });
        window.logAuthDebug("[09]", "refresh token present?", { refreshToken: refreshPresent ? "YES" : "NO" });
      }

      // 2. Cache & Set User Profile BEFORE setSession to prevent race condition with auth state listeners
      this.currentUserProfile = {
        id: data.user.id,
        username: data.user.username,
        name: data.user.name,
        role: data.user.role,
        country: data.user.country,
        flag: data.user.country === 'Malaysia' ? '🇲🇾' : '🇮🇩',
        loginTime: new Date().toISOString()
      };

      try {
        localStorage.setItem(AUTH_SESSION_STORAGE_KEY, JSON.stringify(this.currentUserProfile));
        if (typeof window.logAuthDebug === 'function') {
          window.logAuthDebug("[14]", "localStorage profile saved?", { saved: true, username: this.currentUserProfile.username, id: this.currentUserProfile.id });
        }
      } catch (e) {
        if (typeof window.logAuthDebug === 'function') {
          window.logAuthDebug("[14]", "localStorage profile saved?", { saved: false, error: e.message });
        }
      }

      if (typeof window.logAuthDebug === 'function') {
        window.logAuthDebug("[10]", "setSession started");
      }

      // 3. Bind Native Supabase Session to Client
      try {
        const { error: sessionError } = await this.supabaseClient.auth.setSession({
          access_token: data.session.access_token,
          refresh_token: data.session.refresh_token
        });

        if (sessionError) {
          if (typeof window.logAuthDebug === 'function') {
            window.logAuthDebug("[11]", "setSession result notice", { notice: sessionError.message });
          }
        } else {
          if (typeof window.logAuthDebug === 'function') {
            window.logAuthDebug("[11]", "setSession result", { success: true });
          }
        }
      } catch (sErr) {
        if (typeof window.logAuthDebug === 'function') {
          window.logAuthDebug("[11]", "setSession exception", { message: sErr.message });
        }
      }

      this.notifyListeners('login', this.currentUserProfile);
      return this.currentUserProfile;
    }

    /**
     * Execute User Logout
     * @returns {Promise<boolean>}
     */
    async logout() {
      try {
        if (this.supabaseClient && this.supabaseClient.auth) {
          await this.supabaseClient.auth.signOut();
        }
      } catch (err) {
        console.warn('Supabase signOut notice:', err);
      } finally {
        this.handleSignOutCleanup();
      }
      return true;
    }

    /**
     * Check if a User is Authenticated
     * @returns {boolean}
     */
    isAuthenticated() {
      return !!this.currentUserProfile && !!this.currentUserProfile.id;
    }

    /**
     * Get Current Active User Profile
     * @returns {Object|null}
     */
    getCurrentUser() {
      return this.currentUserProfile;
    }

    /**
     * Restore Session Profile from Local Storage
     */
    restoreLocalSession() {
      try {
        const cached = localStorage.getItem(AUTH_SESSION_STORAGE_KEY);
        if (cached) {
          this.currentUserProfile = JSON.parse(cached);
        }
      } catch (e) {
        this.currentUserProfile = null;
      }
    }

    /**
     * Internal SignOut Cleanup
     */
    handleSignOutCleanup() {
      this.currentUserProfile = null;
      try {
        localStorage.removeItem(AUTH_SESSION_STORAGE_KEY);
      } catch (e) {}
      this.notifyListeners('logout', null);
    }

    /**
     * Internal Sync Profile From Storage
     */
    syncUserProfileFromStorage() {
      if (!this.currentUserProfile) {
        this.restoreLocalSession();
      }
    }

    /**
     * Subscribe to Auth Client Events ('login', 'logout')
     * @param {Function} callback Callback listener function
     */
    subscribe(callback) {
      if (typeof callback === 'function') {
        this.listeners.push(callback);
      }
    }

    /**
     * Notify Subscribers
     */
    notifyListeners(event, data) {
      this.listeners.forEach(fn => {
        try {
          fn(event, data);
        } catch (e) {
          console.error('AuthClient listener error:', e);
        }
      });
    }
  }

  // Export to Global Window Scope
  window.JNAuthClient = new AuthClientManager();

})(window);
