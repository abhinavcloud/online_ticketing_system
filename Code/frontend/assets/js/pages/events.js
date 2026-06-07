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

function normalizeEvent(event) {
  return {
    eventId: event.eventId ?? event.id ?? '',
    eventName: event.eventName ?? event.name ?? 'Untitled event',
    dateTime: event.dateTime ?? event.eventDate ?? event.event_date ?? 'Date unavailable',
    category: event.category ?? '',
    venueName: event.venue?.venueName ?? event.venueName ?? event.venue_name ?? 'Venue unavailable',
    locationName: event.location?.locationName ?? event.locationName ?? event.location_name ?? 'Location unavailable',
    performers: Array.isArray(event.performers) ? event.performers : [],
  };
}

function renderEvent(rawEvent) {
  const event = normalizeEvent(rawEvent);

  const performerMarkup = event.performers.length
    ? `<div class="inline-actions mt-2">${event.performers.map(p => `<span class="badge">${p.performerName}</span>`).join('')}</div>`
    : '';

  return `
    <a class="card" href="event-detail.html?event_id=${encodeURIComponent(event.eventId)}">
      <span class="badge brand">${event.category || 'EVENT'}</span>
      <h3 class="card-title mt-2">${event.eventName}</h3>
      <div class="meta-stack muted">
        <span>${event.dateTime}</span>
        <span>${event.venueName}</span>
        <span>${event.locationName}</span>
      </div>
      ${performerMarkup}
      <p class="helper-text mt-2 mb-0">Open event details to continue.</p>
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
    const items = asArray(payload.events || payload);

    grid.innerHTML = items.length
      ? items.map(renderEvent).join('')
      : '<div class="message-box warning"><p class="mb-0">No events returned for current filters.</p></div>';
  } catch (error) {
    grid.innerHTML = `<div class="message-box danger"><h3 class="mt-0">Failed to load events</h3><p class="mb-0">${error.message}</p></div>`;
  }
}

document.querySelector('#applyFiltersBtn').addEventListener('click', loadEvents);

if (locationInput.value) {
  loadEvents();
}
``