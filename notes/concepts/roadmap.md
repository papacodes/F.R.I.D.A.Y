# Project Roadmap: Multi-Agent Local/Cloud Hybrid

## Goal
Transform Friday from a single-brain assistant into a multi-agent platform capable of leveraging both cloud power and local privacy.

## Action Plan

### 1. Unified Brain Interface
- Define `protocol FridayBrain` with methods: `wake()`, `sleep()`, `stop()`, `restart()`, `isReady`.
- Update `GeminiVoicePipeline` and `LocalVoicePipeline` to conform.

### 2. Auto-Discovery Service
- Implement `LocalModelScanner` to crawl `~/Models/friday/`.
- Register found models as agents in `FridayState`.

### 3. Dynamic Brain Manager
- Create `BrainManager` to handle lifecycle of active agents.
- Implement memory-efficient switching (unload local weights when switching to cloud).

### 4. UI/UX Polishing
- Add a dropdown/selection pill in the expanded view for brain selection.
- Show "Brain Type" (Local/Cloud) icons.

## Packaging Strategy
- Use `Scripts/download_models.sh` to pre-populate common models.
- Instructions for non-technical users to drag-and-drop model folders.
