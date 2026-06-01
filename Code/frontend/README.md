# Static Frontend - Online Ticketing System

This is a plain HTML/CSS/JS static frontend intended to demonstrate the backend capabilities of the online ticketing system.

## Runtime values
Update `assets/js/config.js` with the real values for:

- API Gateway base URL
- Cognito Hosted UI domain
- Cognito client ID
- Redirect URI
- Logout URI
- AWS region

## Hosting
This project is designed for static hosting on S3 + CloudFront.

## Routing model
This frontend uses static pages plus query-string navigation, for example:

- `event-detail.html?event_id=<uuid>`
- `queue.html?event_id=<uuid>&category_id=<uuid>`
- `seats.html?event_id=<uuid>&category_id=<uuid>`

## Notes
- Browse pages are public.
- Queue, seats, reservation, payment, and booking confirmation require Cognito login.
- Seat selection UI is capped at 5 seats.
- On payment failure or confirmation failure the frontend returns to the homepage and leaves cleanup to backend TTL expiry.
- No My Tickets page is included in this phase.
