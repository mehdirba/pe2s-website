---
name: fcr
description: Read any web page, PDF datasheet or supplier catalog (incl. JS-rendered) as compact Markdown via the local `fcr` CLI. Use instead of WebFetch/curl whenever page content, specs or prices are needed.
---

# fcr — token-minimal web reading

Run via Bash. Escalate only as far as needed:

1. `fcr -t <url>` — headings only. Decide what you need.
2. `fcr -s 'spec|technical|data' <url>` — just the matching section(s).
3. `fcr -g 'KNX|PoE|IP[0-9]{2}|voltage' <url>` — just matching lines.
4. `fcr <url>` — full main content, capped at 12k chars.

Repeat calls on the same URL hit a 24h cache: probe with `-t`, then `-s`, at no fetch cost.

- JS shells/SPAs auto-render in headless Chrome. If output is empty or nav-only: `fcr -j <url>`; lazy-loaded product grids: `fcr -j -S <url>`.
- Find the right page on a site first: `fcr map <site> <keyword>`.
- PDFs/DOCX: same command, parsed locally.
- `-L` only if you must follow links; `-m 0` only if the user wants the whole page.
- Never paste full pages into the reply; extract the values asked for.
