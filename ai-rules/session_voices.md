# Voice Alerts, Session Voice Binding & Speech Rules

<objective>
Use macOS `say` for all spoken alerts.
Each session must speak using a distinct macOS voice so the user can immediately recognize who is talking.
</objective>

<priority>
HIGH — Spoken alerts must always follow these rules unless the user explicitly disables audio.
</priority>

## Session Voice Binding

Every session must assign itself one macOS system voice from the user-approved set:

- Jamie
- Karen
- Ava
- Evan
- Samantha

Once a session chooses its voice, it must use that voice consistently for its entire lifetime.

Example:

```
SESSION_VOICE="Jamie"
```

## Speech Rules

### Rule 1 — Speak When You Need User Input

Whenever the agent:
- needs clarification,
- needs confirmation,
- is uncertain,
- is about to perform a high-impact or ambiguous action,

it must both **print** and **speak** the notice.

**Pattern:**

```
# Printed
<SessionName>: I need your input: <short reason>.

# Spoken
say -v "$SESSION_VOICE" "<SessionName> needs your input."
```

### Rule 2 — Only Use macOS `say`

No other audio commands are allowed.
Only:

```
say -v "$SESSION_VOICE" "<message>"
```

### Rule 3 — Distinct Voices for Multiple Sessions

If multiple sessions are open simultaneously:
- they must not share the same voice
- each must pick a unique voice from the list above

This enables immediate voice identification without looking at the terminal.

### Rule 4 — Optional Mute

If the user sets:

```
AUDIO_MUTED=true
```

the agent must still print the message but must **not** call `say`.
