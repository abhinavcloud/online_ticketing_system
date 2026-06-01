import { api } from '../api.js';
import { storage } from '../storage.js';
import { getAuthState } from '../auth.js';
import { qs, money } from './common.js';

function categoryCard(eventData, category) {
  const categoryId = category.id || category.categoryId || '';
  const categoryName = category.name || category.categoryName || 'Category';
  const price = category.price ?? category.unitPrice ?? 0;
  const currency = category.currency || 'INR';
  return `
    <div class="card">
      <span class="badge brand">${categoryName}</span>
      <h3 class="card-title mt-2">${money(price, currency)}</h3>
      <p class="helper-text">Category-specific seat selection begins only after queue release.</p>
      <button class="primary-btn mt-2" data-book-btn
        data-event-id="${eventData.id}"
        data-event-name="${(eventData.name || '').replace(/"/g, '&quot;')}"
        data-event-date="${(eventData.event_date || eventData.eventDate || '').replace(/"/g, '&quot;')}"
        data-venue-name="${(eventData.venue_name || eventData.venueName || '').replace(/"/g, '&quot;')}"
        data-category-id="${categoryId}"
        data-category-name="${categoryName.replace(/"/g, '&quot;')}"
        data-price="${price}"
        data-currency="${currency}">
        Book this category
      </button>
    </div>
  `;
}

function normalizeCategories(eventData) {
  if (Array.isArray(eventData.categories)) return eventData.categories;
  if (Array.isArray(eventData.event_categories)) return eventData.event_categories;
  return [];
}

(async function init() {
  const eventId = qs('event_id') || qs('eventId');
  const target = document.querySelector('#eventDetailContainer');

  if (!eventId) {
    target.innerHTML = '<div class="message-box warning"><h3 class="mt-0">Missing event id</h3><p class="mb-0">Open this page with event_id query parameter.</p></div>';
    return;
  }

  try {
    const eventData = await api.getEventDetail(eventId);
    const categories = normalizeCategories(eventData);
    const statusBadgeClass = String(eventData.status || '').toUpperCase() === 'ON_SALE' ? 'success' : 'warning';

    target.innerHTML = `
      <div class="checkout-layout">
        <div>
          <span class="badge ${statusBadgeClass}">${eventData.status || 'EVENT'}</span>
          <h1 class="hero-title mt-2">${eventData.name || 'Untitled event'}</h1>
          <p class="hero-subtitle">${eventData.description || 'No description returned by the event detail API.'}</p>

          <div class="metrics-grid mt-3">
            <div class="metric"><div class="muted">Date</div><div>${eventData.event_date || eventData.eventDate || '—'}</div></div>
            <div class="metric"><div class="muted">Venue</div><div>${eventData.venue_name || eventData.venueName || '—'}</div></div>
            <div class="metric"><div class="muted">Location</div><div>${eventData.location_name || eventData.locationName || '—'}</div></div>
          </div>

          <section class="section mt-3">
            <div class="section-header">
              <div>
                <h2 class="section-title">Ticket categories</h2>
                <p class="section-subtitle mb-0">Booking flow is category-specific. Choose one category to enter queue.</p>
              </div>
            </div>
            <div class="grid-3">
              ${categories.length
                ? categories.map(category => categoryCard(eventData, category)).join('')
                : `<div class="message-box warning"><h3 class="mt-0">No category data returned</h3><p class="mb-0">This frontend expects event detail API to include category list. If your Lambda returns categories under a different property, update the renderer accordingly.</p></div>`}
            </div>
          </section>
        </div>

        <aside>
          <div class="form-card sidebar-sticky">
            <h3 class="mt-0">Booking rules</h3>
            <ul class="summary-list">
              <li class="summary-item"><span class="muted">Authentication</span><strong>Cognito Hosted UI</strong></li>
              <li class="summary-item"><span class="muted">Queue</span><strong>Required</strong></li>
              <li class="summary-item"><span class="muted">Seat lock</span><strong>Cache only</strong></li>
              <li class="summary-item"><span class="muted">Reservation</span><strong>All or nothing</strong></li>
              <li class="summary-item"><span class="muted">Phase 1</span><strong>No My Tickets page</strong></li>
            </ul>
          </div>
        </aside>
      </div>
    `;

    document.querySelectorAll('[data-book-btn]').forEach(btn => {
      btn.addEventListener('click', () => {
        storage.clearFlow();
        storage.setBooking({
          eventId: btn.dataset.eventId,
          eventName: btn.dataset.eventName,
          eventDate: btn.dataset.eventDate,
          venueName: btn.dataset.venueName,
          categoryId: btn.dataset.categoryId,
          categoryName: btn.dataset.categoryName,
          unitPrice: Number(btn.dataset.price || 0),
          currency: btn.dataset.currency || 'INR',
          selectedSeats: [],
        });

        const authState = getAuthState();
        const targetUrl = `queue.html?event_id=${encodeURIComponent(btn.dataset.eventId)}&category_id=${encodeURIComponent(btn.dataset.categoryId)}`;
        window.location.href = authState.authenticated ? targetUrl : 'login.html';
      });
    });
  } catch (error) {
    target.innerHTML = `<div class="message-box danger"><h3 class="mt-0">Failed to load event detail</h3><p class="mb-0">${error.message}</p></div>`;
  }
})();
