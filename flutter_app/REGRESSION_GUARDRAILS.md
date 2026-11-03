# Regression Guardrails

This file records failures already seen in this project. Check it before changing parsing, KML, input, timeline, animation, or Windows packaging.

## Large input

- Never assign a multi-megabyte source directly to the rendered `TextField`.
- `ProtocolTextController` keeps the full source for parsing, initially renders 16,000 characters, and appends only one 16,000-character page when the editor reaches the bottom.
- Ctrl+V, Windows clipboard history, the Paste button, and file import must all pass through the same bounded controller.
- Editing the bounded preview must map changes back to the full source; select-all paste replaces the full source and must not retain a hidden tail.
- Line numbers and syntax highlighting operate on the bounded preview only.
- Parsing and KML generation run outside the UI isolate. Progress updates must stay low-frequency.
- Do not create a typewriter animation by repeatedly replacing the full input string.

## Parse lifecycle

- Every parse starts from a clean result/progress state, including the second and later parses in the same window.
- Controls remain locked while one parse is running; duplicate parse requests are ignored.
- Successful parsing collapses the input sidebar and gives the result workspace the full width.
- Errors always release the busy state and open the diagnostic terminal.
- Input remains on the left and output expands to the right.

## Alarm and KML rules

- Any packet containing `告警类型` is classified as an alarm packet, regardless of whether it also contains a location.
- Alarm codes must never be interpreted as longitude, latitude, or Google Earth coordinates.
- An alarm packet with a valid time and coordinate is exported to the KML `Alarm Points` folder.
- Alarm KML points use `http://maps.google.com/mapfiles/kml/shapes/flag.png`.
- Alarm totals, filtering, timeline visibility, details, and KML output must agree.
- KML document names and suggested filenames include parsed model and IMEI when available.
- If flag markers are reintroduced in the Flutter timeline, paint them with Canvas rather than icon fonts; verify opaque pixels, layer order, orientation, and hit boxes.

## Concox command event rules

- Only Concox 在线指令下发包(80) packets are command events; 在线指令回复包(21) remains an ordinary reply packet.
- Extract the readable 指令内容 before its hexadecimal field and retain the complete packet text, serial, and inferred timeline time.
- Command-only Concox input is a valid analysis result. Command events appear in statistics, the scrollable details menu, and timeline markers, but are not exported to KML.
- Alarm flags and command information markers sharing a time bucket must keep separate visible hit targets, including at both chart edges.
- Command event parsing currently remains disabled for JT808.
## ACC and timeline rules

- ACC parsing supports both coded forms and plain `ACC状态:ACC高/低` or `ACC开/关` text.
- ACC is a persistent step state: hold horizontally and use a vertical jump at the packet timestamp; never interpolate state changes with diagonal lines.
- A selected range inherits the last ACC state at or before its start. ACC ON stays on a fixed 24 px lane above the baseline; ACC OFF keeps its low proportional lane.
- Device timestamps are already GMT+8 wall-clock values; normalize to UTC exactly once and never display them with a second eight-hour shift.
- Packets without their own time use sequence matching first and nearest timed packet second; inferred time remains distinguishable. Packets after an earlier anchor display a plus marker.
- Axis lines, ticks, tick labels, chart content, and legends share the same left inset. Moving the chart must move all of them together.
- Timeline drawing is downsampled to the visible width and isolated in `RepaintBoundary`.
- The two range thumbs define actual timestamp boundaries, never packet-index boundaries; range cards derive from that interval only. Inferred packets anchored outside the interval must be excluded even when their sequence number falls inside it.
- Pointer hover reports the current packet only. Alarm total remains a static full-log count.
- The timeline always labels the x-axis and the packet-count y-axis.
- Location, heartbeat, alarm, and ACC layers remain independently filterable; filter controls keep spring feedback.
- Alarm flags occupy a reserved lane above the plot. Hover shows a short summary; click opens the alarm menu and the stored alarm-packet text.
- Rapid pointer movement must update only the cursor/tooltip region, not rebuild or reparse the source.

## UI and motion rules

- Result content is primary; the input sidebar is collapsible and the diagnostic terminal belongs at the bottom.
- Avoid invisible hit targets and transparent visual controls. Test the painted pixels as well as pointer activation.
- Entrance motion uses short transform/opacity transitions and remains interruptible. Repeated keyboard actions do not wait for decorative animation.
- Respect reduced-motion settings.
- Theme switching is triggered from the top-right control, blocks pointer input only for the short transition, and repaints its wave in an isolated boundary.
- Light mode uses vibrant blue #1677FF for location data and primary accents; editor, terminal, timeline grid, cursor, and window controls must remain readable in both themes.
- Button shimmer and hover effects must be clipped to the button boundary.
- Large-input status belongs outside the editor viewport so it cannot cover source text.
- Keep the taskbar/window title ASCII English (`TRACEFORGE`) to prevent compiler-codepage mojibake.
- Keep the in-app version label synchronized with the Flutter package version for every project version update.
- Keep bilingual labels readable at the minimum supported window size; do not rely on a single truncated `labelText`.
- A `Positioned` widget may not sit below a render-object wrapper such as `IgnorePointer`; incorrect Stack ancestry previously produced a grey ErrorWidget.
- The collapsed terminal reserves 38px, including its top border, to prevent a 1px RenderFlex overflow.

## Packaging and validation

- Source size is not the same as Flutter build-cache size. `build`, `.dart_tool`, and `windows/flutter/ephemeral` caused the previous 300MB workspace.
- Keep runtime files together under `dist/GPSTrackAnalyzer`; the EXE is not standalone.
- Exclude `.lib` and `.exp` from the runtime copy, then run `flutter clean` after validation.
- Before delivery run static analysis, core parser tests, large-input tests, UI layout tests, a Windows Release build, and one real large-file benchmark.
- Generated KML is not source truth. Regenerate it after source changes before judging behavior.
- Secondary KML actions reveal leftward from the stable primary action; keep the primary button fixed and clip the reveal.
- MTK ephemeris rollback filtering uses the later of the current time and newest log timestamp, removes locations at least ten calendar years older, and clears their old timeline anchors.
- Incremental preview loading preserves the full source, selection, line-number synchronization, and never drains multiple pages from one bottom-scroll event.
