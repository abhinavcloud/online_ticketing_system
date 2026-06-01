const KEYS = {
  AUTH: 'ots.auth',
  RETURN_TO: 'ots.returnTo',
  BOOKING: 'ots.booking',
  RESERVATION: 'ots.reservation',
  PAYMENT: 'ots.payment',
  CONFIRMATION: 'ots.confirmation',
};

function readJson(key, fallback = null) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch (_) {
    return fallback;
  }
}

function writeJson(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

export const storage = {
  keys: KEYS,

  setAuth(value) { writeJson(KEYS.AUTH, value); },
  getAuth() { return readJson(KEYS.AUTH, null); },
  clearAuth() { localStorage.removeItem(KEYS.AUTH); },

  setReturnTo(value) { localStorage.setItem(KEYS.RETURN_TO, value || ''); },
  getReturnTo() { return localStorage.getItem(KEYS.RETURN_TO) || ''; },
  clearReturnTo() { localStorage.removeItem(KEYS.RETURN_TO); },

  setBooking(value) { writeJson(KEYS.BOOKING, value); },
  getBooking() { return readJson(KEYS.BOOKING, {}); },
  patchBooking(patch) {
    const current = readJson(KEYS.BOOKING, {}) || {};
    writeJson(KEYS.BOOKING, { ...current, ...patch });
  },
  clearBooking() { localStorage.removeItem(KEYS.BOOKING); },

  setReservation(value) { writeJson(KEYS.RESERVATION, value); },
  getReservation() { return readJson(KEYS.RESERVATION, null); },
  clearReservation() { localStorage.removeItem(KEYS.RESERVATION); },

  setPayment(value) { writeJson(KEYS.PAYMENT, value); },
  getPayment() { return readJson(KEYS.PAYMENT, null); },
  clearPayment() { localStorage.removeItem(KEYS.PAYMENT); },

  setConfirmation(value) { writeJson(KEYS.CONFIRMATION, value); },
  getConfirmation() { return readJson(KEYS.CONFIRMATION, null); },
  clearConfirmation() { localStorage.removeItem(KEYS.CONFIRMATION); },

  clearFlow() {
    localStorage.removeItem(KEYS.BOOKING);
    localStorage.removeItem(KEYS.RESERVATION);
    localStorage.removeItem(KEYS.PAYMENT);
    localStorage.removeItem(KEYS.CONFIRMATION);
  }
};
