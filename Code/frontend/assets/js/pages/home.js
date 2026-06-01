import { api } from '../api.js';
import { asArray, showStatus } from './common.js';

function locationCard(location) {
  return `
    <a class="card" href="events.html?location_id=${encodeURIComponent(location.id)}&location_name=${encodeURIComponent(location.name)}">
      <span class="badge brand mb-2">Location</span>
      <h3 class="card-title">${location.name || 'Unnamed location'}</h3>
      <p class="helper-text mb-0">Browse venues, performers, and events for this city.</p>
    </a>
  `;
}

function eventCard(event) {
  const id = event.id || event.eventId || '';
  return `
    <a class="card" href="event-detail.html?event_id=${encodeURIComponent(id)}">
      <span class="badge">Event</span>
      <h3 class="card-title mt-2">${event.name || 'Untitled event'}</h3>
      <div class="meta-stack muted">
        <span>${event.event_date || event.eventDate || 'Date not available'}</span>
        <span>${event.venue_name || event.venueName || 'Venue not available'}</span>
      </div>
      <p class="helper-text mb-0 mt-2">${event.description || 'Open the event details page to start booking.'}</p>
    </a>
  `;
}

async function init() {
  try {
    const locationsPayload = await api.getLocations({ page: 1, pageSize: 6 });
    const locations = asArray(locationsPayload);
    document.querySelector('#homeLocations').innerHTML = locations.slice(0, 6).map(locationCard).join('') || '<div class="message-box warning"><p class="mb-0">No locations returned by the browse service.</p></div>';

    if (locations.length > 0) {
      try {
        const eventsPayload = await api.getEvents({ locationId: locations[0].id, page: 1, pageSize: 6 });
        const events = asArray(eventsPayload);
        document.querySelector('#homeEvents').innerHTML = events.slice(0, 6).map(eventCard).join('') || '<div class="message-box warning"><p class="mb-0">No events returned for the first available location.</p></div>';
      } catch (eventErr) {
        document.querySelector('#homeEvents').innerHTML = `<div class="message-box warning"><h3 class="mt-0">Events not loaded</h3><p class="mb-0">${eventErr.message}</p></div>`;
      }
    } else {
      document.querySelector('#homeEvents').innerHTML = '<div class="message-box warning"><p class="mb-0">No events can be shown because no location was returned.</p></div>';
    }
  } catch (error) {
    document.querySelector('#homeLocations').innerHTML = `<div class="message-box danger"><h3 class="mt-0">Browse API error</h3><p class="mb-0">${error.message}</p></div>`;
    document.querySelector('#homeEvents').innerHTML = '';
  }
}

init();
