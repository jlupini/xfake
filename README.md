# xfake

Menu bar app that gives XREAL One Pro glasses a high-resolution HiDPI desktop
on macOS. When the glasses connect, xfake creates a virtual display matching
their current aspect ratio (16:9 or 32:9 ultrawide), makes it the main
display, and hardware-mirrors the glasses to it — macOS renders at Retina
quality and downscales to the panel.

## Install

    make install    # builds and copies xfake.app to /Applications

Requires macOS 14+ and Swift Command Line Tools to build. Uses the private
CGVirtualDisplay API (like BetterDisplay/DeskPad) — quit BetterDisplay before
running xfake; two virtual-display managers will fight.

## CLI

    xfake doctor    # read-only diagnostics: displays, private-API availability
    xfake up        # requires glasses to be connected now; starts a session
                     # immediately and keeps watching (hotplug/mode changes);
                     # Ctrl-C tears everything down
    xfake run       # headless autopilot: watches for glasses hotplug/mode
                     # changes and drives the same state machine the menu
                     # bar app uses, with no UI
    xfake reset     # recovers from a leftover mirror topology (e.g. a prior
                     # xfake process that died without tearing down): un-mirrors
                     # every online display and restores the builtin display as
                     # main, in one WindowServer transaction

With no subcommand, `xfake` launches the SwiftUI menu bar app.

Only one xfake instance can run at a time (CLI *or* menu bar app, not both) —
a lock file enforces this, since two instances would fight over the mirror.
`xfake reset` also takes this lock, so it refuses to run against a live
session instead of fighting it.

### Diagnostic tracing

Set `XFAKE_TRACE=1` in the environment to print a millisecond-timestamped
trace of display reconfiguration callbacks, watcher scans/events, and
`SessionController` state transitions to stderr:

    XFAKE_TRACE=1 xfake run

Useful when a session gets stuck: it shows whether CG reconfiguration
callbacks are actually being delivered, what the watcher's periodic poll
sees, and exactly which event drove (or failed to drive) each state
transition.

## How it works

The glasses' panel is a fixed size (1920×1080, 2560×1080 or 3840×1080
depending on which mode you select on the device), and macOS won't offer
HiDPI modes on it. So xfake creates a *virtual* display matching whatever
aspect the glasses currently report, renders the desktop into a 2× HiDPI
framebuffer, and makes the glasses a hardware mirror of it. The display
pipeline downscales that framebuffer onto the panel — which both sharpens
text (it's supersampled rather than rendered 1:1) and lets you run a
logical resolution larger than the panel, trading sharpness for space.

The resolution menu labels that tradeoff directly: how much extra space a
mode buys, and how many physical panel pixels a 13pt glyph ends up
occupying. Below about 9px text starts to suffer; the exact threshold
depends on the glasses' optics, so trust your eyes over the label.

Everything is session-scoped — xfake never writes to macOS's persistent
display configuration, and the virtual display dies with the process. If
anything goes wrong, quit or kill xfake and macOS reverts to the glasses'
native mode.

Built on the private `CGVirtualDisplay` API (the same one BetterDisplay and
DeskPad use), resolved at runtime via `NSClassFromString` so the app
degrades gracefully instead of crashing if a future macOS removes it. That
also means this can't ship on the Mac App Store.

## Development

`make test` requires the full Xcode.app (not just Command Line Tools) — CLT
does not ship `XCTest.framework`, which the test target links against.
