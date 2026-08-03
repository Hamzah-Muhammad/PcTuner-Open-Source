# Frontend — PcTuner-Open-Source

React + TypeScript SPA (Vite) that renders the desktop app's UI: the tool hub, PC-specs bar, per-tool checklists, and Scan/Apply/Undo flows. Talks to the local FastAPI backend in `../backend` over `/api/*`.

Served by the Python backend in production (`npm run build` output in `dist/` is mounted directly by `python/app.py` — no separate dev server or Node runtime in the packaged app).

## Structure

```
src/
├── App.tsx        # Root component, tool routing
├── api.ts         # Typed fetch wrappers for the FastAPI endpoints
├── layout/        # Shared page chrome
├── views/         # Per-tool screens (hub, FPS optimizer, startup optimizer)
└── theme.css       # Design tokens
```

## Development

```bash
npm install
npm run dev      # standalone dev server against a running backend
npm run build     # production build -> dist/, consumed by python/app.py
```

See the [root README](../../README.md) for how this fits into the full app, and [`docs/PYTHON_REWRITE_DESIGN.md`](../../docs/PYTHON_REWRITE_DESIGN.md) for the full architecture rationale.
