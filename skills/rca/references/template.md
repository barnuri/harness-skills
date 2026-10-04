# {Incident title — specific and one line}

**Date:** {YYYY-MM-DD — the incident date}

**Author:** {author}

**Severity:** {SEV1 | SEV2 | SEV3 — or your best estimate}

**Status:** Investigating | Mitigated | Resolved

---

## Goal

{What the team was trying to do, or the normal job the affected system does. Frame what "working" looked like before the incident, so the rest of the document has context.}

---

## Summary — What Broke

{2–4 sentences: what failed, who/what was impacted, how long it lasted, and how it ended. This is the TL;DR — no root-cause detail, just the shape of the incident.}

---

## Root Cause

{The actual causal chain, not the surface symptom. Push past the first answer to the underlying cause. If the cause is still unconfirmed, say so and list the leading hypotheses.}

### Contributing Factors
- {Things that made the impact worse, or slowed detection/recovery. Remove this subsection if there are none.}

---

## Timeline

All times in {timezone}.

<table border="1" cellpadding="6" cellspacing="0" style="border-collapse: collapse">
<thead>
<tr><th>When</th><th>Event</th></tr>
</thead>
<tbody>
<tr><td>{YYYY-MM-DD HH:MM}</td><td>{First symptom / what triggered the incident}</td></tr>
<tr><td>{YYYY-MM-DD HH:MM}</td><td>{Detection — alert fired / user reported}</td></tr>
<tr><td>{YYYY-MM-DD HH:MM}</td><td>{Diagnosis milestone}</td></tr>
<tr><td>{YYYY-MM-DD HH:MM}</td><td>{Mitigation applied}</td></tr>
<tr><td>{YYYY-MM-DD HH:MM}</td><td>{Resolved — service back to normal}</td></tr>
</tbody>
</table>

---

## Action Items

<table border="1" cellpadding="6" cellspacing="0" style="border-collapse: collapse">
<thead>
<tr><th>#</th><th>Action</th><th>Type</th><th>Owner</th><th>Due</th><th>Status</th></tr>
</thead>
<tbody>
<tr><td>1</td><td>{Concrete, specific action}</td><td>Prevent / Detect / Mitigate</td><td>{owner or TBD}</td><td>{YYYY-MM-DD or TBD}</td><td>{Done / Open}</td></tr>
<tr><td>2</td><td>{…}</td><td></td><td></td><td></td><td></td></tr>
</tbody>
</table>
