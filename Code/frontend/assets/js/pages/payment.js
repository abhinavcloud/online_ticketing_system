import { api } from '../api.js';
import { requireAuth } from '../auth.js';
import { storage } from '../storage.js';
import { renderBookingSummary, money } from './common.js';

if (!requireAuth()) throw new Error('Auth required');

const booking = storage.getBooking();
const reservation = storage.getReservation();
const statusBox = document.querySelector('#paymentStatusBox');
const payNowBtn = document.querySelector('#payNowBtn');

if (!reservation?.reservationId) {
  window.location.href = 'index.html';
}

renderBookingSummary('#paymentSummary', booking, reservation);
const extra = document.querySelector('#paymentSummary .form-card');
if (extra) {
  const block = document.createElement('div');
  block.className = 'message-box info mt-2';
  block.innerHTML = `<h3 class="mt-0">Amount to pay</h3><p class="mb-0">${money(reservation.totalAmount, reservation.currency || booking.currency || 'INR')}</p>`;
  extra.appendChild(block);
}

function setStatus(title, text, kind = 'info') {
  statusBox.className = `message-box ${kind}`;
  statusBox.innerHTML = `<h3 class="mt-0">${title}</h3><p class="mb-0">${text}</p>`;
  statusBox.classList.remove('hidden');
}

payNowBtn.addEventListener('click', async () => {
  payNowBtn.disabled = true;
  payNowBtn.textContent = 'Processing payment...';
  try {
    const payload = await api.payment({
      reservationId: reservation.reservationId,
      amount: reservation.totalAmount,
      currency: reservation.currency || booking.currency || 'INR',
    });

    const status = String(payload.status || payload.paymentStatus || 'SUCCESS').toUpperCase();
    if (status !== 'SUCCESS') {
      setStatus('Payment failed', payload.message || 'Returning to homepage. Seat lock will expire naturally.', 'danger');
      setTimeout(() => {
        storage.clearFlow();
        window.location.href = 'index.html';
      }, 1000);
      return;
    }

    storage.setPayment({
      paymentId: payload.paymentId || payload.id || crypto.randomUUID(),
      status,
      raw: payload,
    });
    window.location.href = 'booking-processing.html';
  } catch (error) {
    setStatus('Payment failed', `${error.message}. Returning to homepage.`, 'danger');
    setTimeout(() => {
      storage.clearFlow();
      window.location.href = 'index.html';
    }, 1200);
  } finally {
    payNowBtn.disabled = false;
    payNowBtn.textContent = 'Pay now';
  }
});
