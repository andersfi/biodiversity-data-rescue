# read run `2026-11-21_step0-c`

| item | value |
| :--- | :--- |
| started | 2026-11-21T16:04:46Z |
| finished | 2026-11-21T16:04:59Z |
| git commit | `1bb7eb9` |
| goldset.csv SHA-256 | `22631f4d9af0` |
| local files | `data/runs/read/2026-11-21_step0-c/` |

Step 0 of the reading test (docs/reading-benchmark.md, section 4).

## Calls

| call | model_requested | models_reported | input_tokens | cache_creation_input_tokens | cache_read_input_tokens | input_total | output_tokens | seconds | duration_ms |
| :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| stdin_check | claude-haiku-5-5 | claude-haiku-5-5 | 2 | 610 | 0 | 612 | 6 | 1.9 | 621 |
| canary | claude-haiku-5-5 | claude-haiku-5-5 | 2 | 654 | 0 | 656 | 692 | 5.8 | 4279 |
| overhead | claude-haiku-5-5 | claude-haiku-5-5 | 2 | 3340 | 0 | 3342 | 561 | 4.6 | 3104 |

## Checks

| check | value |
| :--- | :--- |
| CLI version | 2.1.330 (Claude Code) |
| all flags in `claude --help` | TRUE |
| record read from stdin | TRUE |
| JSON output fields | api_error_status, credential_expires_at, duration_api_ms, duration_ms, fast_mode_disabled_reason, fast_mode_state, first_content_frame_ms, is_error, modelUsage, num_turns, permission_denials, queued_turn_count, result, result_index, safety_stops, session_id, stop_reason, subagent_stats, subtype, terminal_reason, time_to_request_ms, total_cost_usd, ttft_ms, ttft_stream_ms, type, usage, uuid |
| canary strings checked (files) | 121 (2) |
| canary strings leaked | 0 |
| overhead answer valid against schema | TRUE |

Overhead per call with prompt and schema: 3342 input tokens (fresh + cache), 561 output tokens.

The canary answer is kept locally in `data/runs/read/2026-11-21_step0-c/canary_answer.txt`.
