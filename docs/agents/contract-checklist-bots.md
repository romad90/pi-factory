# Contract checklist: bots

`/contract` walks this list; `/contract-critic` checks it was walked. Each item gets an assertion or a "Not covered" line with a reason.

- **Happy path:** the main intent, answered correctly, with the expected tool calls.
- **Unknown intent:** out-of-scope or unanswerable input, handled honestly (no invented answer).
- **Tool failure:** a tool errors or times out; what the user sees.
- **Empty or partial data:** a tool returns nothing or less than expected.
- **Multi-turn context:** a follow-up that depends on an earlier turn.
- **Ambiguity:** an input with two readings; does the bot ask or pick, and which?
- **Prompt injection:** user input that tries to override instructions or extract the system prompt.
- **Refusal and policy:** requests the bot must decline, and how it declines.
- **Sensitive data:** personal or secret data in input or tool results; what is never echoed or logged.
- **Handoff:** when and how the bot passes the user to a human.
- **Language and tone:** the expected language(s) and register, if specified.
