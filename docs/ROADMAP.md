# Roadmap — Flutter Turbo Bridge

## Vision

Enable AI/LLM agents to interact with Flutter apps at near-human speed (<100ms per operation) with full visual and structural feedback, replacing the current 2-5s/op tooling.

---

## Phase 1: MVP — Core Speed Bridge (Current)

**Goal**: Prove the architecture works and deliver a usable AI-Flutter interaction layer.

### Deliverables

1. **`turbo_bridge` package** — In-app companion server
   - HTTP server (shelf) running inside Flutter app
   - `/screenshot` — PNG screenshot in <20ms
   - `/tree` — Widget tree JSON in <15ms
   - `/tap` — Inject tap gesture in <10ms
   - `/info` — App metadata (screen size, platform, etc.)
   - WebSocket endpoint for streaming events and bidirectional commands

2. **`turbo_bridge_client` package** — Dart client library
   - Connect to both: companion server + VM Service
   - Unified API: `screenshot()`, `widgetTree()`, `tap(x, y)`, `evaluate(expr)`
   - Connection health monitoring and auto-reconnect
   - Latency tracking built-in

3. **`target_app`** — Reference Flutter app with bridge integration
4. **`benchmark`** — Speed validation tool measuring all operations

### Success Criteria

- [x] All operations under target latency (p95)
- [x] Screenshot: <20ms (in-process), <50ms (via client) — **13ms achieved**
- [x] Widget tree: <15ms (in-process), <40ms (via client) — **1ms achieved**
- [x] Tap injection: <10ms (in-process), <30ms (via client) — **0ms achieved**
- [x] Full AI feedback loop: <100ms — **16ms achieved**
- [ ] Zero crashes over 1000 consecutive operations
- [x] Unit test coverage >80% — 45 tests passing

5. **`turbo_bridge_mcp` package** — MCP server for LLM integration
   - Model Context Protocol server (stdio transport)
   - Exposes bridge operations as MCP tools
   - Provides app state as MCP resources
   - Pre-built prompts for common AI workflows
   - Compatible with Claude Desktop, VS Code, Cursor, etc.

---

## Phase 2: Enhanced Inspection & AI Integration

**Goal**: Make the bridge smarter for AI consumption.

### Deliverables

1. **Semantic widget tree** — AI-optimized tree format
   - Strip noise, keep actionable info (keys, types, text content, tap targets)
   - Compact JSON format optimized for token count
   - Diff-based updates (only send changes)

2. **Element finder** — Find widgets by text, key, type, semantics
   - `findByText("Login")` → returns tap coordinates
   - `findByKey("submit_button")` → returns element bounds
   - Fuzzy matching for AI imprecision

3. **Gesture library** — Complex gesture support
   - Swipe, long-press, drag, scroll
   - Text input injection
   - Multi-gesture sequences

4. **VM Service integration** — Direct evaluation bridge
   - Hot reload trigger
   - State inspection
   - Error stream forwarding

---

## Phase 3: Web Dashboard & Streaming (Post-MVP)

**Goal**: Real-time web UI showing app state, AI decisions, and debug output.

### Deliverables

1. **Web streaming server**
   - Real-time app screenshot stream (WebSocket → browser)
   - <100ms latency from app to browser display
   - Configurable frame rate (1-30 fps)

2. **Debug dashboard**
   - Live widget tree visualization
   - AI action log (what the AI did and why)
   - Latency metrics real-time chart
   - Error/warning stream
   - Manual override controls (tap, inspect)

3. **Session recording**
   - Record AI interaction sessions
   - Replay with timeline scrubbing
   - Export as test scripts

---

## Phase 4: Production Hardening

**Goal**: Make it reliable for real-world AI dev workflows.

### Deliverables

1. **Security** — Auth tokens, localhost-only by default
2. **Multi-isolate support** — Handle apps with multiple isolates
3. **Platform adaptations** — iOS, Android, Web, Desktop differences
4. **Performance profiling** — Memory, CPU monitoring
5. **MCP server** — Model Context Protocol wrapper for standardized AI tool interface
6. **CI integration** — Automated speed regression tests

---

## Timeline (Estimated)

| Phase | Duration | Status |
|-------|----------|--------|
| Phase 1: MVP | 2-3 weeks | 🔄 In Progress |
| Phase 2: Enhanced | 2-3 weeks | ⏳ Planned |
| Phase 3: Web Dashboard | 2-3 weeks | ⏳ Planned |
| Phase 4: Production | 2-3 weeks | ⏳ Planned |

---

## Technical Constraints

- **Speed is king**: Every design decision prioritizes latency
- **In-process preferred**: Operations running inside the app isolate are 10-100x faster
- **Minimal dependencies**: Keep the bridge lightweight
- **Debug mode only**: Bridge is stripped from release builds
- **No blocking**: All operations must be non-blocking to avoid UI jank
