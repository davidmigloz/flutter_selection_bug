# SelectionArea + go_router Navigation Bug Investigation

## Summary

Text selection breaks on pages reached via `go_router` navigation within a `ShellRoute` that wraps content in `SelectionArea`. A "dead zone" appears where drag-to-select fails, corresponding to the bounding boxes of selectable text from the **previous** page.

## Reproduction Steps

1. Open the entities list screen (`/entities`)
2. Verify text is selectable in the table (emails, names, phones)
3. Click "View" on any entity to navigate to `/entities/:entityId`
4. Try to select "First Name: John" by clicking and dragging -- **fails**
5. Scroll down slightly -- the dead zone shifts, making different rows unselectable
6. Hard-reload `/entities/entity-1` directly (without navigating from list) -- **everything is selectable**

## Key Observations

| Observation | Implication |
|---|---|
| Bug only appears after navigating list -> detail via go_router | Navigation transition is the trigger, not the page content |
| Direct reload of `/entities/entity-1` works perfectly | The detail screen widgets are correct |
| Dead zone height matches the list page's table content height | Stale geometry from previous page's selectables persists |
| Dead zone shifts when scrolling | Tied to viewport coordinates, not specific widgets |
| Starting selection below the dead zone and dragging INTO it selects text | Text IS registered as selectable -- initiating drag in the dead zone is what fails |
| Selection cursor (I-beam) appears in the dead zone | `SelectionArea` registers the text, but the drag gesture is intercepted |

## Root Cause (Confirmed)

**This bug is caused by `go_router`'s Navigator keeping offstage pages fully mounted, combined with `SelectableRegion` iterating ALL registered selectables regardless of visibility.**

### The Precise Mechanism

When navigating from `/entities` to `/entities/entity-1`, `go_router`'s route matching produces **two** `RouteMatch` objects for the shell's Navigator: one for `/entities` (parent) and one for `:entityId` (child). Both are passed to the shell's `_CustomNavigator` as `match.matches`, which builds **two** pages for the `Navigator`.

The Navigator keeps the parent page (list) **mounted but offstage** (due to `maintainState: true`). Offstage pages are fully laid out with valid bounding boxes -- they're just not painted.

The critical issue is how `SelectableRegion` handles selectables:

1. **`SelectableRegion` does NOT use the render tree's hit-testing** -- it maintains its own list of registered selectables and iterates through all of them, checking bounding boxes via `MatrixUtils.transformRect(selectable.getTransformTo(null), rect)` then `Rect.contains(position)`
2. **Offstage pages' Text widgets remain registered** as selectables with the parent `SelectionArea`'s `SelectableRegion`, because `Offstage` only prevents painting, not layout or selectable registration
3. **Both pages' selectables overlap** in the `SelectableRegion`'s coordinate space, and when the user clicks to start selection, the offstage list page's selectable at that position wins the iteration, silently consuming the event

### Confirmed with Debug Output

Added debug logging to `_CustomNavigatorState.build()` which confirmed:
- **Initial load** (`/entities`): Shell Navigator builds with **1 page** `[/entities]`
- **After navigation** (`/entities/entity-1`): Shell Navigator builds with **2 pages** `[/entities, /entities/entity-1]`

### Sequence of Events

1. On `/entities`, `SelectionArea` registers all `Text` widgets (table cells) as selectables via `SelectionRegistrar.add()`.
2. User clicks "View" -- `go_router` navigates to `/entities/entity-1`.
3. Route matching produces `[RouteMatch(/entities), RouteMatch(:entityId)]` for the shell's navigator.
4. Shell's `_CustomNavigator` builds **2 pages** and passes them to `Navigator`.
5. `Navigator` keeps the list page mounted but offstage (underneath the detail page).
6. `SelectionArea` widget **stays mounted** (same instance, same `SelectableRegion`).
7. List page's `Text` widgets remain fully registered as selectables with valid bounding boxes.
8. Detail page's `Text` widgets also register as selectables.
9. Both sets of selectables overlap in the `SelectableRegion`'s coordinate space.
10. When user clicks to start selection, `SelectableRegion` iterates ALL selectables -- the offstage list page's selectable at that position intercepts the event.

