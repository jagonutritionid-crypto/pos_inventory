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
      if (!username || typeof username !== 'string' || !username.trim()) {
        throw new Error('Username wajib diisi.');
      }
      if (!password || typeof password !== 'string' || !password) {
        throw new Error('Password wajib diisi.');
      }

      if (!this.supabaseClient) {
        throw new Error('Koneksi Supabase belum diinisialisasi.');
      }

      // 1. Invoke Supabase Edge Function 'auth-login'
      const { data, error } = await this.supabaseClient.functions.invoke('auth-login', {
        body: {
          username: username.trim().toLowerCase(),
          password: password
        }
      });

      if (error || !data || !data.session) {
        const message = (data && data.error) ? data.error : (error ? error.message : 'Username atau password tidak sesuai.');
        throw new Error(message);
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
      } catch (e) {
        console.warn('Unable to write user profile to localStorage:', e);
      }

      // 3. Bind Native Supabase Session to Client
      try {
        const { error: sessionError } = await this.supabaseClient.auth.setSession({
          access_token: data.session.access_token,
          refresh_token: data.session.refresh_token
        });

        if (sessionError) {
          console.warn('Supabase setSession notice:', sessionError.message);
        }
      } catch (sErr) {
        console.warn('Supabase setSession exception handled:', sErr);
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
