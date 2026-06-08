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

const SEATS_PER_ROW = 10;
const ROWS_PER_PAGE = 10;
const SEATS_PER_PAGE = SEATS_PER_ROW * ROWS_PER_PAGE;

let currentSeatPage = 1;

const seatLabelCollator = new Intl.Collator(undefined, {
  numeric: true,
  sensitivity: 'base',
});

function compareSeatLabels(a, b) {
  return seatLabelCollator.compare(String(a || ''), String(b || ''));
}

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
  if (!statusBox) return;

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

  const normalized = seats.map((seat, index) => ({
    id: seat.id || seat.seatId || seat.seat_label || seat.seatLabel || `seat-${index + 1}`,
    label: seat.seat_label || seat.seatLabel || seat.label || seat.seatId || `Seat ${index + 1}`,
    status: (seat.status || seat.effectiveStatus || seat.availability || 'AVAILABLE').toUpperCase(),
  }));

  normalized.sort((a, b) => compareSeatLabels(a.label, b.label));

  return normalized;
}

function isGeneralSeatView() {
  const { booking } = getBookingContext();
  const categoryName = String(booking?.categoryName || '').trim().toUpperCase();

  if (categoryName === 'GENERAL' || categoryName === 'GEN') {
    return true;
  }

  const firstSeat = seatIndex[0]?.label || '';

  return /^GEN[-\s]/i.test(firstSeat) || /^GENERAL[-\s]/i.test(firstSeat);
}

function getVisibleSeats() {
  const start = (currentSeatPage - 1) * SEATS_PER_PAGE;
  const end = start + SEATS_PER_PAGE;

  return seatIndex.slice(start, end);
}

function getTotalSeatPages() {
  return Math.max(1, Math.ceil(seatIndex.length / SEATS_PER_PAGE));
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
  if (!extra) return;

  const oldNote = extra.querySelector('.message-box.info.mt-2');
  if (oldNote) oldNote.remove();

  const note = document.createElement('div');
  note.className = 'message-box info mt-2';
  note.innerHTML =
    `<h3 class="mt-0">Your Selection</h3>` +
    `<p class="mb-0">${selected.length}/${APP_CONFIG.maxSeatSelection} seats selected. Estimated total ${money(total, currency)}.</p>`;

  extra.appendChild(note);
}

function vipDividerMarkup() {
  return `
    <div class="seat-area-divider">
      <div class="seat-area-divider-title">VIP Seats</div>
      <div class="seat-area-divider-subtitle">
        Premium seats are located closer to the stage
      </div>
    </div>
  `;
}

function renderSeatPager() {
  if (seatIndex.length <= SEATS_PER_PAGE) {
    return '';
  }

  const totalPages = getTotalSeatPages();
  const start = (currentSeatPage - 1) * SEATS_PER_PAGE + 1;
  const end = Math.min(currentSeatPage * SEATS_PER_PAGE, seatIndex.length);

  return `
    <div class="seat-pager">
      <button
        class="secondary-btn"
        data-seat-page-action="prev"
        type="button"
        ${currentSeatPage <= 1 ? 'disabled' : ''}
      >
        Previous seats
      </button>

      <span class="badge">
        Showing ${start}–${end} of ${seatIndex.length}
      </span>

      <button
        class="secondary-btn"
        data-seat-page-action="next"
        type="button"
        ${currentSeatPage >= totalPages ? 'disabled' : ''}
      >
        Next seats
      </button>
    </div>
  `;
}

function getSeatCssClass(seat) {
  const isSelected = selected.includes(seat.label);

  if (seat.status === 'BOOKED') {
    return 'booked';
  }

  if (seat.status === 'LOCKED' || seat.status === 'HELD') {
    return 'locked';
  }

  if (isSelected) {
    return 'selected';
  }

  return 'available';
}

