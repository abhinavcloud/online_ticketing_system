import { requireAuth } from '../auth.js';
import { storage } from '../storage.js';
import { renderBookingSummary, money } from './common.js';

if (!requireAuth()) throw new Error('Auth required');

const booking = storage.getBooking();
const reservation = storage.getReservation();
const confirmation = storage.getConfirmation();
const target = document.querySelector('#successContent');

if (!confirmation) {
  target.innerHTML = '<div class="message-box warning"><h3 class="mt-0">Missing confirmation</h3><p class="mb-0">No confirmation data available in browser storage.</p></div>';
} else {
  target.innerHTML = `
    <div class="form-card">
      <ul class="summary-list">
        <li class="summary-item"><span class="muted">Booking ID</span><strong>${confirmation.bookingId || reservation?.reservationId || '—'}</strong></li>
        <li class="summary-item"><span class="muted">Event</span><strong>${booking.eventName || booking.eventId || '—'}</strong></li>
        <li class="summary-item"><span class="muted">Category</span><strong>${booking.categoryName || booking.categoryId || '—'}</strong></li>
        <li class="summary-item"><span class="muted">Seats</span><strong>${(reservation?.selectedSeats || booking.selectedSeats || []).join(', ') || '—'}</strong></li>
        <li class="summary-item"><span class="muted">Total Amount</span><strong>${money(reservation?.totalAmount || booking.totalAmount, reservation?.currency || booking.currency || 'INR')}</strong></li>
      </ul>
      <div class="message-box success mt-2">
        <h3 class="mt-0">Notification</h3>
        <p class="mb-0">Notifications are handled separately by backend integration. Phase 1 frontend only shows booking confirmation.</p>
      </div>
    </div>
  `;
}

renderBookingSummary('#successSummary', booking, reservation);
