# Acceptance tests

Run these tests with the repository's runtime verification passing. Record the date, macOS version, installed versions, and result for each case.

Use these result values: `PASS`, `FAIL`, `BLOCKED`, or `NOT RUN`. For a failure, save the time, connected keyboards, observed keys, verification output, and recent service logs.

## Basic mapping smoke test

Test separately on the cabled Magic Keyboard and the R-GO Keyboard:

- Type letters, numbers, punctuation, Return, Tab, and Space.
- Confirm each physical modifier works normally.
- Tap `A S D F J K L ;` and confirm eight ordinary characters.
- Hold each home-row key and confirm its documented modifier.
- Confirm Caps Lock sends Backspace.
- Confirm `D+F+J/K/I/L` sends left/down/up/right.
- Confirm physical Command+Option with `J/K/I/L` sends left/down/up/right.
- Confirm `F1`–`F12` perform the documented Apple media/function actions.
- Confirm there are no duplicate characters, dropped characters, or stuck modifiers.

## Keyboard lifecycle matrix

| Case | Starting state | Action | Expected result |
|---|---|---|---|
| No Bluetooth keyboard at boot | R-GO off; Magic Keyboard cabled | Restart, log in, verify, and type | Startup does not wait for R-GO; Magic Keyboard works |
| Bluetooth present at boot | R-GO on and paired | Restart, log in, verify, and type on both | Both keyboards work; no duplicate output |
| Late Bluetooth connection | Boot with R-GO off | Turn R-GO on, wait for macOS connection, then type | R-GO is picked up without manual service intervention |
| Bluetooth disconnect | Both keyboards working | Turn R-GO off and continue on Magic Keyboard | Magic Keyboard remains usable; service stays healthy |
| Bluetooth reconnect | R-GO was disconnected | Turn R-GO on and type | R-GO is picked up again; mappings apply exactly once |
| Repeated hot-plug | Both keyboards working | Disconnect/reconnect R-GO three times | Every cycle recovers; no accumulating processes or duplicate keys |
| Two keyboards | Both connected | Alternate and then type concurrently | Both are remapped; virtual output is not reprocessed |
| No physical keyboard | Disconnect/turn off external keyboards where safe | Wait through at least one supervision interval | Service remains recoverable and accepts a later keyboard |
| Sleep/wake | Both connected | Sleep, wake, unlock, then type | Both recover without stuck modifiers or duplicates |
| Lock screen | Logged in and Kanata active | Lock and type only in safe fields | Keyboard uses normal unmodified behavior while locked; remapping resumes after unlock |
| Fast user switching | Kanata active | Switch away and return | Kanata releases control outside the active session and resumes safely |
| Supervised restart | Both connected | Stop only the Kanata child process | Supervisor restarts it and mappings return once |
| Restart without Bluetooth | R-GO off; Magic Keyboard cabled | Restart and complete verification | No named-keyboard dependency blocks startup |

Do not test the “no physical keyboard” case unless a reliable pointing device and a recovery route remain available. On a laptop, the built-in keyboard counts as a physical keyboard.

## Runtime invariants

After each lifecycle case, verify:

- exactly one repository-managed Kanata service/supervisor is active;
- exactly one repository-managed VirtualHID daemon is active;
- the expected Kanata child process is active;
- the virtual output keyboard is not captured as an input device;
- no Karabiner-Elements processes or remaps are active;
- verification reports the pinned versions and valid configuration;
- logs show no restart loop, repeated driver connection failure, or permission denial.

## Home-row accuracy phase

Begin only after every required deployment case passes.

Test at normal speed and then at deliberately fast speed. Include repeated same-hand rolls:

```text
as sa sd ds df fd jk kj kl lk l; ;l
asdf fdsa jkl; ;lkj
quest water great draft value
youth union point home minor
```

Also include opposite-hand rolls, capitalization, editor shortcuts, browser shortcuts, and intentional two- and three-modifier chords. Use the same sample and application for every tuning iteration.

Record:

- accidental shortcuts/modifiers;
- letters emitted late, lost, or duplicated;
- intentional modifier chords that fail;
- stuck modifiers;
- the exact config change under test.

Change one home-row setting at a time. Rerun the basic mapping smoke test after each change. The target is no configuration-induced shortcuts or stuck modifiers during at least five minutes of mixed normal and fast typing on both required keyboards.

## Final replication test

On the second clean Apple Silicon Mac:

1. Clone only this repository.
2. Run static checks.
3. Follow the clean-slate/install workflow without copying local files from the first Mac.
4. Complete only the documented macOS approvals and restarts.
5. Run runtime verification and this acceptance plan.

The setup passes replication only if no machine-specific edits, undocumented services, Karabiner-Elements installation, or files from the migration archive are needed.
