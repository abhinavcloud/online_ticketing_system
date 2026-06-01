import { requireAuth } from '../auth.js';
import { storage } from '../storage.js';
import { renderBookingSummary, money } from './common.js';

if (!requireAuth()) throw new Error('Auth required');

const booking = storage.getBooking();
const reservation = storage.getReservation();
const target = document.querySelector('#reservationInfo');

if (!reservation?.reservationId) {
  target.innerHTML = '<div class="message-box warning"><h3 class="mt-0">Missing reservation</h3><p class="mb-0">Return to seat selection and reserve seats again.</p></div>';
} else {
  target.innerHTML = `
    <div class="form-card">
      <ul class="summary-list">
        <li class="summary-item"><span class="muted">Reservation ID</span><strong>${reservation.reservationId}</strong></li>
        <li class="summary-item"><span class="muted">Seats</span><strong>${(reservation.selectedSeats || []).join(', ') || '—'}</strong></li>
        <li class="summary-item"><span class="muted">Currency</span><strong>${reservation.currency || booking.currency || 'INR'}</strong></li>
        <li class="summary-item"><span class="muted">Total</span><strong>${money(reservation.totalAmount, reservation.currency || booking.currency || 'INR')}</strong></li>
      </ul>
      <div class="message-box info mt-2">
        <h3 class="mt-0">Important</h3>
        <p class="mb-0">Payment failure or confirmation failure returns to home in this phase. Seat lock cleanup is left to backend TTL expiry.</p>
      </div>
    </div>
  `;
}

renderBookingSummary('#reservationSummary', booking, reservation);
