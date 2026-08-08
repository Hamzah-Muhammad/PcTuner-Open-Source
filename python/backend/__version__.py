"""Single source of truth for the app version (§8.8) — read by `/api/version`,
build.spec's Windows file-version resource, and nothing else. Bump this and
every consumer stays in sync automatically.
"""

__version__ = "1.0.0"
