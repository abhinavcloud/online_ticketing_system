# Requirements for an Online Ticketing System

---

## Functional Requirements

### User Role
- User must be able to authenticate via a Federated Login or Username/Password

- User must be able to select the Location

- User must be able to browse by Events or Performers or Venue for each location

- User must be able to see all the details by
 * Events (DateTime, Performer, Ticket Price by Category, Seat Map if applicable)
 * Performers (Events by Date Time should redirect to specific event, Venue)
 * Venue (Events and Performers by Date Time should redirect to specific event)

- User must be able to select the number of tickets and the total price should be diplsayed and on click of "Book Ticket" should redirect to Payment Gateway

- User should get a notification on Email/SMS on successful or failed attempts at booking ticket

### Admin Role

- Admin should be able to login with an admin user.

- Admin should be able to create an Event with Performers with Venue, Locations, Total Numbers of Tickets and Price of Tickets by Category

- Admin should be able to delete an event

---

### Non Functional Requirements

- The Read to Write ratio is 100:1. The system is read heavy with heavy event browsing activity

- The book ticket activity should be highly consistent i.e. no double booking

- The browsing event activity should be highly available.

- Should be able to handle suddent surge of traffic on poppular events. Sacalibility to handle surges.

---

### Out of Scope
- Payment Gateway integration and actual Payment
- PII 
- GDPR Compliance
- Fault Tolera