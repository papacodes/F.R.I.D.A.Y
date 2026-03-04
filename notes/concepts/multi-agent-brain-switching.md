# Concept: Multi-Agent Brain Switching

## Overview
Friday should be capable of switching between different "Brains" (reasoning engines) depending on user preference, connectivity, and task complexity. This allows for a flexible hybrid approach where high-latency complex tasks can use Cloud Gemini, while quick, private, or offline tasks use Local Qwen.

## Core Capabilities
1.  **Cloud Integration**: Support for Gemini 2.0 Flash and Gemini 2.5 (via API).
2.  **Local Discovery**: Automatically scan `~/Models/friday/` for MLX-compatible models.
3.  **Hot-Swapping**: Ability to switch the active pipeline without restarting the application.
4.  **UI Feedback**: Display the active brain and its "health" (latency, connection status) in the Notch.

## Active Model Discovery Logic
Friday will scan the directory structure at `~/Models/friday/`. Each subdirectory representing a valid MLX model (containing `config.json` and `*.safetensors`) will be added to the internal list of available Local Agents.

## Action Plan

### Phase 1: State & UI Refactor
- [ ] **State Expansion**: Update `FridayState` to hold an `activeBrainID` and a list of `availableBrains`.
- [ ] **UI Switcher**: Add a "Brain Selector" menu in the Expanded Notch (Home Tab) to allow users to toggle between Gemini and Local models.
- [ ] **Dynamic Naming**: Ensure the Notch label ("Gemini 2.0 Flash", "Qwen 3.5 2B", etc.) updates instantly.

### Phase 2: Pipeline Orchestration
- [ ] **Brain Protocol**: Create a unified `FridayBrain` protocol that both `GeminiVoicePipeline` and `LocalVoicePipeline` conform to.
- [ ] **Brain Manager**: Implement a manager class that can tear down one pipeline and spin up another seamlessly.
- [ ] **Resource Management**: Ensure local weights are purged from RAM/VRAM when switching to Cloud mode to save energy.

### Phase 3: Model Auto-Discovery
- [ ] **File Scanner**: Add logic to `LocalBrainProcessor` to crawl `~/Models/friday/` on launch.
- [ ] **Model Metadata**: Parse `config.json` in local folders to display friendly names (e.g., "Qwen 2.5 Coder 7B") instead of folder names.

### Phase 4: Hybrid Intelligence (Future)
- [ ] **Task Routing**: Automatically route "Code" tasks to local Qwen-Coder and "General Knowledge" tasks to Gemini Cloud.
- [ ] **Fallback Logic**: Automatically switch to a Local Brain if the internet connection is lost or Gemini API returns a rate-limit error.

## Success Metrics
- Switch between Cloud and Local brain in under 2 seconds.
- Accurate listing of all models placed in the local models folder.
- Zero-config setup for new local models (drop folder -> use in Friday).
