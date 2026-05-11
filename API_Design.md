# API Design Specifications
---

## Authentications
- User must be able to authenticate via a Federated Login or Username/Password


---
## Location Selection

- User must be able to select the Location
 
 ```json
 GET v1//location
```
```json
 Response:

{
  "page": 1,
  "pageSize": 10,
  "total": 20,
  "locations": [
    {
      "locationId": "location_001",
      "locationName": "ABC"
    }
  ]
}

```

---

## Browsing, and filtering Events, Performers, and Venue by Location

- User must be able to browse by Events or Performers or Venue for each location
- User must be able to see all the details by
 * Events (DateTime, Performer, Ticket Price by Category, Seat Map if applicable)
 * Performers (Events by Date Time should redirect to specific event, Venue)
 * Venue (Events and Performers by Date Time should redirect to specific event)

### Browse by Performers
```json
GET v1//performers?{location=location_id}
```
```json
Response:

{
  "page": 1,
  "pageSize": 10,
  "total": 50,
  "performers": [
    {
      "performerId": "performer_001",
      "performerName": "XYZ"
    }
  ]
}
```

### Browse by Venue
```json
GET v1//venue?{location=location_id}
```

```json
Response:

{
  "page": 1,
  "pageSize": 10,
  "total": 50,
  "venues": [
    {
      "venueId": "venue_001",
      "venueName": "Venue Name"
    }
  ]
}

```

### Browse by Events (filter by Performers And/Or Venue)
```json
GET v1//events?location=location_id&performer=perform_id&venue=venueId
```

```json
Response:

{
  "page": 1,
  "pageSize": 20,
  "total": 150,
  "events": [
    {
      "eventId": "event_001",
      "eventName": "Event Name",
      "dateTime": "2026-06-03T19:30:00+05:30",
      "category": "Concert",

      "location": {
        "locationId": "location_001",
        "locationName": "ABC"
      },

      "venue": {
        "venueId": "venue_001",
        "venueName": "Venue Name"
      },

      "performers": [
        {
          "performerId": "perf_001",
          "performerName": "Performer Name"
        }
      ]
    }
  ]
}
```

---

## Select an Event and Get Event Details

- User selects an Event and get all the event details

```json
GET v1//event/{eventId}
```

```json
Response

{
  "eventId": "event001",
  "eventName": "Event Name",
  "eventDescription": "Event Description",
  "dateTime": "2026-06-03T19:30:00+05:30",
  "status": "ON_SALE",

  "location": {
    "locationId": "location001",
    "locationName": "Location Name"
  },

  "venue": {
    "venueId": "venue_001",
    "venueName": "Name of the Venue"
  },

  "performers": [
    {
      "performerId": "perf_001",
      "performerName": "Name of the performer"
    }
  ],

  "ticketCategories": [
    {
      "categoryId": "category_001",
      "categoryName": "VIP",
      "price": 3000,
      "currency": "INR",
      "totalTickets": 500,
      "availableTickets": 100,
      "status": "AVAILABLE"
    },
    {
      "categoryId": "category_002",
      "categoryName": "General",
      "price": 500,
      "currency": "INR",
      "totalTickets": 2500,
      "availableTickets": 1500,
      "status": "AVAILABLE"
    }
  ],

  "seatMap": {
    "applicable": true,
    "type": "RESERVED_SEATING",
    "seatEndpoint": "/v1/events/event001/seats"
  }
}

```

---

## User selects a Category and the browse the seat and select the seats

- User Selects a Category from dorpdown and then selects a seat from seatmap

```json
GET /v1/events/{eventId}/seats?category_id=category_002
```

```json
Response:

{
  "eventId": "event001",
  "categoryId": "category_002",
  "asOf": "2026-05-11T09:14:16+05:30",

  "seats": [
    {
      "seatId": "A-01-01",
      "row": "A",
      "number": 1,
      "status": "AVAILABLE"
    },
    {
      "seatId": "Z-10-30",
      "row": "Z",
      "number": 30,
      "status": "BOOKED"
    },
    {
      "seatId": "Z-10-31",
      "row": "Z",
      "number": 31,
      "status": "LOCKED"
      "lockExpiresAt": "2026-05-11T09:20:00+05:30"
    }
  ]
}
```

---

## Reserve Ticket

- User is able to reserve tickets and navigate to Payment Gateway for Payments

```json
POST /reserveTicket
```

```json
Response:

```

---

## Book Ticket

- User makes a successful payment and has booked a ticket

```json
PUT /confirmTicket
```

```json

```

---

## Notify User

- User should get a notification on Email/SMS on successful or failed attempts at booking ticket
Notifcation Event via SES/SNS