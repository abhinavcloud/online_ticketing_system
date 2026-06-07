import { api } from '../api.js';
import { asArray } from './common.js';

function normalizeLocation(location) {
  return {
    id: location.locationId ?? location.id ?? location.location_id ?? '',
    name: location.locationName ?? location.name ?? location.location_name ?? 'Unnamed location',
  };
}

function renderCard(rawLocation) {
  const location = normalizeLocation(rawLocation);

  return `
    <a class="card" href="events.html?location_id=${encodeURIComponent(location.id)}&location_name=${encodeURIComponent(location.name)}">
      <span class="badge brand mb-2">Location</span>
      <h3 class="card-title">${location.name}</h3>
      <p class="helper-text mb-0">Browse all events for this location.</p>
    </a>
  `;
}

(async function init() {
  const target = document.querySelector('#locationsGrid');
  target.innerHTML = '<div class="loader"></div>';

  try {
    const payload = await api.getLocations();
    const items = asArray(payload.locations || payload);

    target.innerHTML = items.length
      ? items.map(renderCard).join('')
      : '<div class="message-box warning"><p class="mb-0">No locations returned.</p></div>';
  } catch (error) {
    target.innerHTML = `
      <div class="message-box danger">
        <h3 class="mt-0">Failed to load locations</h3>
        <p class="mb-0">${error.message}</p>
      </div>
    `;
  }
})();
