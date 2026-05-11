- User must be able to authenticate via a Federated Login or Username/Password


- User must be able to select the Location
 
 ```json
 GET v1//location
```
```json
 Response:

 { 
    "page": 1
    "pageSize": 10
    "total" 20
    "location": [
        {
        "locationId": "location_001"
        "locationName": "ABC"
        }
    ]

 }
```

- User must be able to browse by Events or Performers or Venue for each location
- User must be able to see all the details by
 * Events (DateTime, Performer, Ticket Price by Category, Seat Map if applicable)
 * Performers (Events by Date Time should redirect to specific event, Venue)
 * Venue (Events and Performers by Date Time should redirect to specific event)

```json
GET v1//performers?{location=location_id}
```
```json
Response:

{ 
  "page": 1
  "pageSize": 10
  "total": 50
  "performers": [
        {
            "performerId": "performer_001"
            "performerName"" "XYZ"
        }
    ]
}
```

```json
GET v1//venue?{location=location_id}
```

```json
Response:
{
"page": 1
  "pageSize": 10
  "total": 50
  "venue": [
    {
        "venueId": "venue_001"
        "venueName": "venueName"

    }
  ]
}
```

```json
GET v1//events?location=location_id&performer=perform_id&venue=venueId
```

```json
Response:

{ "page": 1
  "pageSize": 20
  "total": 150
  "events": [
        {
            "eventId": "event_001"
            "eventName": "event_001_name"
            "dateTime": "2026-06-03T19:30:00+05:30"
            "location": "ABC"
            "categoy": "Concert"
            "venue": {
                "venueId": "venue_001"
                "venueName": "Venue Name"
            }
            "performers": [
                {
                    "performerId": "perf_001"
                    "performerName": "Performer Name
                }
            ]

           
        }
    ]
}
````

```json
GET v1//event/{eventId}

{
    "eventId": "event001"
    "eventName": "Event Name"
    "eventDescription": "Event Description"
    "dateTime": "2026-06-03T19:30:00+0
    "location": {
        "locationId": "location001"
        "locationName": "Location Name"
    }
    "venue": {
        "venueId": "venue_001"
        "venueName": "Name of the Venue
    }
        
    "performers": [
        
        {
            "performerId": "perf_001"
            "performerName": "Name of the performer"
        }

    ]
    ticketCategory: [
        {
            "categoryId": "category_001"
            "categoryName": "VIP"
            "price": 3000
            "unit": "INR"
            "totalTickets": 500
            "availableTickets": 100
            "status": "AVAILABLE"
        }

        {
            "categoryId": "category_002"
            "categoryName": "General"
            "price": 500
            "unit": "INR"
            "totalTickets": 2500
            "availableTickets": 1500
            "status": "AVAILABLE"
        }
    ]
    
    "seatMap": {
        "applicable": true,
        "type": "RESERVED_SEATING"
        "seatMapEndpoint": "/v1/events/event001/seats"
    }
}
```


```json
GET /v1/events/event001/seats
```


- User must be able to select the number of tickets and the total price should be diplsayed and on click of "Book Ticket" should redirect to Payment Gateway
POST /reserveTicket
POST /confirmTicket

- User should get a notification on Email/SMS on successful or failed attempts at booking ticket
Notifcation Event via SES/SNS