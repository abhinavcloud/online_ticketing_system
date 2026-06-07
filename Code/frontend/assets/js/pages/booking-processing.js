import { api } from '../api.js';
import { requireAuth } from '../auth.js';
import { storage } from '../storage.js';

if (!requireAuth()) throw new Error('Auth required');

const message = document.querySelector('#bookingProcessingMessage');
const booking = storage.getBooking();
const reservation = storage.getReservation();
const payment = storage.getPayment();

(async function finalizeBooking() {
  if (!reservation?.reservationId || !payment?.paymentId || !booking?.bookingToken) {
    message.textContent = `Missing state: reservationId=${!!reservation?.reservationId}, paymentId=${!!payment?.paymentId}, bookingToken=${!!booking?.bookingToken}`;
    return;
  }


  try {
    const payload = await api.booking({
      reservationId: reservation.reservationId,
      paymentId: payment.paymentId,
      paymentStatus: payment.status,
      amount: reservation.totalAmount,
      bookingToken: booking.bookingToken,
    });

    storage.setConfirmation({
      bookingId: payload.bookingId || payload.id || reservation.reservationId,
      tickets: payload.tickets || payload.ticketIds || [],
      raw: payload,
    });
    window.location.href = 'booking-success.html';
  } catch (error) {
    message.textContent = `${error.message}. Redirecting to homepage. Seat lock cleanup is left to backend TTL.`;
    setTimeout(() => {
      storage.clearFlow();
      window.location.href = 'index.html';
    }, 1200);
  }
})();