function renderGrid() {
  if (!grid) return;

  // Keep display:grid as a fallback if CSS is stale/cached.
  // Do not set grid-template-columns inline; CSS controls desktop/mobile layout.
  grid.style.display = 'grid';
  grid.style.removeProperty('grid-template-columns');

  const generalView = isGeneralSeatView();
  const visibleSeats = getVisibleSeats();

  const seatsMarkup = visibleSeats.map((seat) => {
    const css = getSeatCssClass(seat);

    return `
      <button
        class="seat ${css}"
        ${css !== 'available' && css !== 'selected' ? 'disabled' : ''}
        data-seat-label="${seat.label}"
        type="button"
      >
        ${seat.label}
      </button>
    `;
  }).join('');

  grid.innerHTML = `
    ${renderSeatPager()}
    ${generalView ? vipDividerMarkup() : ''}
    ${seatsMarkup}
  `;

  grid.querySelectorAll('[data-seat-label]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const label = btn.dataset.seatLabel;

      if (selected.includes(label)) {
        selected = selected.filter((x) => x !== label);
      } else {
        if (selected.length >= APP_CONFIG.maxSeatSelection) {
          setStatus(
            'Selection limit reached',
            `You can select up to ${APP_CONFIG.maxSeatSelection} seats at a time.`,
            'warning'
          );
          return;
        }

        selected.push(label);
        selected.sort(compareSeatLabels);
      }

      renderGrid();
      selectedSummary();
    });
  });

  grid.querySelectorAll('[data-seat-page-action]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const action = btn.dataset.seatPageAction;
      const totalPages = getTotalSeatPages();

      if (action === 'prev' && currentSeatPage > 1) {
        currentSeatPage -= 1;
      }

      if (action === 'next' && currentSeatPage < totalPages) {
        currentSeatPage += 1;
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
      'Missing booking details',
      'Event or category details are missing. Please go back and start again.',
      'warning'
    );
    return;
  }

  if (!bookingToken) {
    setStatus(
      'Session expired',
      'Your booking session is no longer active. Please start again.',
      'warning'
    );

    setTimeout(() => {
      window.location.href = 'session-expired.html';
    }, 1000);

    return;
  }

  storage.patchBooking({ eventId, categoryId });
  selected = [...(booking.selectedSeats || [])].sort(compareSeatLabels);

  try {
    const payload = await api.getSeats({ eventId, categoryId, bookingToken });

    seatIndex = normalizeSeats(payload);
    currentSeatPage = 1;

    if (!seatIndex.length) {
      setStatus(
        'No seats available',
        payload?.status === 'WAITING'
          ? (payload.message || 'Please wait a moment and try again.')
          : 'No seats could be loaded for this event right now.',
        'warning'
      );
    } else if (payload?.hasMore) {
      setStatus(
        'Some seats are not shown',
        'Only part of the seat map was loaded. Please try again shortly or choose another section.',
        'warning'
      );
    }

    renderGrid();
    selectedSummary();
  } catch (error) {
    if (error.status === 401 || error.status === 403) {
      setStatus(
        'Session expired',
        error.message || 'Your booking session is no longer valid.',
        'danger'
      );

      setTimeout(() => {
        window.location.href = 'session-expired.html';
      }, 1000);

      return;
    }

    setStatus('Unable to load seats', error.message || 'Please try again.', 'danger');
  }
}

if (reserveBtn) {
  reserveBtn.addEventListener('click', async () => {
    const { booking, eventId, categoryId, bookingToken } = getBookingContext();

    if (!selected.length) {
      setStatus('No seats selected', 'Please select at least one seat to continue.', 'warning');
      return;
    }

    if (!bookingToken) {
      setStatus(
        'Session expired',
        'Your booking session is no longer active. Please start again.',
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
        seats: selected.map((seatId) => ({ seatId })),
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
        payload: error.payload,
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
      reserveBtn.textContent = 'Continue with selected seats';
    }
  });
}

loadSeats();
