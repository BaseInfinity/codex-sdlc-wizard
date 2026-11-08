# Claude desktop targets

Claude Code sessions in Desktop's Code tab use native cross-session messaging
once registered. A terminal controller can use `ListAgents` / `SendMessage`;
Codex can relay through a Claude CLI courier. `codex queue` targets Codex, not
Claude. No raw writes to another session's private inbox socket are needed.

Inbound permission rules still apply. A held message is not delivered, and
Desktop cannot display the terminal approval dialog. Default-held messages can
expire after five minutes. Check the delivery result and the receiver's
correlated response; never approve a dialog on the user's behalf or silently
widen inbound settings.

For a live test, identify an existing local Desktop Code session by its unique
registered name/ref, confirm the target, send one recorded envelope, and await
one result. A running app without a registered Code session supplies no target.
Ordinary Desktop chats and Cowork were not verified as native targets; do not
claim universal access or assume an installed plugin makes them reachable.

## Codex conductor delegates a Desktop startup

When the user authorizes a new Claude Desktop Code session, a Codex conductor
may delegate that bounded host task to a discovered, registered Claude
conductor. Record the request in the canonical Conduct outbox and deliver it
through the registered Claude route. The receiver uses its own verified
`claude-desktop.sh`; this Codex package deliberately does not vendor that shell
driver or its Accessibility Python. This is user-authorized delegation, not
direct Codex GUI/Desktop access.

The receiver owns permissions and runtime mode. Delegation never authorizes it
to override a runtime denial, approve a dialog, change modes, or claim broader
access. Without an existing Trust grant, require `--no-trust`; if the folder
needs Trust, return `NEEDS_TRUST` instead of clicking. Write one exact result
referencing the request into the canonical `.brain/runs/<run-id>/inbox/` and
include actual receiver evidence. A prompting relay return message may expire,
so transport acceptance is not evidence of the receiver outcome.
Capture the receiver result before reporting success. Do not create response
loops or a permanent watcher.

Sources: [cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging),
[Desktop Code Remote Control](https://code.claude.com/docs/en/remote-control).
