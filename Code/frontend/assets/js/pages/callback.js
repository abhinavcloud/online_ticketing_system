import { parseHostedUiCallback } from '../auth.js';

const result = parseHostedUiCallback();
const msg = document.querySelector('#callbackMessage');
if (!result.ok) {
  msg.textContent = result.error || 'Authentication callback failed.';
} else {
  msg.textContent = 'Authentication successful. Redirecting back to your booking flow...';
  setTimeout(() => {
    window.location.href = result.returnTo || 'index.html';
  }, 400);
}
