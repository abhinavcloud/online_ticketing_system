import { api } from '../api.js';
import { requireAuth } from '../auth.js';
import { storage } from '../storage.js';
import { APP_CONFIG } from '../config.js';
import { qs, renderBookingSummary, money } from './common.js';

if (!requireAuth()) throw new Error('Auth required');

const booking = storage.getBooking();
const eventId = qs('event_id') || qs('eventId') || booking.eventId;
const categoryId = qs('category_id') || qs('categoryId') || booking.categoryId;
const bookingToken = booking.bookingToken;
const statusBox = document.querySelector('#seatsStatusBox');
const grid = document.querySelector('#seatGrid');
const reserveBtn = document.querySelector('#reserveBtn');
let selected = [...(booking.selectedSeats || [])];
let seatIndex = [];

function setStatus(title, text, kind = 'info') {
  statusBox.className = `message-box ${kind}`;
  statusBox.innerHTML = `<h3 class="mt-0">${title}</h3><p class="mb-0">${text}</p>`;
  statusBox.classList.remove('hidden');
}

function normalizeSeats(payload) {
  const seats = Array.isArray(payload?.seats) ? payload.seats : Array.isArray(payload) ? payload : [];
  return seats.map((seat, index) => ({
    id: seat.id || seat.seatId || seat.seat_label || seat.seatLabel || `seat-${index + 1}`,
    label: seat.seat_label || seat.seatLabel || seat.label || `Seat ${index + 1}`,
    status: (seat.status || seat.effectiveStatus || seat.availability || 'AVAILABLE').toUpperCase(),
  }));
}

function selectedSummary() {
  const total = (booking.unitPrice || 0) * selected.length;
  storage.patchBooking({ selectedSeats: selected, totalAmount: total });
  renderBookingSummary('#seatSummary', storage.getBooking());
  const extra = document.querySelector('#seatSummary .form-card');
  if (extra) {
    const note = document.createElement('div');
    note.className = 'message-box info mt-2';
    note.innerHTML = `<h3 class="mt-0">Selection</h3><p class="mb-0">${selected.length}/${APP_CONFIG.maxSeatSelection} seats selected. Estimated amount ${money(total, booking.currency || 'INR')}.</p>`;
    extra.appendChild(note);
  }
}

function renderGrid() {
  grid.innerHTML = seatIndex.map(seat => {
    const isSelected = selected.includes(seat.label);
    let css = 'available';
    if (seat.status === 'BOOKED') css = 'booked';
    else if (seat.status === 'LOCKED' || seat.status === 'HELD') css = 'locked';
    else if (isSelected) css = 'selected';

    return `<button class="seat ${css}" ${css !== 'available' && css !== 'selected' ? 'disabled' : ''} data-seat-label="${seat.label}">${seat.label}</button>`;
  }).join('');

  grid.querySelectorAll('[data-seat-label]').forEach(btn => {
    btn.addEventListener('click', () => {
      const label = btn.dataset.seatLabel;
      if (selected.includes(label)) {
        selected = selected.filter(x => x !== label);
      } else {
        if (selected.length >= APP_CONFIG.maxSeatSelection) {
          setStatus('Selection limit reached', `Only ${APP_CONFIG.maxSeatSelection} seats can be selected from the UI in this phase.`, 'warning');
          return;
        }
        selected.push(label);
      }
      renderGrid();
      selectedSummary();
    });
  });
}

async function loadSeats() {
  if (!eventId || !categoryId || !bookingToken) {
    window.location.href = 'session-expired.html';
    return;
  }

  storage.patchBooking({ eventId, categoryId });
  try {
    const payload = await api.getSeats({ eventId, categoryId, bookingToken });
    seatIndex = normalizeSeats(payload);
    if (!seatIndex.length) {
      setStatus('No seats returned', 'Seat availability API returned an empty payload. Verify seat response shape if needed.', 'warning');
    }
    renderGrid();
    selectedSummary();
  } catch (error) {
    if (error.status === 401) {
      window.location.href = 'session-expired.html';
      return;
    }
    setStatus('Failed to load seat map', error.message, 'danger');
  }
}

reserveBtn.addEventListener('click', async () => {
  if (!selected.length) {
    setStatus('No seats selected', 'Choose at least one available seat before reserving.', 'warning');
    return;
  }

  reserveBtn.disabled = true;
  reserveBtn.textContent = 'Reserving...';
  const idempotencyKey = crypto.randomUUID();

  try {
    const payload = await api.reserveTicket({
      eventId,
      categoryId,
      seats: selected,
      bookingToken,
      idempotencyKey,
    });

    storage.patchBooking({ selectedSeats: selected });
    storage.setReservation({
      reservationId: payload.reservationId || payload.id || payload.reservation_id,
      totalAmount: payload.totalAmount ?? payload.total_amount ?? (booking.unitPrice || 0) * selected.length,
      currency: payload.currency || booking.currency || 'INR',
      selectedSeats: payload.selectedSeats || payload.seats || selected,
      raw: payload,
    });
    window.location.href = 'reservation-review.html';
  } catch (error) {
    window.location.href = 'reservation-conflict.html';
  } finally {
    reserveBtn.disabled = false;
    reserveBtn.textContent = 'Reserve selected seats';
  }
});

loadSeats();
