import { api } from '../api.js';
import { requireAuth } from '../auth.js';
import { storage } from '../storage.js';
import { APP_CONFIG } from '../config.js';
import { qs, renderBookingSummary, setText } from './common.js';

if (!requireAuth()) {
  throw new Error('Auth required');
}

const statusBox = document.querySelector('#queueStatusBox');
const leaveBtn = document.querySelector('#leaveQueueBtn');
let pollTimer = null;

const booking = storage.getBooking();
const eventId = qs('event_id') || qs('eventId') || booking.eventId;
const categoryId = qs('category_id') || qs('categoryId') || booking.categoryId;

if (!eventId || !categoryId) {
  statusBox.innerHTML = '<h3 class="mt-0">Missing booking context</h3><p class="mb-0">Go back to event details and choose a category again.</p>';
  leaveBtn.classList.add('hidden');
} else {
  storage.patchBooking({ eventId, categoryId });
  setText('#queueEventId', eventId);
  setText('#queueCategoryId', categoryId);
  renderBookingSummary('#queueSummary', storage.getBooking());
}

function setStatus(title, text, kind = 'info') {
  statusBox.className = `message-box ${kind}`;
  statusBox.innerHTML = `<h3 class="mt-0">${title}</h3><p class="mb-0">${text}</p>`;
}

async function releaseAndExit() {
  const current = storage.getBooking();
  try {
    if (current.sessionId) {
      await api.queueRelease({ eventId: current.eventId, categoryId: current.categoryId, sessionId: current.sessionId });
    }
  } catch (_) {
    // best-effort
  } finally {
    storage.clearFlow();
    window.location.href = 'index.html';
  }
}

leaveBtn.addEventListener('click', releaseAndExit);

async function pollAllowed(current) {
  try {
    const payload = await api.queuePoll({
      eventId: current.eventId,
      categoryId: current.categoryId,
      sessionId: current.sessionId,
      bookingToken: current.bookingToken,
    });

    const status = payload.status || payload.queueStatus || 'WAITING';
    if (status === 'ALLOWED') {
      storage.patchBooking({
        bookingToken: payload.bookingToken || current.bookingToken,
        sessionId: payload.sessionId || current.sessionId,
      });
      setStatus('Queue released', 'Backend allowed this session to continue into seat selection.', 'success');
      setTimeout(() => {
        window.location.href = `seats.html?event_id=${encodeURIComponent(current.eventId)}&category_id=${encodeURIComponent(current.categoryId)}`;
      }, 500);
      return;
    }

    if (status === 'SOLD_OUT') {
      setStatus('Sold out', payload.message || 'This category is sold out.', 'warning');
      return;
    }

    if (status === 'EXPIRED') {
      window.location.href = 'session-expired.html';
      return;
    }

    setStatus('Waiting for release', payload.message || 'Still waiting in queue. Polling again shortly...', 'info');
    pollTimer = window.setTimeout(() => pollAllowed(storage.getBooking()), (payload.pollAfterSeconds || APP_CONFIG.queuePollFallbackSeconds) * 1000);
  } catch (error) {
    setStatus('Queue polling failed', error.message, 'danger');
  }
}

async function enterQueue() {
  try {
    const payload = await api.queueEnter({ eventId, categoryId });
    storage.patchBooking({
      sessionId: payload.sessionId || null,
      bookingToken: payload.bookingToken || null,
      queueStatus: payload.status || 'WAITING',
    });
    setText('#queueSessionId', payload.sessionId || 'Pending');

    if ((payload.status || '').toUpperCase() === 'ALLOWED') {
      setStatus('Immediate release', payload.message || 'Queue allowed this session immediately.', 'success');
      window.location.href = `seats.html?event_id=${encodeURIComponent(eventId)}&category_id=${encodeURIComponent(categoryId)}`;
      return;
    }

    if ((payload.status || '').toUpperCase() === 'SOLD_OUT') {
      setStatus('Sold out', payload.message || 'Tickets are sold out for this category.', 'warning');
      return;
    }

    setStatus('In queue', payload.message || 'Waiting for available seats.', 'info');
    pollTimer = window.setTimeout(() => pollAllowed(storage.getBooking()), (payload.pollAfterSeconds || APP_CONFIG.queuePollFallbackSeconds) * 1000);
  } catch (error) {
    setStatus('Queue entry failed', error.message, 'danger');
  }
}

if (eventId && categoryId) enterQueue();
window.addEventListener('beforeunload', () => {
  if (pollTimer) window.clearTimeout(pollTimer);
});
