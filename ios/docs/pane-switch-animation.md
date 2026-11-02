# Pane switch animation

## Findings (static analysis; not profiled in Instruments)

1. **Hard cut.** `PaneDetailView.selectedPaneSession` is keyed `.id(sessionIdentity)`
   (intentional: per-pane drafts/dictation/Live isolation). Changing the pane
   removes and inserts a whole `PaneSessionView` in one frame with no transition,
   because `PaneSwitcher` assigned `selection = pane.id` outside any animation.
2. **Rebuild cost on the main thread.** The new `PaneSessionView` runs its
   `init` (state, draft load) and builds the output/timeline view and compose
   bar in the same frame; `reload()` then runs async and the output scrolls to
   the bottom after first layout, which reads as a snap.
3. **Competing motion.** The switcher's own `proxy.scrollTo` used a default
   `withAnimation` in the same frame as the (unanimated) swap and the
   `navigationTitle` / toolbar title change.

## Candidate approaches

| Approach | Pros | Cons |
| --- | --- | --- |
| A. Animate selection + transition on the keyed session view (chosen) | Tiny; keeps `.id` isolation; Reduce Motion is trivial | Does not reduce rebuild cost, only hides it |
| B. `matchedGeometryEffect` selection indicator in the switcher | Nice switcher feedback | Cards/chips swap layouts; does nothing for the session swap |
| C. Snapshot the outgoing pane / defer heavy loading until after the transition | Addresses hitch directly | Complex; snapshot of a live terminal is stale; risks isolation bugs |

## Implemented: A

- Switcher selection goes through `animatedSelection`, which sets the slide edge
  from switcher order and wraps the change in `.snappy(duration: 0.28)`.
- Incoming session: fade plus 28pt slide from the side the pane sits on.
  Outgoing session: fade only (a removed view keeps its last-rendered
  transition, so a direction-dependent removal would slide the wrong way).
- Reduce Motion: plain cross-fade.
- Switcher `scrollTo` uses the same `.snappy(duration: 0.28)`.
- Non-switcher selection changes (kill, create, peer refresh) are unchanged
  (no animation).
