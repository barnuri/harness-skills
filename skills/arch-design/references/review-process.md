# Design Review Process

This governs how a design gets reviewed and approved.
It is process guidance for the author, not content for the document — never paste it into a design doc.

## Ownership

- The **TL owns the design process** and ensures every step lands on time to meet the delivery date.
- **Requirements come from the PM.** Where R&D leads the feature, GMs and TLs own the requirements section.
- The **first PM review** includes the Director, GM, and TL only, and is reviewed online. Architects and tech leaders join relevant projects.
- The first requirement review covers **PM requirements, not implementation challenges**.

## Before the review meeting

- **Send the design document at least 2 days before the meeting.**
- Requirements are **reviewed offline by all stakeholders** — not read for the first time in the meeting.
- **Close major open issues with a small forum first.** The design meeting is the finalizing step, not the debate.
- **Reschedule** if stakeholders have not reviewed the design, or if the meeting will not be effective.

## Planning the design

- For a first design, ask **Alex or Rachel** for mentoring.
- Review the **problem statement** with the PM and stakeholders before writing detailed requirements, so the scope is agreed.
- **Coordinate proactively** with all stakeholders to shorten the design duration.
- **Schedule design meetings early** to secure slots with busy stakeholders.
- Leave a **buffer between design and implementation** so the team is not delayed.

> Good design = good communication with stakeholders.

## How this maps to the document

| Process step | Document field |
|---|---|
| Draft started | `status: Draft` in the frontmatter |
| Sent for the 2-day pre-read | `status: In review` |
| All approval areas signed off | `status: Approved` — triggers promotion to `docs/architecture/<area>/` |
| Each revision after a review | A new row in the **Document history** table |
| Each area's sign-off | A row in the **Approvals** table |


## The requirements approval gate

`Detailed Requirements (Customer-Facing)` is approved on its own, before any downstream section is
written. Until product signs it off the document ends there on purpose.

**Raise it, do not resolve it.** When later work conflicts with an approved section, the author
stops and brings it to the approver. The temptation is always to make the small edit and move on,
because the new wording is usually better — but the approval was given on specific text, and
changing that text without saying so means the record of what product agreed to is now wrong.

After sign-off the section is frozen: append `R<n>`, never edit or renumber an approved one, and
send a genuine change back for re-approval with a Document history row recording it. Everything
downstream — approach, interfaces, persistence, life cycle, ops — is written against the frozen
numbers, which is what makes those numbers safe to cite in tasks and tests.
