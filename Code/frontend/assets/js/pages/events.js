import { api } from '../api.js';
import { asArray, qs } from './common.js';

const locationInput = document.querySelector('#locationId');
const venueInput = document.querySelector('#venueId');
const performerInput = document.querySelector('#performerId');
const grid = document.querySelector('#eventsGrid');
const status = document.querySelector('#eventsStatus');

locationInput.value = qs('location_id') || qs('locationId') || '';
venueInput.value = qs('venue_id') || qs('venueId') || '';
performerInput.value = qs('performer_id') || qs('performerId') || '';

function renderEvent(event) {
  const eventId = event.id || event.eventId;
  const categoryMarkup = Array.isArray(event.categories) && event.categories.length
    ? `<div class="inline-actions mt-2">${event.categories.map(c => `<span class="badge">${c.name || c.categoryName}: ${c.currency || 'INR'} ${c.price ?? ''}</span>`).join('')}</div>`
    : '';

  return `
    <a class="card" href="event-detail.html?event_id=${encodeURIComponent(eventId)}">
      <span class="badge ${String(event.status || '').toUpperCase() === 'ON_SALE' ? 'success' : 'warning'}">${event.status || 'EVENT'}</span>
      <h3 class="card-title mt-2">${event.name || 'Untitled event'}</h3>
      <div class="meta-stack muted">
        <span>${event.event_date || event.eventDate || 'Date unavailable'}</span>
        <span>${event.venue_name || event.venueName || 'Venue unavailable'}</span>
        <span>${event.location_name || event.locationName || 'Location unavailable'}</span>
      </div>
      ${categoryMarkup}
      <p class="helper-text mt-2 mb-0">${event.description || 'Open event details to continue.'}</p>
    </a>
  `;
}

async function loadEvents() {
  grid.innerHTML = '<div class="loader"></div>';
  status.classList.add('hidden');
  const locationId = locationInput.value.trim();
  const venueId = venueInput.value.trim();
  const performerId = performerInput.value.trim();

  if (!locationId) {
    grid.innerHTML = '<div class="message-box warning"><p class="mb-0">This backend flow expects location-driven event browse. Provide a location ID first.</p></div>';
    return;
  }

  try {
    const payload = await api.getEvents({ locationId, venueId, performerId });
    const items = asArray(payload);
    grid.innerHTML = items.length ? items.map(renderEvent).join('') : '<div class="message-box warning"><p class="mb-0">No events returned for current filters.</p></div>';
  } catch (error) {
    grid.innerHTML = `<div class="message-box danger"><h3 class="mt-0">Failed to load events</h3><p class="mb-0">${error.message}</p></div>`;
  }
}

document.querySelector('#applyFiltersBtn').addEventListener('click', loadEvents);
if (locationInput.value) loadEvents();
