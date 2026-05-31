# AGENTS.md — AI Development Guidelines

## Core Principles

1. **Docs are always up to date** — When you change code, update the relevant docs in the same action. Never let docs drift from implementation.
2. **Research before building** — Every new feature starts with a research phase: understand the landscape, evaluate options, document findings, then implement.
3. **Speed is the #1 priority** — Every decision must consider latency impact. Prefer in-process over out-of-process, binary over text, direct over abstracted.
4. **Verify before claiming done** — Run tests, run the benchmark, verify it builds. No "should work" — prove it works.

## Repository Structure

This is a Dart/Flutter monorepo managed with Melos:

```
flutter_turbo_bridge/
├── packages/
│   ├── turbo_bridge/          # In-app server (Flutter package)
│   ├── turbo_bridge_client/   # Client library (pure Dart)
│   └── turbo_bridge_mcp/      # MCP server for LLM integration
├── apps/
│   ├── target_app/            # Reference Flutter app with bridge
│   └── benchmark/             # Speed benchmark tool
├── docs/
│   ├── ROADMAP.md             # Project phases and deliverables
│   ├── IMPLEMENTATION_PLAN.md # Technical architecture and API contracts
│   └── BENCHMARK_RESULTS.md   # Latest performance measurements
├── ARCHITECTURE.md            # Research findings and high-level design
└── AGENTS.md                  # This file
```

## Feature Development Workflow

Every new feature follows this lifecycle:

### 1. Research Phase
- Study the problem space, existing solutions, and standards
- Evaluate trade-offs (performance, complexity, dependencies)
- Document findings in `ARCHITECTURE.md` or a dedicated research doc
- Identify risks and unknowns before committing to an approach

### 2. Documentation Phase
- Update `docs/IMPLEMENTATION_PLAN.md` with the technical design
- Update `docs/ROADMAP.md` with scope and deliverables
- Define API contracts, data formats, and integration points
- Write the docs **before** the code — docs drive implementation

### 3. Implementation Phase
- Follow the documented API contracts exactly
- Write unit tests alongside implementation
- Keep packages decoupled — no circular dependencies
- Use dependency injection for testability

### 4. Validation Phase
- Run `dart analyze` — zero warnings
- Run `dart test` — all pass
- Run the benchmark if performance-sensitive
- Update any docs that drifted during implementation
- Verify the feature works end-to-end

## Development Workflow

### Before Making Changes

1. Read `docs/IMPLEMENTATION_PLAN.md` to understand the architecture
2. Check `docs/ROADMAP.md` for current phase and priorities
3. Run `melos bootstrap` to ensure dependencies are resolved

### While Making Changes

1. Keep packages decoupled — `turbo_bridge` should not depend on `turbo_bridge_client`
2. Every public API needs a unit test
3. Measure performance: if adding a feature, benchmark it
4. Use dependency injection for testability (no global state)

### After Making Changes

1. **Format every Dart file** — run `melos run format --no-select` from the repo root. CI uses `dart format --line-length 80 --set-exit-if-changed .`, so any unformatted Dart code fails the pipeline. There is no "format on save" hook — this is on you.
2. Run `melos run analyze --no-select` — zero warnings.
3. Run `melos run test:dart --no-select` and `(cd packages/turbo_bridge && flutter test)` — all pass.
4. If you changed a public API, update `docs/IMPLEMENTATION_PLAN.md`.
5. If you changed scope/deliverables, update `docs/ROADMAP.md`.
6. Run the benchmark locally against a macOS debug build if you changed anything in `turbo_bridge` or `turbo_bridge_client`:
   ```bash
   # Terminal 1: Start target app
   cd apps/target_app && flutter run -d macos --debug

   # Terminal 2: Run benchmark (bridge-only is sufficient for most changes)
   cd apps/benchmark && dart run bin/benchmark.dart --bridge-only -p 8888 -n 50
   ```
   All benchmarks must pass (10/10) before considering the change complete.

## Formatting Rules

- **Dart**: `dart format --line-length 80` (matches `melos run format`). 80-column line length is non-negotiable — CI rejects anything else. Run formatter on every file you touch, including tests and `tool/` scripts.
- **TypeScript / CSS / HTML** (DevTools UI under `packages/turbo_bridge/devtools_ui/`): Prettier defaults; let your editor handle it. `npm run typecheck` must pass (strict TS, `noUnusedLocals` on).
- **Markdown**: no fixed line length, but wrap at ~80 cols where reasonable. Don't reformat existing docs you aren't touching.
- **YAML** (pubspec, melos, CI): 2-space indent.
- **No tabs anywhere.**
- Trailing newline on every file.

## Version Bump Workflow

The version string is centralized but lives in multiple files (pubspec, Dart constants, README install snippets, tests, docs). Use the bump script — never edit version strings by hand:

```bash
# From the repo root:
dart run tool/bump_version.dart 0.1.6
```

The script edits, in one shot:

