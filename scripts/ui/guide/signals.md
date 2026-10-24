# Signals (SignalHub, Game and presentation consumers)

- `SignalHub` is the typed, notification-only autoload for cross-system events. It loads before `Game`; it stores no game state and runs no commands.
- `Game` validates and commits state, then emits the existing notification synchronously through `SignalHub`. Consumers read state from `Game` and submit orders through `Game`; emitting an event never substitutes for executing an order.
- Keep the original event payload and ordering. Do not forward the same event through both Game and SignalHub. Use concrete typed signals, not a string-keyed generic dispatch method.
- Instance-local events (selection, close, layout, animation and component requests) remain on their owning objects and are wired by their owner. Godot built-in signals stay on their nodes. Map and WAR ROOM layers stay independent; their UI bridges handle global events.
- Connect once per receiver lifetime. Godot disconnects freed Object receivers automatically; explicitly disconnect when a live receiver stops listening. Test observers watch SignalHub for global events and the actual component for local events.
- Simulation classes under `scripts/engine/` never access this Node autoload. Save data and deterministic state belong to the engine, not the notification hub.
