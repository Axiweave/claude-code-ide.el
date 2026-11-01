# Data Model: Fork a Session from the Sidebar with `S`

This feature stores no data. It adds one message between Emacs and omp.

## Fork request

- **Form**: the `pi:action` packet with the name `fork-spawn`. See [contracts/pi-action-packet.md](contracts/pi-action-packet.md).
- **Sender**: the manager sidebar command on `S`, for one row.
- **Receiver**: the omp of that row's Session A, through A's terminal input.
- **Fields**: none other than the name. It carries no text, directory, model, or option.
- **Validation in Emacs**: the row exists, its buffer is live, the buffer's terminal process is live, and its CLI type is `omp`.
- **Validation in omp**: no dialog owns input. After that, the `/fork spawn` refusals apply: vibe mode, no zmx session, a key on A's command line, and no saved conversation.

## Effect

A successful request creates one Sibling Session B, as spec 022 describes. Two requests create two Bs. A's draft, cursor, conversation, and running turn do not change.
