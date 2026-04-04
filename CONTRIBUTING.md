# Contributing to Embedded AI Assistant

## Welcome

Thanks for helping improve Embedded AI Assistant. Contributions that improve reliability, local/offline behavior, reproducibility, documentation quality, and embedded deployment support are especially valuable.

## Code of conduct

Please read and follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) in all project spaces.

## Ways to contribute

- Bug reports
- Feature requests
- Code contributions
- Documentation improvements
- Hardware testing (reporting results on different embedded boards)
- Yocto recipe improvements

## Development setup

1. Fork and clone the repository.
2. Install Node.js `24` (matches CI). See `backend/.nvmrc`.
3. Run one-time setup:
   ```bash
   bash scripts/setup.sh
   ```
4. Run preflight checks:
   ```bash
   bash scripts/check.sh
   ```
5. Start the system:
   ```bash
   ./start.sh
   ```
6. Run tests:
   ```bash
   bash scripts/test.sh
   ```
7. Stop services when done:
   ```bash
   ./stop.sh
   ```

## Project structure

Use the repository structure described in `README.md` as the canonical layout. In short:

- `backend/`: Express API, validation, services, unit tests, static UI
- `llm/`, `stt/`, `tts/`: local AI runtime components and models
- `scripts/`: setup, checks, system tests, and logs helpers
- `docs/`: architecture, hardware, API, and voice pipeline documentation
- `yocto/`: embedded Linux build layer, recipes, and machine-specific scripts

## Making changes

### Branching

- `main`: stable, always passing CI
- `feature/short-description`: new features
- `fix/short-description`: bug fixes
- Never commit directly to `main`

### Code style

Backend JavaScript:

- ESLint config in `backend/eslint.config.cjs`
- Run: `cd backend && npm run lint`
- Run: `cd backend && npm run lint:fix`

Shell scripts:

- ShellCheck compliant
- Run: `shellcheck scripts/*.sh start.sh stop.sh`

C++ (if backend is ported):

- `clang-format` with Google style

Yocto recipes:

- Follow OpenEmbedded recipe style guide
- `SRCREV` must be pinned (no `AUTOREV`)

### Commit messages

Use conventional commits:

- `feat: add streaming voice response`
- `fix: correct WAV header chunk size calculation`
- `docs: update voice pipeline latency table`
- `chore: pin llama-cpp SRCREV to stable commit`
- `ci: add shellcheck to lint job`
- `yocto: fix piper-tts RDEPENDS for espeak-ng-data`

### Pull requests

- One logical change per PR
- All CI checks must pass
- Include test results for any AI behavior changes
- For Yocto changes: describe which target was tested (QEMU / RPi5 / static validation only)
- For hardware changes: describe the physical setup

## Testing

### Unit tests

```bash
cd backend && npm test
```

### Integration tests (requires running system)

```bash
bash scripts/test.sh
```

### Yocto static validation

Read `plan.md` for the Yocto validation checklist.

## Reporting bugs

Use the GitHub issue template.

Always include:

- Output of: `bash scripts/check.sh`
- Output of: `bash scripts/test.sh`
- Relevant log lines from: `bash scripts/logs.sh`
- Target hardware: dev machine / QEMU / RPi5

## Adding a new voice model

1. Add the new Piper model files (`.onnx` and `.onnx.json`) under `tts/models/`.
2. Register the voice in `tts/piper-voices.json`.
3. Update the UI voice selector in `backend/public/app.js`.
4. Update any backend defaults in `backend/.env.example` if needed.
5. Add the model installation/copy logic to the Yocto layer recipe(s) so images contain the new voice.
6. Validate with `bash scripts/test.sh` and document model notes in `docs/voice-pipeline.md`.

## Adding support for a new embedded board

What typically needs to change:

- New `MACHINE` config in `local.conf`
- New BSP layer (if not in `meta-raspberrypi`)
- Hardware-specific tuning flags in recipes
- Testing and documentation updates in `docs/hardware.md`

## License agreement

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
For significant contributions, add yourself to the `CONTRIBUTORS` file.