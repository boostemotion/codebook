# Third-Party Notices

Cipherbook bundles the following local Flutter packages:

## Prism Shell and Prism UI

- `packages/prism_shell/` — GPL-3.0
- `plugins/prism_ui/` — GPL-3.0

The Prism frontend workbench was extracted from FlClash and adapted for Cipherbook.
The migration reference commit is `fbe52d985c47e67c71f6f2feb703338bbaf10f75`.

License texts:

- [`packages/prism_shell/LICENSE`](packages/prism_shell/LICENSE)
- [`plugins/prism_ui/LICENSE`](plugins/prism_ui/LICENSE)

## Adapted code in Prism UI

`plugins/prism_ui/NOTICE` records additional upstream projects and licenses:

- Material Color Utilities — Apache-2.0
- Material New Shapes — MIT
- Super Sliver List — MIT
- navigator_resizable — MIT
- Flutter ink sparkle shader — BSD-3-Clause

See [`plugins/prism_ui/NOTICE`](plugins/prism_ui/NOTICE) for file-level attribution.

## Project licensing status

The Cipherbook repository does not currently declare one root-level license for the whole
application. Publishing binaries or reusing the Prism frontend in another product requires a
license review that accounts for the bundled GPL-3.0 components. This notice is attribution,
not a replacement for a project-wide license decision.