- `packages/turbo_bridge/pubspec.yaml` — `version:`
- `packages/turbo_bridge_client/pubspec.yaml` — `version:`
- `packages/turbo_bridge_mcp/pubspec.yaml` — `version:` and the `turbo_bridge_client: ^…` dep pin
- `packages/turbo_bridge/lib/src/version.dart` — `turboBridgeVersion` constant (the single source of truth read by `AppInfoService` and tests)
- `packages/turbo_bridge_mcp/lib/src/version_info.dart` — `turboBridgeMcpVersion` constant
- `packages/turbo_bridge/README.md` — `"bridgeVersion": "…"` example
- `packages/turbo_bridge_client/README.md` — install snippet
- `docs/IMPLEMENTATION_PLAN.md` — `"bridgeVersion": "…"` example
- `packages/turbo_bridge_client/test/bridge_connection_test.dart` — fixture values
- `packages/turbo_bridge_mcp/test/server_test.dart` — `mcpServerVersion` expectations

**Two manual follow-ups after running it:**

1. **`server_test.dart` "update-recommended" case** — the comparison test deliberately uses a `bridgeVersion` strictly greater than the MCP version. After bumping MCP, eyeball that test and bump its `bridgeVersion` to one more than the new MCP version.
2. **CHANGELOG entry per package** — the script doesn't touch CHANGELOGs. Add a section in each package's `CHANGELOG.md` describing what shipped.

Then:

```bash
melos run format --no-select
melos run analyze --no-select
(cd packages/turbo_bridge && flutter test)
melos run test:dart --no-select
```

## Code Guidelines

### Performance Rules

- **No unnecessary allocations** — reuse buffers, avoid repeated list/map creation
- **No base64 for binary data** — use raw bytes over HTTP
- **No synchronous I/O** on the main isolate
- **Benchmark any new operation** — add it to the benchmark suite
- **Cache computed results** when the input hasn't changed (widget tree, app info)

### Architecture Rules

- **Services are injectable** — use constructor injection, not `static` methods
- **Single responsibility** — each service does one thing
- **No circular dependencies** between packages
- **Public API is minimal** — export only what consumers need
- **Errors are typed** — use sealed classes or specific exception types, not generic `Exception`

### Testing Rules

- **Unit tests** for all services (mock Flutter bindings where needed)
- **Integration tests** using the benchmark tool against a running app
- **Performance tests** — assert latency targets are met (p95)
- **No flaky tests** — if timing-dependent, use generous thresholds or mock time

## Key Files to Keep Updated

| File | Update When |
|------|-------------|
| `docs/ROADMAP.md` | Scope changes, phase completion |
| `docs/IMPLEMENTATION_PLAN.md` | API changes, architecture changes |
| `ARCHITECTURE.md` | Research findings, fundamental design changes |
| `AGENTS.md` | Workflow or convention changes |
| `README.md` (root) | New packages, architecture changes, setup changes |
| `packages/turbo_bridge/README.md` | HTTP API changes, new endpoints, config options |
| `packages/turbo_bridge_client/README.md` | Client API changes, new methods, models |
| `packages/turbo_bridge_mcp/README.md` | New MCP tools/resources/prompts, setup changes |
| `docs/BENCHMARK_RESULTS.md` | New benchmark operations, target changes, setup changes |
| `.github/workflows/ci.yml` | CI/CD pipeline changes, new jobs or steps |

## README Maintenance Rules

Each README targets a specific audience — keep content aligned:

| README | Audience | Focus |
|--------|----------|-------|
| Root `README.md` | Evaluators, contributors | Overview, quick start, architecture diagram |
| `turbo_bridge/README.md` | Flutter developers adding bridge to their app | HTTP API reference, config, security |
| `turbo_bridge_client/README.md` | Tool builders, CI/pipeline developers | Dart API reference, examples, error handling |
| `turbo_bridge_mcp/README.md` | AI/LLM developers, MCP host users | MCP tool/resource/prompt docs, host setup |

When making changes:

1. **New endpoint in `turbo_bridge`** → Update HTTP API section in `turbo_bridge/README.md`
2. **New method in `TurboBridgeClient`** → Update API reference in `turbo_bridge_client/README.md`
3. **New MCP tool/resource/prompt** → Update the relevant section in `turbo_bridge_mcp/README.md`
4. **New package or major architecture change** → Update root `README.md` diagram and packages table
5. **New CLI flag in MCP server** → Update CLI Options section in `turbo_bridge_mcp/README.md`

## Performance Targets (p95)

| Operation | In-Process | Via Client |
|-----------|-----------|------------|
| Screenshot | <20ms | <50ms |
| Widget tree | <15ms | <40ms |
| Tap gesture | <10ms | <30ms |
| App info | <1ms | <10ms |
| Full AI loop | — | <100ms |

## Dependencies Policy

- Minimize external dependencies
- Prefer `dart:` core libraries
- `shelf` for HTTP (lightweight, battle-tested)
- `vm_service` for VM protocol (official Dart package)
- No code generation unless strictly necessary
- Pin major versions in pubspec
