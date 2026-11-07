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

Sources: [cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging),
[Desktop Code Remote Control](https://code.claude.com/docs/en/remote-control).
