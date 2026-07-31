"""Tick-stamped high-level signal observations with event provenance."""

from __future__ import annotations

from dataclasses import dataclass

from kiwi.domain.ids import EntityId, EventId
from kiwi.dsl.runtime_values import IntegerValue, ListValue, RecordValue, StringValue
from kiwi.sim.commands import CommandSource, SignalName
from kiwi.sim.limits import MAX_AUTHORITY_TICK

SIGNAL_RECORD_TYPE = "Signal"


@dataclass(frozen=True, slots=True)
class SignalObservation:
    """One player or scenario signal visible at its exact issued tick."""

    signal: SignalName
    tick: int
    command_sequence: int
    source: CommandSource
    target_entity_id: EntityId | None
    provenance_event_id: EventId

    def __post_init__(self) -> None:
        if not isinstance(self.signal, SignalName):
            raise ValueError("signal observation requires a signal name")
        if not isinstance(self.tick, int) or isinstance(self.tick, bool):
            raise ValueError("signal observation tick must be an integer")
        if not 0 <= self.tick <= MAX_AUTHORITY_TICK:
            raise ValueError("signal observation tick must fit non-negative signed 64-bit range")
        if not isinstance(self.command_sequence, int) or isinstance(self.command_sequence, bool):
            raise ValueError("signal observation sequence must be an integer")
        if not 0 <= self.command_sequence <= MAX_AUTHORITY_TICK:
            raise ValueError(
                "signal observation sequence must fit non-negative signed 64-bit range"
            )
        if not isinstance(self.source, CommandSource):
            raise ValueError("signal observation requires a command source")
        if self.target_entity_id is not None and not isinstance(self.target_entity_id, EntityId):
            raise ValueError("signal observation target must be an entity ID or absent")
        if not isinstance(self.provenance_event_id, EventId):
            raise ValueError("signal observation requires an event ID")


@dataclass(frozen=True, slots=True)
class SignalStore:
    """An immutable `(tick, command sequence)`-ordered signal collection."""

    signals: tuple[SignalObservation, ...] = ()

    def __post_init__(self) -> None:
        if not isinstance(self.signals, tuple):
            raise ValueError("signal store entries must be an immutable tuple")
        previous_key = (-1, -1)
        event_ids: tuple[EventId, ...] = ()
        for signal in self.signals:
            if not isinstance(signal, SignalObservation):
                raise ValueError("signal store entries must contain signal observations")
            key = signal_order_key(signal)
            if key <= previous_key:
                raise ValueError("signal store entries must use canonical tick and sequence order")
            if signal.provenance_event_id in event_ids:
                raise ValueError("signal store entries must have unique event IDs")
            previous_key = key
            event_ids += (signal.provenance_event_id,)


def signal_order_key(signal: SignalObservation) -> tuple[int, int]:
    """Return the canonical key shared by storage and owner-local projection."""
    if not isinstance(signal, SignalObservation):
        raise ValueError("signal ordering requires a signal observation")
    return (signal.tick, signal.command_sequence)


def add_signal(store: SignalStore, signal: SignalObservation) -> SignalStore:
    """Append one signal without relying on command input order."""
    if not isinstance(store, SignalStore):
        raise ValueError("signal storage requires a signal store")
    if not isinstance(signal, SignalObservation):
        raise ValueError("signal storage requires a signal observation")
    return SignalStore(tuple(sorted((*store.signals, signal), key=signal_order_key)))


def discard_signals_before(store: SignalStore, current_tick: int) -> SignalStore:
    """Remove signals that cannot be observed at the current or later tick."""
    if not isinstance(store, SignalStore):
        raise ValueError("signal expiry requires a signal store")
    if not isinstance(current_tick, int) or isinstance(current_tick, bool):
        raise ValueError("signal expiry tick must be an integer")
    if not 0 <= current_tick <= MAX_AUTHORITY_TICK:
        raise ValueError("signal expiry tick must fit non-negative signed 64-bit range")
    retained = tuple(signal for signal in store.signals if signal.tick >= current_tick)
    if retained == store.signals:
        return store
    return SignalStore(retained)


def signals_for(
    store: SignalStore, owner_entity_id: EntityId, current_tick: int
) -> tuple[SignalObservation, ...]:
    """Project squad and directly targeted signals for one owner at one tick."""
    if not isinstance(store, SignalStore):
        raise ValueError("signal projection requires a signal store")
    if not isinstance(owner_entity_id, EntityId):
        raise ValueError("signal projection requires an owner entity ID")
    if not isinstance(current_tick, int) or isinstance(current_tick, bool):
        raise ValueError("signal projection tick must be an integer")
    if not 0 <= current_tick <= MAX_AUTHORITY_TICK:
        raise ValueError("signal projection tick must fit non-negative signed 64-bit range")
    return tuple(
        signal
        for signal in store.signals
        if signal.tick == current_tick
        and (signal.target_entity_id is None or signal.target_entity_id == owner_entity_id)
    )


def signal_runtime_value(signal: SignalObservation) -> RecordValue:
    """Convert one signal to a closed policy-facing DSL record."""
    if not isinstance(signal, SignalObservation):
        raise TypeError("signal runtime value requires a SignalObservation")
    return RecordValue(
        SIGNAL_RECORD_TYPE,
        ("name", "tick"),
        (StringValue(signal.signal.value), IntegerValue(signal.tick)),
    )


def signals_runtime_value(signals: tuple[SignalObservation, ...]) -> ListValue:
    """Convert an owner-local canonical signal tuple to a DSL list value."""
    if not isinstance(signals, tuple):
        raise TypeError("signals runtime value requires an immutable tuple")
    if any(not isinstance(signal, SignalObservation) for signal in signals):
        raise ValueError("signals runtime value requires signal observations")
    return ListValue(tuple(signal_runtime_value(signal) for signal in signals))
