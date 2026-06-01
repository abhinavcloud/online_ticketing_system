import { wireAuthUi } from '../auth.js';

export function qs(name) {
  return new URLSearchParams(window.location.search).get(name);
}

export function setText(selector, value, fallback = '—') {
  const el = document.querySelector(selector);
  if (el) el.textContent = value ?? fallback;
}

export function money(amount, currency = 'INR') {
  if (amount === undefined || amount === null || Number.isNaN(Number(amount))) return '—';
  try {
    return new Intl.NumberFormat('en-IN', { style: 'currency', currency }).format(Number(amount));
  } catch (_) {
    return `${currency} ${amount}`;
  }
}

export function asArray(payload) {
  if (Array.isArray(payload)) return payload;
  if (Array.isArray(payload?.items)) return payload.items;
  if (Array.isArray(payload?.data)) return payload.data;
  if (Array.isArray(payload?.locations)) return payload.locations;
  if (Array.isArray(payload?.events)) return payload.events;
  if (Array.isArray(payload?.venues)) return payload.venues;
  if (Array.isArray(payload?.performers)) return payload.performers;
  if (Array.isArray(payload?.seats)) return payload.seats;
  return [];
}

export function showStatus(targetSelector, kind, title, text) {
  const box = document.querySelector(targetSelector);
  if (!box) return;
  box.className = `message-box ${kind}`;
  box.innerHTML = `<h3 class="mt-0">${title}</h3><p class="helper-text mb-0">${text}</p>`;
  box.classList.remove('hidden');
}

export function renderBookingSummary(containerSelector, booking = {}, reservation = null) {
  const el = document.querySelector(containerSelector);
  if (!el) return;
  const selectedSeats = booking.selectedSeats || reservation?.selectedSeats || [];
  const total = reservation?.totalAmount ?? booking.totalAmount;
  const currency = reservation?.currency || booking.currency || 'INR';
  el.innerHTML = `
    <div class="form-card sidebar-sticky">
      <h3 class="mt-0">Booking Summary</h3>
      <ul class="summary-list">
        <li class="summary-item"><span class="muted">Event</span><strong>${booking.eventName || booking.eventId || '—'}</strong></li>
        <li class="summary-item"><span class="muted">Category</span><strong>${booking.categoryName || booking.categoryId || '—'}</strong></li>
        <li class="summary-item"><span class="muted">Date</span><strong>${booking.eventDate || '—'}</strong></li>
        <li class="summary-item"><span class="muted">Venue</span><strong>${booking.venueName || '—'}</strong></li>
        <li class="summary-item"><span class="muted">Seats</span><strong>${selectedSeats.length ? selectedSeats.join(', ') : 'None selected'}</strong></li>
        <li class="summary-item"><span class="muted">Amount</span><strong>${money(total, currency)}</strong></li>
      </ul>
    </div>
  `;
}

wireAuthUi();
