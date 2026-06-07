import { api } from '../api.js';
import { asArray } from './common.js';

function normalizeLocation(location) {
  return {
    id: location.locationId ?? location.id ?? location.location_id ?? '',
    name: location.locationName ?? location.name ?? location.location_name ?? 'Unnamed location',
  };
}

function normalizeEvent(event) {
  return {
    id: event.eventId ?? event.id ?? '',
    name: event.eventName ?? event.name ?? 'Untitled event',
    dateTime: event.dateTime ?? event.eventDate ?? event.event_date ?? '',
    venueName: event.venue?.venueName ?? event.venueName ?? event.venue_name ?? 'Venue not available',
    locationName: event.location?.locationName ?? event.locationName ?? event.location_name ?? 'Location not available',
    category: event.category ?? '',
    performers: Array.isArray(event.performers) ? event.performers : [],
  };
}

function locationCard(rawLocation) {
  const location = normalizeLocation(rawLocation);

  return `
    <a class="card" href="events.html?location_id=${encodeURIComponent(location.id)}&location_name=${encodeURIComponent(location.name)}">
      <span class="badge brand mb-2">Location</span>
      <h3 class="card-title">${location.name}</h3>
      <p class="helper-text mb-0">Browse venues, performers, and events for this city.</p>
    </a>
  `;
}

function eventCard(rawEvent) {
  const event = normalizeEvent(rawEvent);

  return `
    <a class="card" href="event-detail.html?event_id=${encodeURIComponent(event.id)}">
      <span class="badge">Event</span>
      <h3 class="card-title mt-2">${event.name}</h3>
      <div class="meta-stack muted">
        <span>${event.dateTime || 'Date not available'}</span>
        <span>${event.venueName}</span>
        <span>${event.locationName}</span>
      </div>
      <p class="helper-text mb-0 mt-2">${event.category || 'Open the event details page to start booking.'}</p>
    </a>
  `;
}

async function init() {
  try {
    const locationsPayload = await api.getLocations({ page: 1, pageSize: 6 });
    const locations = asArray(locationsPayload.locations || locationsPayload);

    document.querySelector('#homeLocations').innerHTML =
      locations.slice(0, 6).map(locationCard).join('') ||
      '<div class="message-box warning"><p class="mb-0">No locations returned by the browse service.</p></div>';

    if (locations.length > 0) {
      const firstLocation = normalizeLocation(locations[0]);

      try {
        const eventsPayload = await api.getEvents({
          locationId: firstLocation.id,
          page: 1,
          pageSize: 6,
        });

        const events = asArray(eventsPayload.events || eventsPayload);

        document.querySelector('#homeEvents').innerHTML =
          events.slice(0, 6).map(eventCard).join('') ||
          '<div class="message-box warning"><p class="mb-0">No events returned for the first available location.</p></div>';
      } catch (eventErr) {
        document.querySelector('#homeEvents').innerHTML =
          `<div class="message-box warning"><h3 class="mt-0">Events not loaded</h3><p class="mb-0">${eventErr.message}</p></div>`;
      }
    } else {
      document.querySelector('#homeEvents').innerHTML =
        '<div class="message-box warning"><p class="mb-0">No events can be shown because no location was returned.</p></div>';
    }
  } catch (error) {
    document.querySelector('#homeLocations').innerHTML =
      `<div class="message-box danger"><h3 class="mt-0">Browse API error</h3><p class="mb-0">${error.message}</p></div>`;
    document.querySelector('#homeEvents').innerHTML = '';
  }
}

init();