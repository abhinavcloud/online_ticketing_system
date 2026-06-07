import { APP_CONFIG } from './config.js';
import { getBearerToken } from './auth.js';

function joinUrl(path) {
  return `${APP_CONFIG.apiBaseUrl}${path.startsWith('/') ? path : `/${path}`}`;
}

function buildHeaders({ auth = false, json = true, bookingToken = null } = {}) {
  const headers = {};
  if (json) headers['Content-Type'] = 'application/json';
  if (auth) {
    const token = getBearerToken();
    if (token) headers['Authorization'] = `Bearer ${token}`;
  }
  if (bookingToken) headers['x-booking-token'] = bookingToken;
  return headers;
}

async function request(path, { method = 'GET', query = null, body = null, auth = false, bookingToken = null } = {}) {
  const url = new URL(joinUrl(path));
  if (query) {
    Object.entries(query).forEach(([k, v]) => {
      if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v));
    });
  }

  const response = await fetch(url.toString(), {
    method,
    headers: buildHeaders({ auth, json: body !== null, bookingToken }),
    body: body !== null ? JSON.stringify(body) : null,
  });

  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch (_) { data = text; }

  if (!response.ok) {
    const message = data?.message || data?.error || `HTTP ${response.status}`;
    const error = new Error(message);
    error.status = response.status;
    error.payload = data;
    throw error;
  }

  return data;
}

function dualCaseParams(params = {}) {
  const copy = { ...params };
  Object.entries(params).forEach(([key, value]) => {
    if (value === undefined || value === null || value === '') return;
    if (key.endsWith('Id')) {
      const snake = key.replace(/[A-Z]/g, m => `_${m.toLowerCase()}`);
      copy[snake] = value;
    }
  });
  return copy;
}

export const api = {
  getLocations({ page = 1, pageSize = APP_CONFIG.browsePageSize } = {}) {
    return request('/v1/location', { query: { page, pageSize, page_size: pageSize } });
  },

  getVenues({ locationId, page = 1, pageSize = APP_CONFIG.browsePageSize } = {}) {
    return request('/v1/venue', {
      query: dualCaseParams({ locationId, page, pageSize, page_size: pageSize })
    });
  },

  getPerformers({ locationId, page = 1, pageSize = APP_CONFIG.browsePageSize } = {}) {
    return request('/v1/performers', {
      query: dualCaseParams({ locationId, page, pageSize, page_size: pageSize })
    });
  },

  getEvents({ location, venue, performer, page = 1, pageSize = APP_CONFIG.browsePageSize } = {}) {
    return request('/v1/events', {
      query: {
        location: location,
        venue: venue,
        performer: performer,
        page,
        pageSize,
        page_size: pageSize
      }
    });
  },

  getEventDetail(eventId) {
    return request(`/v1/event_detail/${encodeURIComponent(eventId)}`);
  },

  queueEnter({ eventId, categoryId }) {
    return request('/v1/queue/enter', {
      method: 'POST',
      auth: true,
      body: { eventId, categoryId }
    });
  },

  queuePoll({ eventId, categoryId, sessionId, bookingToken }) {
    return request('/v1/queue/poll', {
      method: 'POST',
      auth: true,
      body: { eventId, categoryId, sessionId, bookingToken }
    });
  },

  queueRelease({ eventId, categoryId, sessionId }) {
    return request('/v1/queue/release', {
      method: 'POST',
      auth: true,
      body: { eventId, categoryId, sessionId }
    });
  },

  getSeats({ eventId, categoryId, bookingToken }) {
    return request(`/v1/event/${encodeURIComponent(eventId)}/seats`, {
      method: 'GET',
      auth: true,
      bookingToken,
      query: dualCaseParams({ categoryId })
    });
  },

  reserveTicket({ eventId, categoryId, seats, bookingToken, idempotencyKey }) {
    return request('/v1/reserveticket', {
      method: 'POST',
      auth: true,
      bookingToken,
      body: { eventId, categoryId, seats, bookingToken, idempotencyKey }
    });
  },

  payment({ reservationId, amount, currency }) {
    return request('/v1/payment', {
      method: 'POST',
      auth: true,
      body: { reservationId, amount, currency }
    });
  },

  booking({ reservationId, paymentId, bookingToken }) {
    return request('/v1/booking', {
      method: 'POST',
      auth: true,
      bookingToken,
      body: { reservationId, paymentId, bookingToken }
    });
  }
};
