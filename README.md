# iOS-cw-2-fleets
this is a iOS cw part 2. that is developing fleet management app
 
  COBSCCOMP242P-008

  S.M.A.D.V.Deshan Sammandapperuma

  fleetIQ

 # MVP

 App Name: FleetIQ
Functional Features:
* Authentication (Firebase Auth — email/password login, role-based Manager and Driver accounts)
* Dashboard (Manager home with fleet status hero cards, monthly spend, efficiency metrics, urgent alerts, quick actions, today's activity feed)
* User Profile (Manager profile with name, email, phone, fleet name, Face ID toggle)
* Vehicle Management (Add, edit, delete vehicles with registration, make, model, year, fuel type, mileage, insurance and licence expiry dates)
* Driver Management (Add drivers, assign to vehicles, manage fleet drivers, real-time Firestore sync)
* Fault Reporting (Driver submits fault with description, urgency, up to 3 photos, GPS location captured automatically)
* Fuel Log (Driver logs fill-ups with litres, cost per litre, total LKR, auto km/L efficiency calculation)
* Trip Log (Driver logs start/end mileage, destination, purpose, auto distance calculation)
* Cost Report (Lifetime cost, monthly average, cost per km, category breakdown with share via WhatsApp/email)
* Document Vault (Store insurance and revenue licence photos with OCR expiry date extraction)
Advanced Feature — Mandatory:
* Push Notifications (3 types: service due reminder 14 days before predicted date, document expiry warning 30 days before, document expiry final alert 7 days before.)
* Core Data (Offline persistence for Vehicle, ServiceRecord, FuelLog, TripLog, FaultReport, Driver, Document entities. Acts as cache when Firebase is unavailable)
* Face ID (LocalAuthentication framework — biometric lock on every app launch, toggleable in settings)

Advanced Feature — MapKit:

* MapKit with CoreLocation and Nominatim API. When driver submits a fault report, CoreLocation captures a one-time GPS fix. MapKit renders an MKMapView with a driver location annotation pin. URLSession calls the OpenStreetMap Overpass API to find the 3 nearest vehicle repair garages. Results shown as annotation pins with garage name, distance in km, phone number tap-to-dial, and driving directions button using MKMapItem.openMaps. MKLocalSearch is not used because Apple Maps has no POI coverage for Sri Lanka. Nominatim provides full coverage via URLSession with no third-party SDK.

Advanced Feature — Core ML / Vision:

* Vision Framework (VNRecognizeTextRequest — on-device OCR with no internet required. Two uses: scanning paper garage invoices to auto-fill service date, cost, mileage, garage name and service type into service records; and scanning insurance certificates and revenue licence documents to auto-extract expiry dates into Document Vault. Entirely on-device, no API key, no third-party SDK)

Advanced Feature — Swift Charts:

* Two charts on the Analytics tab using Apple Swift Charts framework. Chart 1: monthly maintenance cost bar chart per vehicle using BarMark. Chart 2: stacked spending breakdown by category (Service, Fuel, Insurance, Tyres) using BarMark with foregroundStyle by value. Month navigation with previous/next controls. Data sourced from CoreData aggregation via AnalyticsViewModel.




