import { APP_CONFIG } from './config.js';
import { storage } from './storage.js';

function decodeJwt(token) {
  try {
    const [, payload] = token.split('.');
    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(normalized));
  } catch (_) {
    return null;
  }
}

function tokenExpired(token) {
  const payload = decodeJwt(token);
  if (!payload?.exp) return false;
  return Date.now() >= payload.exp * 1000;
}

export function getAuthState() {
  const auth = storage.getAuth();
  if (!auth?.idToken && !auth?.accessToken) return { authenticated: false };
  const token = auth.idToken || auth.accessToken;
  if (!token || tokenExpired(token)) {
    storage.clearAuth();
    return { authenticated: false };
  }
  return {
    authenticated: true,
    token,
    idToken: auth.idToken,
    accessToken: auth.accessToken,
    profile: decodeJwt(auth.idToken || auth.accessToken) || {},
  };
}

export function getBearerToken() {
  const state = getAuthState();
  return state.authenticated ? (state.idToken || state.accessToken) : null;
}

export function requireAuth(returnTo = window.location.pathname + window.location.search) {
  const state = getAuthState();
  if (!state.authenticated) {
    storage.setReturnTo(returnTo);
    window.location.href = 'login.html';
    return false;
  }
  return true;
}

export function buildAuthorizeUrl() {
  const url = new URL(`${APP_CONFIG.cognitoDomain}/oauth2/authorize`);
  url.searchParams.set('client_id', APP_CONFIG.cognitoClientId);
  url.searchParams.set('response_type', 'token');
  url.searchParams.set('scope', APP_CONFIG.oauthScopes.join(' '));
  url.searchParams.set('redirect_uri', APP_CONFIG.redirectUri);
  url.searchParams.set('identity_provider', APP_CONFIG.identityProvider);
  return url.toString();
}

export function login() {
  window.location.href = buildAuthorizeUrl();
}

export function logout() {
  storage.clearAuth();
  storage.clearFlow();
  const url = new URL(`${APP_CONFIG.cognitoDomain}/logout`);
  url.searchParams.set('client_id', APP_CONFIG.cognitoClientId);
  url.searchParams.set('logout_uri', APP_CONFIG.logoutUri);
  window.location.href = url.toString();
}

export function parseHostedUiCallback() {
  const hash = window.location.hash.startsWith('#') ? window.location.hash.slice(1) : '';
  const params = new URLSearchParams(hash);
  const idToken = params.get('id_token');
  const accessToken = params.get('access_token');
  const expiresIn = Number(params.get('expires_in') || 0);
  if (!idToken && !accessToken) {
    return { ok: false, error: 'No token found in callback.' };
  }

  storage.setAuth({
    idToken,
    accessToken,
    expiresIn,
    storedAt: Date.now(),
  });

  const returnTo = storage.getReturnTo() || 'index.html';
  storage.clearReturnTo();
  return { ok: true, returnTo };
}

export function wireAuthUi() {
  const authState = getAuthState();
  const loginButtons = document.querySelectorAll('[data-action="login"]');
  const logoutButtons = document.querySelectorAll('[data-action="logout"]');
  const authOnly = document.querySelectorAll('[data-auth="true"]');
  const guestOnly = document.querySelectorAll('[data-guest="true"]');
  const profileNodes = document.querySelectorAll('[data-auth-profile]');

  loginButtons.forEach(btn => btn.addEventListener('click', (e) => {
    e.preventDefault();
    login();
  }));

  logoutButtons.forEach(btn => btn.addEventListener('click', (e) => {
    e.preventDefault();
    logout();
  }));

  authOnly.forEach(el => el.classList.toggle('hidden', !authState.authenticated));
  guestOnly.forEach(el => el.classList.toggle('hidden', authState.authenticated));

  profileNodes.forEach(el => {
    el.textContent = authState.authenticated
      ? (authState.profile?.email || authState.profile?.cognito_username || 'Signed in')
      : 'Guest';
  });
}
