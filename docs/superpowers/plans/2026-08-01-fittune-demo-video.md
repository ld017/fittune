# FitTune 2.0 Demo Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a verified 1920×1080 H.264 MP4 that demonstrates FitTune 2.0 strength, cardio, multisport, records, and trend workflows using the real iOS interface.

**Architecture:** Build and install the Debug app on a dedicated iPhone simulator, seed deterministic demo-only state without affecting Release behavior, and record separate vertical screen clips for each chapter. A small macOS AVFoundation compositor places those clips on a branded 1080p landscape canvas with title cards and captions, then exports a single compatible MP4.

**Tech Stack:** Swift/SwiftUI, iOS Simulator `simctl`, macOS AVFoundation/CoreGraphics, H.264 MP4, shell orchestration.

## Global Constraints

- Final output is 1920×1080, 30 fps, H.264 MP4.
- Target duration is 4–6 minutes but content completeness takes priority.
- Use only the real FitTune interface; demo state may shorten waiting but cannot invent nonexistent screens.
- Personal fitness data is permitted, but account credentials, device identifiers, notifications, and precise private locations must not appear.
- Default final audio is silent and contains no unlicensed music.
- Release behavior and persisted user data must remain unchanged.

---

### Task 1: Deterministic Simulator Demo State

**Files:**
- Create: `FitTune/Services/DemoVideoDataFactory.swift`
- Modify: `FitTune/App/FitTuneApp.swift`
- Modify: `FitTune.xcodeproj/project.pbxproj`
- Modify: `Package.swift`
- Test: `FitTuneTests/DemoVideoDataFactoryTests.swift`

**Interfaces:**
- Consumes: existing `AppSnapshot`, `AppStore`, strength/cardio/sport record models.
- Produces: `DemoVideoDataFactory.snapshot(now:) -> AppSnapshot` and Debug launch argument `-DemoVideo`.

- [ ] **Step 1: Add a test for a complete, deterministic demo snapshot**

Assert that the factory returns a profile, generated plan, at least three strength records, two cardio records, two sport records, recovery data, body data, and no active draft.

- [ ] **Step 2: Run the focused test and confirm it fails because the factory is absent**

Run: `swift test --filter DemoVideoDataFactoryTests`

- [ ] **Step 3: Implement the factory and Debug-only launch seeding**

When `-DemoVideo` is present in a Debug build, replace only the simulator app's local snapshot with deterministic recent dates and realistic metric provenance. Do not execute this path in Release.

- [ ] **Step 4: Run the focused and full test suites**

Run: `swift test --filter DemoVideoDataFactoryTests && swift test`

- [ ] **Step 5: Commit the demo-state support**

```bash
git add FitTune FitTuneTests Package.swift FitTune.xcodeproj/project.pbxproj
git commit -m "test: add deterministic demo video state"
```

### Task 2: Build, Install, and Capture Chapter Clips

**Files:**
- Create: `tools/demo-video/capture.sh`
- Create: `artifacts/demo-video/raw/`

**Interfaces:**
- Consumes: Debug app with `-DemoVideo`, simulator identifier, real FitTune UI.
- Produces: H.264 `.mov` clips for intro/today, strength, cardio, sports, and records.

- [ ] **Step 1: Build the simulator app and boot a dedicated iPhone 17 Pro simulator**

Use an isolated DerivedData directory and erase only the dedicated simulator created for this recording.

- [ ] **Step 2: Install and launch with `-DemoVideo`**

Verify the opening frame shows the populated Today screen and contains no onboarding or permission dialog.

- [ ] **Step 3: Record the Today and strength chapters**

Capture real navigation, starting a strength workout, set input, RIR, completion, rest recommendation, next-set action, pause, and safe exit/summary.

- [ ] **Step 4: Record the cardio and multisport chapters**

Capture modality selection, live timer/metrics, pause/resume, finish summary, sport catalog, one complete sport session, and data-confidence messaging.

- [ ] **Step 5: Record records/trends and ending clips**

Capture unified filters, representative details, 30-day trends, and app/version ending frame.

- [ ] **Step 6: Validate every raw clip**

Use `mdls`/AVFoundation metadata to confirm nonzero duration, H.264 video, stable frame size, and absence of blank first/last frames.

### Task 3: 1080p Composition and Captions

**Files:**
- Create: `tools/demo-video/compose.swift`
- Create: `tools/demo-video/storyboard.json`
- Create: `artifacts/demo-video/FitTune-2.0-Demo-1080p.mp4`

**Interfaces:**
- Consumes: raw `.mov` clips and storyboard chapter metadata.
- Produces: silent 1920×1080 H.264 MP4 at 30 fps.

- [ ] **Step 1: Define chapter order and concise Chinese captions**

The storyboard contains opening, today, strength, cardio, multisport, records/trends, and closing sections with exact titles and clip paths.

- [ ] **Step 2: Implement the AVFoundation compositor**

Place the portrait screen recording centered on a dark FitTune gradient canvas, preserve aspect ratio, add rounded framing, chapter title, short feature caption, and FitTune 2.0 footer. Export with `AVAssetExportSession` using an H.264-compatible 1080p preset.

- [ ] **Step 3: Export the first complete cut**

Run: `swift tools/demo-video/compose.swift tools/demo-video/storyboard.json artifacts/demo-video/FitTune-2.0-Demo-1080p.mp4`

- [ ] **Step 4: Inspect key frames and revise clipping/caption timing**

Extract frames at every chapter boundary and verify no caption covers an interactive control and no transition contains black gaps.

### Task 4: Final Verification and Delivery

**Files:**
- Create: `artifacts/demo-video/README.md`
- Modify: `docs/superpowers/plans/2026-08-01-fittune-demo-video.md`

**Interfaces:**
- Consumes: final MP4 and raw assets.
- Produces: verified deliverable, reproducible capture notes, and completed checklist.

- [ ] **Step 1: Verify codec, dimensions, frame rate, duration, and playback**

Use AVFoundation metadata plus Quick Look playback. Required values: 1920×1080, H.264, 30 fps, duration greater than 60 seconds.

- [ ] **Step 2: Verify content coverage from extracted frames**

Confirm frames show strength set entry/rest, cardio live metrics, sport selection/session, and record/trend detail.

- [ ] **Step 3: Run project regression checks**

Run: `swift test`, `git diff --check`, and an iOS Simulator Debug build.

- [ ] **Step 4: Document deliverables and commit reproducible tooling**

```bash
git add tools/demo-video artifacts/demo-video/README.md docs/superpowers/plans/2026-08-01-fittune-demo-video.md
git commit -m "feat: produce FitTune 2.0 demo video"
```

The large MP4 and raw recordings remain local deliverables unless the repository's Git policy explicitly permits committing large binaries.
