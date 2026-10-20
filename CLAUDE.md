# SalesPlace / NHC — تطبيق المبيعات الموحّد (التفاصيل + العرض الشامل)

**Before any work, read [`docs/LIVE_BOARD_HANDOFF.md`](docs/LIVE_BOARD_HANDOFF.md) in full.** It holds the architecture,
security model, SQL run order, upload flows, exact metric methodologies, UI map, test harness and the open items awaiting the user.

Essentials:
- Reply to the user (Tareq, NHC sales) **in Arabic**, short and concrete: what changed, which SQL to run, which file to replace, whether to re-upload the allocation file / revenue table / employee roster.
- **One file only: `SalesPlace_01.html`.** It is the app (التفاصيل), the sales board for laptop/TV (`?tv=1`, العرض الشامل) and the phone board (`?tv=1&m=1`). The old generated `NHC_Live_Board.html` and `tools/build_live_board.py` are retired — do not recreate them.
- Work on branch `claude/supabase-app-ro5u8x`; commit, push, then send the changed files to the user. No PR unless asked. No model names in commits or code.
- Security (`app_security.sql`): every screen, including the TV, requires login (`login_v2` → session token). **All** data calls go through the `api` / `api_read` gateway with that token; the public key alone opens nothing. Uploads/deletes need an admin account checked server-side (`admin_*` RPCs with `crypt()`); passwords stay in page memory only. Financial data (revenue, collections, contract values, financing amounts, salaries) needs `app_users.can_fin` (admins always) — enforced server-side (`API_FIN`, key stripping) and hidden client-side (`FIN`, `html.noFin`). TV/exhibition sessions (`kind='tv'`) are 30-day view-only. Never read or upload national IDs, emails or phone numbers from any file.
- Supabase is not reachable from cloud sessions; ask the user to run diagnostic SQL and send a screenshot. A local Postgres (port 5499) mirrors the SQL for tests (see handoff §8).
- Test with Playwright mocks in `tools/board_tests/` (setup in the handoff doc §9; `gw.js` emulates the gateway and seeds a session): no overflow, no page errors at 1920×1080, 1366×768 and phone sizes; `login.js` and `nofin.js` cover login/session/financial gating.
