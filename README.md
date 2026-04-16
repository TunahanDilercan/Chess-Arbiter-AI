# Arbiter AI

Satranc skor kagidi fotoagrafindan hamle okuyan ve FIDE kurallarina gore analiz
eden bir proje.

## Stack

- Backend: FastAPI, python-chess, OpenCV, TrOCR, Celery, PostgreSQL
- Mobile: Flutter, Riverpod, Dio
- Web: Next.js (inceleme araci)

## Hizli Baslatma

```bash
docker-compose up --build
```

API docs:

- http://localhost:8000/docs

## Mobil Calistirma

```bash
cd mobile
flutter pub get
flutter run
```

## Test

```bash
cd backend
pip install -r requirements.txt
pytest -q
```
