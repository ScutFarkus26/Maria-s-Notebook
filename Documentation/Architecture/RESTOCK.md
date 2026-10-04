# Restock (Supplies + Orders)

Moved from `Cosmic Daybook/CLAUDE.md` on 2026-10-04. The build plan and its history are in `../Implementation/RESTOCK_PLAN.md`; this file holds the rules for the shipped feature. They are rules: follow them.

## Rules

Plan and history: `../Implementation/RESTOCK_PLAN.md`. One page, raw section value `supplies` (`.orders` is an alias).

- A **staple** is a `CDSupply` with a level (Stocked / Low / Out) and a source (office / order); a **need** is a `CDOrderItem`. A staple that goes Low or Out has exactly one open need (`supplyID`); a one-off is a need on its own. Supply, SupplyTransaction and OrderItem are in the classroom share (schema 15).
- **`RestockService` is the only writer** (notebook page, Assistant, Siri, MCP); callers save (`SaveCoordinator` on screen, `AssistantSave` on the phone). Every level change writes a `CDSupplyTransaction` (quantity 0) for History. `reconcile()` folds needs two devices opened at once, keeping the oldest; screens run it on appear and on import, never in a loop.
- **Counts:** "to order" means not yet asked for. An item asked for waits on the office and isn't counted on the badge, Today's card or the page header.
- The count → level launch step (`RestockLevelBackfill`) runs on the Mac only; a pre-v37 restore runs it on any device.
- **The stage is derived, never stored:** `CDOrderItem.stage` reads received > confirmed > asked for > to request off `receivedAt` / `confirmedAt` / `requestedAt`. Office needs go To Request → Received only. Items asked for in one message share a `requestID`. Quantity is 1–999 (`OrderService.quantityRange`).
- Draft Request (`OrderRequestDraftSheet`) builds the email with `OrderRequestMessage` (wording pinned by `OrderServiceTests`), with links cleaned by `OrderLinkCleaner` (Amazon → `/dp/ASIN`, tracking stripped), and marks the included items asked for when Mail reports it sent. Only the guide sends it.
- Who requests go to lives in `OrderRequestPrefs`, synced through `SyncedPreferencesStore`, edited in Settings › Communication › Order Requests and from the Restock page.