### Why the Dead Zone Shifts with Scroll

The offstage list page's selectable bounding boxes occupy a fixed region in the `SelectableRegion`'s local coordinate space. The detail page's `SingleChildScrollView` moves its content through this fixed region. As you scroll, different content passes through the ghost zone.

### Why setState Works But go_router Doesn't

With `setState` child swapping, when the list widget is replaced by the detail widget, Flutter's element tree reconciliation **completely disposes** the old list widget's elements. This triggers `SelectionRegistrar.remove()` for each selectable, cleaning up the `SelectableRegion`'s selectable list.

With `go_router`, both pages coexist in the Navigator -- the old page is NOT disposed, it's kept mounted but offstage. Its selectables remain registered because the page (and its render objects) are still alive.

## What Was Ruled Out

| Suspect | Status | Evidence |
|---|---|---|
| General Flutter `SelectionArea` bug | **Ruled out** | Pure `setState` child swap with the same `SelectionArea` wrapping works perfectly -- stale registrations are properly cleaned up by Flutter's normal widget reconciliation |
| `SingleChildScrollView` stealing drag gestures from `SelectionArea` | **Ruled out** | Minimal repro with just `SelectionArea` + `SingleChildScrollView` works fine |
| `LayoutBuilder` in `BrxsPageScaffold` | **Ruled out** | Removing `LayoutBuilder` did not fix the bug |
| `DefaultTabController` / `TabBar` consuming gestures | **Ruled out** | No `TabBarView` present; removing tabs did not fix the bug |
| `BrxsSurface` / `ClipRRect` interfering with hit testing | **Ruled out** | Pure decorative widgets with no gesture handling |
| Nested `SelectionArea` widgets | **Ruled out** | Only one `SelectionArea` exists in the widget tree |
| `GestureDetector` / `InkWell` in detail screen content | **Ruled out** | No gesture handlers in `_InfoRow`, `_OverviewTab`, or section widgets |
| Header buttons (`ElevatedButton`, `IconButton`) stealing gestures | **Ruled out** | They're in the fixed header, not overlapping scroll content |
| Flutter version or web renderer issue | **Partially ruled out** | Reproduces with DDC and dart2wasm but NOT dart2js (see [Build Mode Behavior](#build-mode-behavior)) |

## Build Mode Behavior

The bug does **not** reproduce in all build configurations:

| Command | Compiler | Bug reproduces? |
|---|---|---|
| `flutter run -d chrome` | DDC (debug) | **Yes** |
| `flutter run -d chrome --wasm` | dart2wasm (debug) | **Yes** |
| `flutter run -d chrome --release --wasm` | dart2wasm (release) | **Yes** |
| `flutter run -d chrome --release` | dart2js (release) | No |

### Analysis

The bug reproduces with **DDC** and **dart2wasm** across all build modes (debug and release), but does **not** reproduce with **dart2js**.

This rules out debug-only assertions (`assert`) as the cause -- dart2wasm release strips all asserts, yet the bug persists. The differentiating factor is the **compiler**, not the build mode.

DDC and dart2wasm both preserve Dart semantics faithfully, while dart2js applies aggressive optimizations that likely mask the bug. Possible dart2js-specific factors:

1. **Number representation**: dart2js uses JavaScript doubles for all numbers. Floating-point differences in `MatrixUtils.transformRect` → `Rect.contains(position)` could cause offstage bounding box checks to narrowly miss, effectively making the dead zone "not match" the click position.

2. **Sort stability**: `List.sort` stability guarantees differ across compilers. The `_flushAdditions` sort in `MultiSelectableSelectionContainerDelegate` compares overlapping `Rect` positions from offstage and current page selectables. Different sort orderings determine which selectable "wins" during iteration.

3. **Object identity / equality**: dart2js may optimize `Rect` and `Offset` comparisons differently, affecting boundary conditions in `contains()`.

### Implication

As Flutter migrates toward **dart2wasm as the default web compiler**, this bug will affect release builds. The dart2js release "working" is the exception, not the norm -- the underlying issue (offstage selectables remaining registered with `SelectableRegion`) exists in all compilers, but dart2js happens to mask it.

## Affected Code (brxs_pro_app)

The `SelectionArea` is defined in:
- **File**: `app/brxs_pro_app/lib/shared/widgets/app_shell.dart`
- **Line**: 192
- **Code**: `body: SelectionArea(child: widget.child)`

This wraps ALL route content within the shell. Every page-to-page navigation via `go_router` within this `ShellRoute` is potentially affected.

## Scope of Impact

This bug likely affects **every screen** in `brxs_pro_app` reached via in-app navigation -- not just the entity detail screen. Any page that follows a page with selectable text will have a dead zone matching the previous page's selectable content layout.

## Reproduction Apps

### go_router version (BUG REPRODUCES)

The original reproduction app used `go_router` with a `ShellRoute`. Navigate from list to detail to trigger the bug:
- `go_router` with a `ShellRoute`
- `AppShell` wrapping child in `SelectionArea`
- List screen (`/entities`) with a `Table` containing selectable text
- Detail screen (`/entities/:entityId`) with sections in a scrollable `PageScaffold`
- Run with: `flutter run -d chrome`
- Steps: Open `/entities`, click "View" on any entity, try to select text on the detail page

### Pure setState version (BUG DOES NOT REPRODUCE)

The current `lib/main.dart` uses a pure `StatefulWidget` with `setState` to swap between the same list and detail screens -- no `go_router` involved. The same `SelectionArea` wraps the swappable child, matching the `ShellRoute` pattern exactly. **Text selection works perfectly after navigation**, confirming the bug is specific to `go_router`'s internal child management, not Flutter's `SelectionArea` itself.

## Implemented Fix (in go_router fork)

### `_OffstageSelectionDisabler` widget

**File**: `packages/go_router/lib/src/builder.dart`

The fix adds an `_OffstageSelectionDisabler` widget that wraps each page's content inside go_router's `_CustomNavigator`. This widget:

1. Uses `ModalRoute.of(context)` to reactively detect when its route becomes offstage
2. When the route is NOT the current (topmost) route, wraps the child in `SelectionContainer.disabled`
3. `SelectionContainer.disabled` provides a null `SelectionRegistrar` to descendants
4. Text widgets detect the changed `SelectionRegistrarScope` via `didChangeDependencies`
5. Text widgets unregister from the parent `SelectableRegion`, preventing the dead zone

```dart
class _OffstageSelectionDisabler extends StatelessWidget {
  const _OffstageSelectionDisabler({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      return child;
    }
    return SelectionContainer.disabled(child: child);
  }
}
```

### Where it's applied

1. **`_buildPlatformAdapterPage`** -- wraps the child widget, covering all `builder`-based GoRoutes
2. **`_addSelectionGuardToPage`** -- wraps user-provided pages from `pageBuilder` for known page types (`NoTransitionPage`, `CustomTransitionPage`)

### How it's reactive

- `ModalRoute.of(context)` depends on `_ModalScopeStatus` (an `InheritedWidget`)
- When `isCurrent` changes (page goes offstage or comes back), `_ModalScopeStatus` notifies dependents
- `_OffstageSelectionDisabler` rebuilds, inserting or removing `SelectionContainer.disabled`
- Text widgets' `didChangeDependencies` fires, updating their registrar subscription

### Test coverage

Three new tests in `test/builder_test.dart`:
1. **builder case**: Offstage page's `SelectionContainer.maybeOf(context)` returns null
2. **pageBuilder case**: Same verification with `NoTransitionPage`
3. **back navigation**: Selection is re-enabled when navigating back (registrar becomes non-null)

### Limitations

- Only handles `NoTransitionPage` and `CustomTransitionPage` for the `pageBuilder` case
- Custom `Page` subclasses (e.g., `MaterialPage`, `CupertinoPage` used directly in `pageBuilder`) are not wrapped
- Those cases are rare since `builder`-based routes (which are always covered) are the common pattern

## User-Side Workarounds (if not using the fix)

### Workaround 1: Key the SelectionArea on route location

```dart
final location = GoRouterState.of(context).matchedLocation;
body: SelectionArea(
  key: ValueKey(location),
  child: widget.child,
),
```

**Pros**: Minimal change, clears all stale state.
**Cons**: Destroys and recreates `SelectionArea` on every navigation, resetting active selection.

### Workaround 2: Move SelectionArea into each page

Remove `SelectionArea` from the shell and add it inside each screen's build method.

**Pros**: Each page owns its selection state.
**Cons**: Requires changes to every screen.

## Proper Framework-Level Fix (recommended for upstream)

The go_router fix (`_OffstageSelectionDisabler` + `_IndexedStackedRouteBranchContainer` wrapping) is a pragmatic solution, but the root problem belongs in Flutter's `Offstage` widget itself. Any widget tree with `Offstage` + an ancestor `SelectionArea` can hit this dead zone issue -- it is not unique to go_router.

### Why `Offstage` should handle this

`Offstage` already prevents **painting** and **hit testing** for offstage children. Preventing **selection registration** is the same category of concern: offstage content should not participate in interactive behaviors. The `Visibility` widget (the higher-level compose of `Offstage`) already disables multiple concerns for non-visible children:

| Concern | Disabled by | When |
|---|---|---|
| Painting | `Offstage` | `offstage: true` |
| Hit testing | `Offstage` (via `RenderOffstage`) | `offstage: true` |
| Animations/tickers | `TickerMode` | `enabled: false` |
| Focus | `ExcludeFocus` | `excluding: true` |
| Semantics | `_Visibility` | `maintainSemantics: false` |
| Pointer events | `IgnorePointer` | `ignoring: true` |
| **Selection** | **Nothing** | **-- gap --** |

Selection is the missing entry. Offstage content remaining registered with `SelectableRegion` is architecturally inconsistent with how every other interactive behavior is handled.

### Implementation options

**Option A: Fix in `Offstage` directly** (highest impact, most invasive)

`Offstage` is a `SingleChildRenderObjectWidget` creating `RenderOffstage`. It has no `build()` method, so adding `SelectionContainer.disabled` would require converting it to a `StatelessWidget` that composes `_RawOffstage` (the render object) with `SelectionContainer.disabled` when offstage. This changes the widget type, which is a breaking change for code that depends on `Offstage` being a `RenderObjectWidget`.

**Option B: Fix in `Visibility`** (natural fit, lower risk)

`Visibility.build()` already composes `Offstage` + `TickerMode` + `ExcludeFocus` + `IgnorePointer`. Adding `SelectionContainer.disabled` in the `maintainState` branch would follow the exact same pattern:

```dart
// In Visibility.build(), the maintainState branch:
if (maintainState) {
  if (!maintainAnimation) {
    result = TickerMode(enabled: visible, child: result);
  }
  result = Offstage(offstage: !visible, child: result);
  // ADD: disable selection for offstage content
  if (!visible) {
    result = SelectionContainer.disabled(child: result);
  }
}
```

However, this only helps users of `Visibility`, not direct `Offstage` users (which includes go_router and most routing packages).

**Option C: Fix in `SelectableRegion`** (most correct, most complex)

`SelectableRegion` could check visibility/offstage status before dispatching selection events to registered selectables. This would fix the problem at the source regardless of which widget creates the offstage subtree.

### No existing framework issue

As of February 2026, there is **no open issue** in `flutter/flutter` tracking this specific gap. The closest issues are:
- [#117527](https://github.com/flutter/flutter/issues/117527) -- assertion error with `SelectionArea` + nested go_router routes (layout timing, not offstage selection)
- [#151536](https://github.com/flutter/flutter/issues/151536) -- similar assertion error with subroutes (render box not laid out, not offstage selection)

A new issue should be filed proposing that `Offstage` (or `Visibility`) disables selection for offstage children, similar to how `TickerMode` disables animations and `ExcludeFocus` disables focus.

## Related Existing Issues

No existing issue matches this exact bug (silent dead zone from stale selectable geometry after `ShellRoute` navigation). However, the following open issues are in the same problem space -- `SelectionArea` + `go_router` navigation:

### Directly related (SelectionArea + go_router)

| Issue | Status | Summary | Relationship to this bug |
|---|---|---|---|
| [#117527](https://github.com/flutter/flutter/issues/117527) | **Open** (P2) | `SelectionArea` with nested `go_router` routes throws assertion error (`!debugNeedsLayout`) when navigating directly to a nested route. `RenderParagraph.getBoxesForSelection` accesses layout info before paragraph completes layout. | Same root area: `SelectableRegion` lifecycle is not properly synchronized with `go_router`'s page transitions. Our bug is the *silent* variant -- instead of crashing, stale geometry persists and blocks hit-testing. |
| [#151536](https://github.com/flutter/flutter/issues/151536) | **Open** (P2, 14 👍) | Assertion error (`RenderBox was not laid out: RenderFractionalTranslation`) when navigating to subroutes containing `SelectionArea`. The `MultiSelectableSelectionContainerDelegate` tries to sort selectables using render boxes that haven't been laid out yet. | Same root cause family: `SelectableRegion` attempts to operate on stale/invalid render objects after `go_router` swaps pages. Both bugs point to `SelectableRegion` not properly handling the widget lifecycle during `go_router` navigation. |

### Tangentially related (SelectionArea general issues)

| Issue | Status | Summary | Notes |
|---|---|---|---|
| [#120892](https://github.com/flutter/flutter/issues/120892) | **Closed** (fixed) | `SelectionArea` clears selection prematurely during scroll gestures. Fixed by removing problematic `onLongPressCancel` callback in PR #128765. | Different bug, but shows `SelectableRegion` gesture handling has had lifecycle issues before. |
| [#126817](https://github.com/flutter/flutter/issues/126817) | **Closed** (dup of #111021) | `SelectionArea` doesn't match expected behavior with `WidgetSpan`. Some text passages become unselectable. | Different cause (text range comparison bug), but similar symptom of "dead zones" in selection. |
| [#169149](https://github.com/flutter/flutter/issues/169149) | **Open** | Web: `SelectionArea` text selection and drag gestures break after using the context menu to copy. Cursor changes to "forbidden" and drag events stop reaching Flutter. | Different trigger (context menu), but similar outcome: `SelectableRegion` enters a broken state where drag gestures silently fail. |

### Key differentiator of this bug

The existing issues (#117527, #151536) **crash with assertion errors**, which means they are caught during development and have clear stack traces pointing to the problem. Our bug is more insidious:

- **No crash, no assertion error, no console warnings** -- the app appears to work normally
- The I-beam cursor still appears, suggesting text is selectable
- Only drag-to-select initiation silently fails in specific regions
- The dead zone is position-dependent and shifts with scroll, making it hard to diagnose
- It affects every page navigated to via `go_router` `ShellRoute`, but may go unnoticed if users don't try to select text in the specific dead zone area

### Suggested labels for new issue

```
f: selection, f: routes, package: go_router, found in release: 3.x, has reproducible steps, P2
```
