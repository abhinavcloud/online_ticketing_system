import { wireAuthUi, getAuthState } from '../auth.js';
import { storage } from '../storage.js';

wireAuthUi();
if (!storage.getReturnTo()) {
  const booking = storage.getBooking();
  if (booking?.eventId && booking?.categoryId) {
    storage.setReturnTo(`queue.html?event_id=${encodeURIComponent(booking.eventId)}&category_id=${encodeURIComponent(booking.categoryId)}`);
  }
}
if (getAuthState().authenticated) {
  window.location.href = storage.getReturnTo() || 'index.html';
}
