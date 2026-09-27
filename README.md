# POS Frontend

Flutter mobile app for a point-of-sale system built for Tabaka Farmers agrovet shop.
Talks to the [PointOfSale](https://github.com/KingN3V/PointOfSale) FastAPI backend.

## Features

- Login / registration with JWT auth, forgot-password flow
- New Sale: cart-based checkout with Cash or M-Pesa, walk-in or on-credit
- Products: add, edit, hide/unhide, restock with buying/selling price tracking
- Customers and credit: track balances owed, record partial or full payments
- Sales history: filter by status and timeframe, search, cancel open orders
- Reports: sales summary, top products, low stock, outstanding balances —
  each with CSV/Excel export
- Categories

## Stack

- Flutter (Dart)
- Backend: FastAPI + PostgreSQL, deployed on Render + Neon

## Running locally

```bash
flutter pub get
flutter run
```

Point `baseUrl` in `lib/services/api_service.dart` at your backend instance.