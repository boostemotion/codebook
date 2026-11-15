# prism_shell

`prism_shell` is the reusable application-shell layer extracted from the
FlClash frontend workbench. It owns only presentation infrastructure:

- responsive desktop sidebar and mobile navigation;
- retained page and navigation motion;
- configurable destinations and page builders;
- app-level theme, locale, text-scale, and reduced-motion plumbing;
- process-local shell settings;
- an overridable current-destination provider.

It contains no product data, networking, persistence, platform service, proxy,
VPN, database, IPC, or filesystem code. A host application supplies its own
pages, localization delegates, accent defaults, and optional desktop window
drag region.

See `../../docs/frontend.md` for Cipherbook's current integration and safety boundaries.
