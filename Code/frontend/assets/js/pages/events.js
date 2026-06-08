import { api } from '../api.js';
import { asArray, qs } from './common.js';

const locationSelect = document.querySelector('#locationSelect');
const venueSelect = document.querySelector('#venueSelect');
const performerSelect = document.querySelector('#performerSelect');
const applyFiltersBtn = document.querySelector('#applyFiltersBtn');
const clearFiltersBtn = document.querySelector('#clearFiltersBtn');
const grid = document.querySelector('#eventsGrid');
const statusBox = document.querySelector('#eventsStatus');

const initialLocationId = qs('location_id') || qs('locationId') || qs('location') || '';
const initialVenueId = qs('venue_id') || qs('venueId') || qs('venue') || '';
const initialPerformerId = qs('performer_id') || qs('performerId') || qs('performer') || '';

function showStatus(title, text, kind = 'info') {
  if (!statusBox) return;

  statusBox.className = `message-box ${kind}`;
  statusBox.innerHTML = `<h3 class="mt-0">${title}</h3><p class="mb-0">${text}</p>`;
  statusBox.classList.remove('hidden');
}

function hideStatus() {
  if (!statusBox) return;

  statusBox.classList.add('hidden');
  statusBox.innerHTML = '';
}

function setLoading(message = 'Loading events...') {
  if (!grid) return;

  grid.innerHTML = `
    <div class="message-box info">
      <div class="loader"></div>
      <p class="mt-2 mb-0">${message}</p>
    </div>
  `;
}

function normalizeLocation(location) {
  return {
    id: location.locationId || location.id || location.location_id || '',
    name: location.locationName || location.name || location.location_name || 'Unknown location',
  };
}

function normalizeVenue(venue) {
  return {
    id: venue.venueId || venue.id || venue.venue_id || '',
    name: venue.venueName || venue.name || venue.venue_name || 'Unknown venue',
  };
}

function normalizePerformer(performer) {
  return {
    id: performer.performerId || performer.id || performer.performer_id || '',
    name: performer.performerName || performer.name || performer.performer_name || 'Unknown performer',
  };
}

function normalizeEvent(event) {
  return {
    eventId: event.eventId ?? event.id ?? '',
    eventName: event.eventName ?? event.name ?? 'Untitled event',
    dateTime: event.dateTime ?? event.eventDate ?? event.event_date ?? 'Date unavailable',
    category: event.category ?? event.eventType ?? event.event_type ?? 'EVENT',
    venueName: event.venue?.venueName ?? event.venueName ?? event.venue_name ?? 'Venue unavailable',
    locationName: event.location?.locationName ?? event.locationName ?? event.location_name ?? 'Location unavailable',
    performers: Array.isArray(event.performers) ? event.performers : [],
  };
}

function getItems(payload, preferredKey) {
  if (Array.isArray(payload)) {
    return payload;
  }

  if (Array.isArray(payload?.[preferredKey])) {
    return payload[preferredKey];
  }

  if (Array.isArray(payload?.items)) {
    return payload.items;
  }

  if (Array.isArray(payload?.data)) {
    return payload.data;
  }

  return asArray(payload);
}

function clearSelect(select, placeholder) {
  select.innerHTML = `<option value="">${placeholder}</option>`;
}

function populateSelect(select, items, placeholder, normalizer) {
  clearSelect(select, placeholder);

  items
    .map(normalizer)
    .filter((item) => item.id)
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true }))
    .forEach((item) => {
      const option = document.createElement('option');
      option.value = item.id;
      option.textContent = item.name;
      select.appendChild(option);
    });
}

function renderEvent(rawEvent) {
  const event = normalizeEvent(rawEvent);

  const performerMarkup = event.performers.length
    ? `
      <div class="inline-actions mt-2">
        ${event.performers
          .map((performer) => {
            const name =
              performer.performerName ||
              performer.name ||
              performer.performer_name ||
              'Performer';
            return `<span class="badge">${name}</span>`;
          })
          .join('')}
      </div>
    `
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

async function loadLocations() {
  clearSelect(locationSelect, 'Loading locations...');
  locationSelect.disabled = true;

  try {
    const payload = await api.getLocations();
    const locations = getItems(payload, 'locations');

    populateSelect(locationSelect, locations, 'Choose a location', normalizeLocation);
    locationSelect.disabled = false;

    if (initialLocationId) {
      locationSelect.value = initialLocationId;
    }

    if (!locationSelect.value && locationSelect.options.length > 1) {
      locationSelect.selectedIndex = 1;
    }

    if (locationSelect.value) {
      await loadDependentFilters(locationSelect.value, {
        venueId: initialVenueId,
        performerId: initialPerformerId,
      });

      await loadEvents();
    } else {
      grid.innerHTML = `
        <div class="message-box warning">
          <p class="mb-0">No locations are available right now.</p>
        </div>
      `;
    }
  } catch (error) {
    locationSelect.disabled = false;
    clearSelect(locationSelect, 'Unable to load locations');

    grid.innerHTML = `
      <div class="message-box danger">
        <h3 class="mt-0">Unable to load locations</h3>
        <p class="mb-0">${error.message || 'Please try again.'}</p>
      </div>
    `;
  }
}

async function loadDependentFilters(locationId, selectedValues = {}) {
  clearSelect(venueSelect, 'All venues');
  clearSelect(performerSelect, 'All performers');

  venueSelect.disabled = true;
  performerSelect.disabled = true;

  if (!locationId) {
    return;
  }

  try {
    const [venuesPayload, performersPayload] = await Promise.all([
      api.getVenues({ locationId }),
      api.getPerformers({ locationId }),
    ]);

    const venues = getItems(venuesPayload, 'venues');
    const performers = getItems(performersPayload, 'performers');

    populateSelect(venueSelect, venues, 'All venues', normalizeVenue);
    populateSelect(performerSelect, performers, 'All performers', normalizePerformer);

    venueSelect.disabled = false;
    performerSelect.disabled = false;

    if (selectedValues.venueId) {
      venueSelect.value = selectedValues.venueId;
    }

    if (selectedValues.performerId) {
      performerSelect.value = selectedValues.performerId;
    }
  } catch (error) {
    venueSelect.disabled = false;
    performerSelect.disabled = false;

    showStatus(
      'Some filters could not be loaded',
      error.message || 'You can still search events by location.',
      'warning'
    );
  }
}

async function loadEvents() {
  hideStatus();
  setLoading();

  const locationId = locationSelect.value;
  const venueId = venueSelect.value;
  const performerId = performerSelect.value;

  if (!locationId) {
    grid.innerHTML = `
      <div class="message-box warning">
        <p class="mb-0">Please choose a location to see available events.</p>
      </div>
    `;
    return;
  }

  try {
    const payload = await api.getEvents({
      locationId,
      venueId,
      performerId,
    });

    const items = getItems(payload, 'events');

    grid.innerHTML = items.length
      ? items.map(renderEvent).join('')
      : `
        <div class="message-box warning">
          <p class="mb-0">No events found for the selected filters.</p>
        </div>
      `;
  } catch (error) {
    grid.innerHTML = `
      <div class="message-box danger">
        <h3 class="mt-0">Unable to load events</h3>
        <p class="mb-0">${error.message || 'Please try again.'}</p>
      </div>
    `;
  }
}

locationSelect.addEventListener('change', async () => {
  await loadDependentFilters(locationSelect.value);
  await loadEvents();
});

applyFiltersBtn.addEventListener('click', loadEvents);

clearFiltersBtn.addEventListener('click', async () => {
  venueSelect.value = '';
  performerSelect.value = '';
  await loadEvents();
});

loadLocations();