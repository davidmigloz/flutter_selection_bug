# SelectionArea + go_router Dead Zone Bug

Minimal reproduction for a bug where `SelectionArea` text selection breaks after
navigating between routes in a `go_router` `ShellRoute`.

## Live Demo

https://davidmigloz.github.io/flutter_selection_bug/

## The Bug

When a `SelectionArea` wraps the child of a `ShellRoute`, navigating from a
parent route to a child route creates invisible "dead zones" where drag-to-select
silently fails. The dead zones correspond to the bounding boxes of selectable
text from the previous (now offstage) page.

- No crash, no assertion error, no console warnings
- The I-beam cursor still appears in the dead zone
- Only drag-to-select initiation fails; dragging INTO the zone from outside works
- The dead zone shifts when scrolling

## Reproduction Steps

```bash
flutter run -d chrome            # debug (DDC)  — reproduces
flutter run -d chrome --wasm     # debug (WASM) — reproduces
```

1. Open the entities list screen (`/entities`)
2. Verify text is selectable in the table (emails, names, phones)
3. Click "View" on any entity to navigate to `/entities/:entityId`
4. Try to select "First Name: John" by clicking and dragging -- **fails**
5. Scroll down slightly -- the dead zone shifts, making different rows unselectable
6. Hard-reload `/entities/entity-1` directly (without navigating from list) -- **works**

## Build Mode Behavior

| Command | Compiler | Bug reproduces? |
|---|---|---|
| `flutter run -d chrome` | DDC (debug) | **Yes** |
| `flutter run -d chrome --wasm` | dart2wasm (debug) | **Yes** |
| `flutter run -d chrome --release --wasm` | dart2wasm (release) | **Yes** |
| `flutter run -d chrome --release` | dart2js (release) | No |

## Root Cause

When navigating to `/entities/entity-1`, go_router's route matching produces two
`RouteMatch` objects for the shell's Navigator: `/entities` (parent) and
`:entityId` (child). The Navigator keeps the parent page mounted but offstage.

`SelectableRegion` (behind `SelectionArea`) does not use the render tree's
hit-testing -- it iterates its own list of registered selectables. The offstage
page's Text widgets remain registered with valid bounding boxes that overlap the
current page's content, intercepting selection events.

## Branches

- **`main`**: Reproduces the bug with published `go_router: ^17.1.0`
- **`fix/offstage-selection-disabler`**: Fix using a local go_router fork that
  wraps offstage page content in `SelectionContainer.disabled`

See [INVESTIGATION.md](INVESTIGATION.md) for the full analysis.
