# b-tasks-harden: adversarial review of the backend tasks module

Scope (same as b-tasks): `family_hub_backend/src/modules/tasks/**`, `src/i18n/locales/en/tasks.json`,
`tests/tasks.test.js`. The full findings list is in `docs/progress/b-tasks.md` → "Hardening review".

## Done
- [x] Read the contract (§1, §7, §13), the backend guide, the compliance rules and the builder's code and tests.
- [x] Probed the live app on an in-memory MongoDB with: operator injection, mass assignment, `__proto__`,
      bad or uppercase ids, 100 kb+ bodies, emoji/RTL/Indic/control/zero-width/lone-surrogate text,
      date edge cases, pagination bounds, and races between the read and the write.
- [x] Fixed: the complete/reopen race that bypassed permissions (assignee now in the atomic filter, plus a retry).
- [x] Fixed: raw Mongoose messages echoing input (UTF-16 length limits that match the model).
- [x] Fixed: invisible-only titles, control characters and lone surrogates in title/description.
- [x] Fixed: push titles split grapheme clusters (Indic conjuncts, ZWJ emoji, flags).
- [x] Fixed: a pending task left for a removed member (the write re-checks the assignee and undoes itself on a lost race).
- [x] Fixed: `task_assigned` push when re-assigning a done task.
- [x] Fixed: the due-date lower bound rejected valid local midnights of 2000-01-01 east of UTC.
- [x] 22 new tests (71 in total). Each fix was mutation-checked: 8 mutations, all caught.
- [x] `node scripts/check-syntax.js`: all OK. `node --test tests/tasks.test.js`: 71/71. `npm test`: 623/623.

## Pending (handoffs, files I do not own)
- [ ] `src/middleware/error.js`: stop echoing Mongoose `ValidationError` messages (they contain the stored value).
- [ ] `src/lib/validate.js`: shared UTF-16 `max` and text normalisation helpers for the other modules.
- [ ] `src/modules/me/memberCascade.js`: delete the member row before purging their pending tasks.
- [ ] `docs/03-API_CONTRACT.md` §7: document the new behaviour (409 CONFLICT, text rules, done re-assign, due window).
- [ ] Translations of `tasks.json`: no new keys were added (the translators' key set is unchanged).

## Known issues
- See "Known issues / not changed" in `docs/progress/b-tasks.md`.
