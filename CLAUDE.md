# SalesPlace / NHC Live Sales Board

**Before any work on the sales board (شاشة المبيعات / `?tv=1` / `NHC_Live_Board.html`), read
[`docs/LIVE_BOARD_HANDOFF.md`](docs/LIVE_BOARD_HANDOFF.md) in full.** It holds the architecture, SQL run order,
upload flows, exact metric methodologies, UI map, test harness and the open items awaiting the user.

Essentials:
- Reply to the user (Tareq, NHC sales) **in Arabic**, short and concrete: what changed, which SQL to run, which file to replace, whether to re-upload the allocation file / revenue table.
- `SalesPlace_01.html` is the single source. `NHC_Live_Board.html` is generated — never edit it by hand; run `python3 tools/build_live_board.py` after every change.
- Work on branch `claude/supabase-app-ro5u8x`; commit, push, then send the changed files to the user. No PR unless asked. No model names in commits or code.
- Security: board is view-only; uploads/deletes need an admin account checked server-side (`admin_*` RPCs with `crypt()`); credentials stay in page memory only; the revenue view requires a user login and is never opened automatically.
- Supabase is not reachable from cloud sessions; ask the user to run diagnostic SQL and send a screenshot.
- Test with Playwright mocks in `tools/board_tests/` (setup in the handoff doc §9): no overflow, no page errors at 1920×1080, 1366×768 and phone sizes.
