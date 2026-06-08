import { api } from '../api.js';
import { requireAuth } from '../auth.js';
import { storage } from '../storage.js';
import { APP_CONFIG } from '../config.js';
import { qs, renderBookingSummary, money } from './common.js';

if (!requireAuth()) {
  throw new Error('Auth required');
}

const statusBox = document.querySelector('#seatsStatusBox');
const grid = document.querySelector('#seatGrid');
const reserveBtn = document.querySelector('#reserveBtn');

let selected = [];
let seatIndex = [];

function getBookingContext() {
  const booking = storage.getBooking() || {};

  return {
    booking,
    eventId: qs('event_id') || qs('eventId') || booking.eventId || '',
    categoryId: qs('category_id') || qs('categoryId') || booking.categoryId || '',
    bookingToken: booking.bookingToken || '',
    sessionId: booking.sessionId || '',
  };
}

function setStatus(title, text, kind = 'info') {
  statusBox.className = `message-box ${kind}`;
  statusBox.innerHTML = `<h3 class="mt-0">${title}</h3><p class="mb-0">${text}</p>`;
  statusBox.classList.remove('hidden');
}

function normalizeSeats(payload) {
  const seats = Array.isArray(payload?.seats)
    ? payload.seats
    : Array.isArray(payload)
      ? payload
      : [];

  return seats.map((seat, index) => ({
    id: seat.id || seat.seatId || seat.seat_label || seat.seatLabel || `seat-${index + 1}`,
    label: seat.seat_label || seat.seatLabel || seat.label || seat.seatId || `Seat ${index + 1}`,
    status: (seat.status || seat.effectiveStatus || seat.availability || 'AVAILABLE').toUpperCase(),
  }));
}

function selectedSummary() {
  const { booking } = getBookingContext();
  const unitPrice = booking.unitPrice || 0;
  const currency = booking.currency || 'INR';
  const total = unitPrice * selected.length;

  storage.patchBooking({
    selectedSeats: selected,
    totalAmount: total,
  });

  renderBookingSummary('#seatSummary', storage.getBooking());

  const extra = document.querySelector('#seatSummary .form-card');
  if (extra) {
    const oldNote = extra.querySelector('.message-box.info.mt-2');
    if (oldNote) oldNote.remove();

    const note = document.createElement('div');
    note.className = 'message-box info mt-2';
    note.innerHTML =
      `<h3 class="mt-0">Selection</h3>` +
      `<p class="mb-0">${selected.length}/${APP_CONFIG.maxSeatSelection} seats selected. Estimated amount ${money(total, currency)}.</p>`;
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

    return `
      <button
        class="seat ${css}"
        ${css !== 'available' && css !== 'selected' ? 'disabled' : ''}
        data-seat-label="${seat.label}">
        ${seat.label}
      </button>
    `;
  }).join('');

  grid.querySelectorAll('[data-seat-label]').forEach(btn => {
    btn.addEventListener('click', () => {
      const label = btn.dataset.seatLabel;

      if (selected.includes(label)) {
        selected = selected.filter(x => x !== label);
      } else {
        if (selected.length >= APP_CONFIG.maxSeatSelection) {
          setStatus(
            'Selection limit reached',
            `Only ${APP_CONFIG.maxSeatSelection} seats can be selected from the UI in this phase.`,
            'warning'
          );
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
  const { booking, eventId, categoryId, bookingToken } = getBookingContext();

  if (!eventId || !categoryId) {
    setStatus(
      'Missing booking context',
      'Event or category context is missing. Go back to event details and start the flow again.',
      'warning'
    );
    return;
  }

  if (!bookingToken) {
    setStatus(
      'Missing booking token',
      'Queue session token was not found in browser storage. This usually means the queue state was not persisted before redirect or was lost before seat selection.',
      'warning'
    );

    setTimeout(() => {
      window.location.href = 'session-expired.html';
    }, 1000);
    return;
  }

  storage.patchBooking({ eventId, categoryId });
  selected = [...(booking.selectedSeats || [])];

  try {
    const payload = await api.getSeats({ eventId, categoryId, bookingToken });
    seatIndex = normalizeSeats(payload);

    if (!seatIndex.length) {
      setStatus(
        'No seats returned',
        payload?.status === 'WAITING'
          ? (payload.message || 'You are not admitted yet. Please return to queue flow.')
          : 'Seat availability API returned an empty payload. Verify seat response shape or queue admission state.',
        'warning'
      );
    }

    renderGrid();
    selectedSummary();
  } catch (error) {
    if (error.status === 401 || error.status === 403) {
      setStatus(
        'Session invalid or expired',
        error.message || 'Seat selection is no longer authorized for this queue session.',
        'danger'
      );

      setTimeout(() => {
        window.location.href = 'session-expired.html';
      }, 1000);
      return;
    }

    setStatus('Failed to load seat map', error.message, 'danger');
  }
}

reserveBtn.addEventListener('click', async () => {
  const { booking, eventId, categoryId, bookingToken } = getBookingContext();

  if (!selected.length) {
    setStatus('No seats selected', 'Choose at least one available seat before reserving.', 'warning');
    return;
  }

  if (!bookingToken) {
    setStatus(
      'Missing booking token',
      'Queue session token is missing. Please restart the booking flow.',
      'danger'
    );
    return;
  }

  reserveBtn.disabled = true;
  reserveBtn.textContent = 'Reserving...';

  const idempotencyKey = crypto.randomUUID();

  try {
    const payload = await api.reserveTicket({
      eventId,
      categoryId,
      seats: selected.map(seatId => ({ seatId })),
      bookingToken,
      idempotencyKey,
    });

    storage.patchBooking({ selectedSeats: selected });

    storage.setReservation({
      reservationId: payload.reservationId || payload.id || payload.reservation_id,
      totalAmount:
        payload.pricing?.totalAmount ??
        payload.totalAmount ??
        payload.total_amount ??
        (booking.unitPrice || 0) * selected.length,
      currency:
        payload.pricing?.currency ||
        payload.currency ||
        booking.currency ||
        'INR',
      selectedSeats:
        payload.seats?.locked ||
        payload.selectedSeats ||
        selected,
      raw: payload,
    });

    window.location.href = 'reservation-review.html';
  } catch (error) {
    console.error('reserveTicket failed', {
    status: error.status,
    message: error.message,
    payload: error.payload
  });

  const backendError = error.payload?.error || '';
  const backendMessage = error.payload?.message || error.message || 'Reservation failed';

  if (
    error.status === 409 ||
    backendError === 'SEAT_CONFLICT' ||
    backendError === 'SEATS_NOT_AVAILABLE' ||
    backendError === 'RESERVATION_CONFLICT'
  ) {
    window.location.href = 'reservation-conflict.html';
    return;
  }

  setStatus('Reservation failed', backendMessage, 'danger');
  } finally {
    reserveBtn.disabled = false;
    reserveBtn.textContent = 'Reserve selected seats';
  }
});

loadSeats();
