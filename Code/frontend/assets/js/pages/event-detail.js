import { api } from '../api.js';
import { storage } from '../storage.js';
import { getAuthState } from '../auth.js';
import { qs, money } from './common.js';

function normalizeEventDetail(eventData) {
  return {
    eventId: eventData.eventId ?? eventData.id ?? '',
    eventName: eventData.eventName ?? eventData.name ?? 'Untitled event',
    eventDescription: eventData.eventDescription ?? eventData.description ?? '',
    dateTime: eventData.dateTime ?? eventData.eventDate ?? eventData.event_date ?? '',
    status: eventData.status ?? 'EVENT',
    venueId: eventData.venue?.venueId ?? eventData.venueId ?? '',
    venueName: eventData.venue?.venueName ?? eventData.venueName ?? eventData.venue_name ?? '—',
    locationId: eventData.location?.locationId ?? eventData.locationId ?? '',
    locationName: eventData.location?.locationName ?? eventData.locationName ?? eventData.location_name ?? '—',
    performers: Array.isArray(eventData.performers) ? eventData.performers : [],
    ticketCategories: Array.isArray(eventData.ticketCategories) ? eventData.ticketCategories : [],
  };
}

function normalizeCategory(category) {
  return {
    categoryId: category.categoryId ?? category.id ?? '',
    categoryName: category.categoryName ?? category.name ?? 'Category',
    price: category.price ?? category.unitPrice ?? 0,
    currency: category.currency ?? 'INR',
    availableTickets: category.availableTickets ?? 0,
    totalTickets: category.totalTickets ?? 0,
    status: category.status ?? 'AVAILABLE',
  };
}

function categoryCard(eventData, rawCategory) {
  const category = normalizeCategory(rawCategory);

  return `
    <div class="card">
      <span class="badge brand">${category.categoryName}</span>
      <h3 class="card-title mt-2">${money(category.price, category.currency)}</h3>
      <p class="helper-text">Category-specific seat selection begins only after queue release.</p>
      <p class="helper-text mb-0">Available: ${category.availableTickets} / Total: ${category.totalTickets}</p>
      <button class="primary-btn mt-2" data-book-btn
        data-event-id="${eventData.eventId}"
        data-event-name="${(eventData.eventName || '').replace(/"/g, '&quot;')}"
        data-event-date="${(eventData.dateTime || '').replace(/"/g, '&quot;')}"
        data-venue-name="${(eventData.venueName || '').replace(/"/g, '&quot;')}"
        data-category-id="${category.categoryId}"
        data-category-name="${category.categoryName.replace(/"/g, '&quot;')}"
        data-price="${category.price}"
        data-currency="${category.currency}">
        Book this category
      </button>
    </div>
  `;
}

(async function init() {
  const eventId = qs('event_id') || qs('eventId');
  const target = document.querySelector('#eventDetailContainer');

  if (!eventId) {
    target.innerHTML = '<div class="message-box warning"><h3 class="mt-0">Missing event id</h3><p class="mb-0">Open this page with event_id query parameter.</p></div>';
    return;
  }

  try {
    const rawEventData = await api.getEventDetail(eventId);
    const eventData = normalizeEventDetail(rawEventData);
    const statusBadgeClass = String(eventData.status || '').toUpperCase() === 'ON_SALE' ? 'success' : 'warning';

    target.innerHTML = `
      <div class="checkout-layout">
        <div>
          <span class="badge ${statusBadgeClass}">${eventData.status || 'EVENT'}</span>
          <h1 class="hero-title mt-2">${eventData.eventName}</h1>
          <p class="hero-subtitle">${eventData.eventDescription || 'No description returned by the event detail API.'}</p>

          <div class="metrics-grid mt-3">
            <div class="metric"><div class="muted">Date</div><div>${eventData.dateTime || '—'}</div></div>
            <div class="metric"><div class="muted">Venue</div><div>${eventData.venueName}</div></div>
            <div class="metric"><div class="muted">Location</div><div>${eventData.locationName}</div></div>
          </div>

          <section class="section mt-3">
            <div class="section-header">
              <div>
                <h2 class="section-title">Ticket categories</h2>
                <p class="section-subtitle mb-0">Booking flow is category-specific. Choose one category to enter queue.</p>
              </div>
            </div>
            <div class="grid-3">
              ${eventData.ticketCategories.length
                ? eventData.ticketCategories.map(category => categoryCard(eventData, category)).join('')
                : `<div class="message-box warning"><h3 class="mt-0">No category data returned</h3><p class="mb-0">This frontend expects event detail API to return ticketCategories.</p></div>`}
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