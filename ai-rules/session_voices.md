# Voice Alerts, Session Binding & Audio Control

<objective>
You MUST use macOS `say` to speak aloud whenever user input is needed AND you MUST bind each session to a distinct voice so the user can immediately know which session is speaking (e.g., two terminals, two agents).
</objective>

<priority>
HIGH — This rule overrides any conflicting behavior. Spoken alerts MUST always follow these rules unless the user explicitly disables audio.
</priority>

<cognitive_triggers>
Keywords: say, macOS voice, audio alert, Karen, Jamie, session voice, terminal, silence, mute, unmute, Codex, Claude Code
</cognitive_triggers>

## CRITICAL RULES

### Rule 1 — Spoken Alerts When User Input Is Needed
You MUST speak when you:
- need confirmation,
- require user clarification,
- detect destructive or high-impact actions,
- are uncertain about multiple architectural paths.

**Pattern:**

```bash
# Text
<SessionName> session: I need your input: <short reason>.

# Speech
say -v "<SESSION_VOICE>" "<SessionName> session: I need your input."