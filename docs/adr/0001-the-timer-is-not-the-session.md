# The Clock timer tracks a session, it does not define one

The first design of the study session macro made the Clock.app timer the
identity of a session: the timer started the session, and the timer ended it.
Retroactive entry breaks that rule, because a block that the user records after
the fact has no timer. We widened the definition instead: a session is a topic,
a start, and an end, and the timer is one optional way to track a live session.

Every note now carries a `source` field with the value `live` or `retro`. This
matters because `status: completed` used to mean "a timer rang near the planned
end", which is evidence. A retro session only asserts it. Without the field, the
completion rate and the distraction average on the dashboard stop meaning
anything. A note with no `source` field is live, because every note written
before this change was timer-backed.

## Considered options

- **Two record types.** A Session with a timer and an outcome, and an Entry that
  the user asserts. This is more honest, but it doubles the surface for a
  difference the user mostly wants to ignore.
- **No marker.** Write retro sessions as ordinary completed sessions. Rejected,
  because it silently corrupts the dashboard.
