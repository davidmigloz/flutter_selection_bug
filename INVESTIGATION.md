# SelectionArea + go_router Navigation Bug Investigation

## Summary

Text selection breaks on pages reached via `go_router` navigation within a `ShellRoute` that wraps content in `SelectionArea`. A "dead zone" appears where drag-to-select fails, corresponding to the bounding boxes of selectable text from the **previous (now non-current) page**.

## Status Update (March 5, 2026)

- Tracking issue is open in Flutter framework: [flutter/flutter#182573](https://github.com/flutter/flutter/issues/182573)
- Initial package-level fix is open in go_router: [flutter/packages#11062](https://github.com/flutter/packages/pull/11062)
- Current maintainer guidance is to land the root fix in `flutter/flutter` (framework), then decide whether the go_router patch is still needed

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

**This bug is caused by `go_router`'s Navigator keeping non-current pages mounted (hidden but alive), combined with `SelectableRegion` iterating ALL registered selectables regardless of visibility.**

### The Precise Mechanism

When navigating from `/entities` to `/entities/entity-1`, `go_router`'s route matching produces **two** `RouteMatch` objects for the shell's Navigator: one for `/entities` (parent) and one for `:entityId` (child). Both are passed to the shell's `_CustomNavigator` as `match.matches`, which builds **two** pages for the `Navigator`.

The Navigator keeps the parent page (list) **mounted but non-current/hidden** (due to `maintainState: true`). In route stacks, covered pages are often hidden by `Overlay` mechanics (opaque stacking + skip), while still remaining laid out and registered.

The critical issue is how `SelectableRegion` handles selectables:

1. **`SelectableRegion` does NOT use the render tree's hit-testing** -- it maintains its own list of registered selectables and iterates through all of them, checking bounding boxes via `MatrixUtils.transformRect(selectable.getTransformTo(null), rect)` then `Rect.contains(position)`
2. **Hidden non-current pages' Text widgets remain registered** as selectables with the parent `SelectionArea`'s `SelectableRegion`, because hidden routes are still mounted and keep their selectable registrations
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
5. `Navigator` keeps the list page mounted but non-current/hidden (underneath the detail page).
6. `SelectionArea` widget **stays mounted** (same instance, same `SelectableRegion`).
7. List page's `Text` widgets remain fully registered as selectables with valid bounding boxes.
8. Detail page's `Text` widgets also register as selectables.
9. Both sets of selectables overlap in the `SelectableRegion`'s coordinate space.
10. When user clicks to start selection, `SelectableRegion` iterates ALL selectables -- the offstage list page's selectable at that position intercepts the event.

### Why the Dead Zone Shifts with Scroll

The hidden previous page's selectable bounding boxes occupy a fixed region in the `SelectableRegion`'s local coordinate space. The detail page's `SingleChildScrollView` moves its content through this fixed region. As you scroll, different content passes through the ghost zone.

### Why setState Works But go_router Doesn't

With `setState` child swapping, when the list widget is replaced by the detail widget, Flutter's element tree reconciliation **completely disposes** the old list widget's elements. This triggers `SelectionRegistrar.remove()` for each selectable, cleaning up the `SelectableRegion`'s selectable list.

With `go_router`, both pages coexist in the Navigator -- the old page is NOT disposed, it's kept mounted but hidden/non-current. Its selectables remain registered because the page (and its render objects) are still alive.

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

## Initial Upstream Approach (go_router PR #11062)

As an initial upstream attempt, a fix was implemented in go_router:

- PR: [flutter/packages#11062](https://github.com/flutter/packages/pull/11062)
- Scope: disable selection registration for non-current/offstage route content managed by go_router

### What was implemented

1. **Route-level guard in `_CustomNavigator`** (`packages/go_router/lib/src/builder.dart`)
   - Adds `_OffstageSelectionDisabler` around route page content
   - Uses `ModalRoute.isCurrentOf(context)` to reactively detect whether the route is current
   - Disables selection for non-current routes with `SelectionContainer.disabled`

2. **Branch-level guard for `StatefulShellRoute.indexedStack`** (`packages/go_router/lib/src/route.dart`)
   - Adds `_SelectionGuard(disabled: !isActive, child: ...)` for inactive branches
   - Covers inactive branch navigators that are offstage via indexed stack behavior

3. **State-preserving guard structure**
   - Both guards use `GlobalKey` + `KeyedSubtree` to preserve descendant `State` when wrapping is toggled
   - Prevents scroll/text-field state loss when routes move onstage/offstage

### Test coverage added in PR

The PR includes extensive tests in `go_router/test/builder_test.dart`, including:

- Builder and pageBuilder route cases
- Deep-link and back-navigation re-enable behavior
- 3-level nested route stacks
- `StatefulShellRoute` inactive-branch behavior
- State preservation checks (e.g., `TextField` content survives transitions)

### Known limitation in the package-level approach

For `GoRoute.pageBuilder`, automatic wrapping only applies to known go_router page types (`NoTransitionPage`, `CustomTransitionPage`). Custom page subclasses still require manual wrapping.

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

The package-level fix works, but reviewer feedback on [flutter/packages#11062](https://github.com/flutter/packages/pull/11062) asked to move the root fix into framework. A deeper framework investigation changes the preferred technical target.

### Deeper framework findings

1. **`ModalRoute.offstage` is not the main signal for covered routes**
   - In framework internals, `offstage` is primarily toggled for hero-flight measurement frames (temporarily), not as the general "route is covered by another route" state.

2. **Covered routes are usually hidden by `Overlay` mechanics**
   - `Overlay` uses `opaque`, `maintainState`, and `_Theater.skipCount` to keep lower routes mounted but out of paint/hit-test order.
   - This means stale selectables can persist even when `ModalRoute.offstage` is false.

3. **`ModalRoute.isCurrent` is the reliable route-stack signal**
   - For route stacks in a `Navigator`, non-current routes are exactly the ones that should not contribute selectables to an ancestor `SelectionArea`.

### Recommended framework patch target

**File**: `packages/flutter/lib/src/widgets/routes.dart`  
**Widget**: `_ModalScopeState.build()` around the route content subtree

Apply a selection guard at modal-scope level using route currentness:

- Disable selection when the route is not current (`!route.isCurrent`)
- Optionally include `route.offstage` as an additional guard condition
- Preserve subtree state by using a stable wrapper shape (avoid toggling parent type in a way that remounts descendants)

This places the fix where modal route lifecycle and visibility semantics are defined, instead of requiring each routing package to patch around it.

### Why this target is better than alternatives for this bug

- **Fixing `Offstage` alone is insufficient** for `Navigator` route stacks because covered routes are often hidden by `Overlay` skip behavior, not `Offstage`.
- **Fixing `Visibility`** does not cover route stacks managed by `Navigator`.
- **Fixing `SelectableRegion` directly** is broader and potentially more correct long-term, but significantly more invasive and riskier for a first patch.

### Complementary follow-up: framework `Offstage` patch

Even if the route-level fix lands first (recommended for this issue), an `Offstage`-specific framework follow-up is still valuable as a general consistency improvement.

#### Desired behavior contract

When `Offstage(offstage: true)` is applied, descendants should not participate in text selection registration under ancestor `SelectionArea`/`SelectableRegion`.

#### What would need to change technically

1. **Add a selection gate for offstage subtrees**
   - Offstage subtrees should expose a disabled selection registrar (equivalent to `SelectionContainer.disabled` behavior for descendants).

2. **Preserve subtree state while toggling**
   - The implementation must avoid remounting descendants when `offstage` flips.
   - A naive conditional wrapper (adding/removing a parent widget type) risks state loss.
   - The tree shape should remain stable while only the effective registrar exposure changes.

3. **Refactor implications in `Offstage`**
   - `Offstage` is currently a `SingleChildRenderObjectWidget` with no `build()` method.
   - Injecting selection behavior likely requires one of:
     - Introducing an internal raw render-object widget (e.g., `_RawOffstage`) and making `Offstage` compose wrapper behavior, or
     - A more complex element-level approach (higher risk/complexity).

4. **Selection-scope plumbing**
   - The patch needs a robust way to set registrar to `null` for the offstage subtree and restore it onstage without changing descendant identity.
   - This likely touches `SelectionRegistrarScope`/selection scope propagation mechanics.

#### Required test matrix for an `Offstage` patch

- `offstage: true` => `SelectionContainer.maybeOf(context)` is null in subtree.
- `offstage: false` => registrar is present/restored.
- Toggling `offstage` preserves state (e.g., `TextField` text, scroll position).
- Nested `Offstage` combinations behave correctly.
- Hero transition scenarios (temporary offstage frames) do not regress.

#### Why this is still complementary, not sufficient for #182573

For navigator route stacks, covered routes are often hidden by `Overlay` (`opaque` + `maintainState` + `_Theater.skipCount`) rather than `Offstage(offstage: true)` as the primary mechanism.  
Therefore an `Offstage` patch alone cannot guarantee fixing the `ShellRoute` dead-zone class in this report; the route-lifecycle fix in `routes.dart` remains necessary.

### Scope and expected residual gap

This framework patch should solve stacked-route cases like the `ShellRoute` parent/child dead zone repro (the core bug in this report).

Potential residual gap: `StatefulShellRoute` inactive branch navigators (offstaged by branch containers) may still need package-side branch guards, because branch inactivity is not always represented by `ModalRoute.isCurrent` in the nested branch navigator.

### Tracking issue

The framework tracking issue is already open:

- [flutter/flutter#182573](https://github.com/flutter/flutter/issues/182573)

The framework PR should reference both:

- [flutter/flutter#182573](https://github.com/flutter/flutter/issues/182573)
- [flutter/packages#11062](https://github.com/flutter/packages/pull/11062)

## Related Existing Issues

The exact bug in this report is now tracked in framework. Related issues in the same problem space:

### Directly related (SelectionArea + go_router)

| Issue | Status | Summary | Relationship to this bug |
|---|---|---|---|
| [#182573](https://github.com/flutter/flutter/issues/182573) | **Open** (P2, triaged-framework) | Selection dead zones after `ShellRoute` navigation, where offstage/covered route selectables intercept drag selection. | Canonical tracking issue for this investigation and framework fix direction. |
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
