---
name: email
description: Email work order PDFs and weekly summaries to recipients
entrypoint: email.py
requiresConfirmation: []
triggers:
  - "send work order # to <email>"
  - "email the weekly summary"
  - "send pdf to someone@example.com"
  - "email work order 1234 to admin"
---

# Email Skill

This skill sends work order PDFs and weekly summaries via email. Requires the Exchange-SMTP feature to be deployed.

## Actions

### send_work_order_pdf

Sends a PDF of a specific work order to a recipient.

**Arguments**:
- `job_no` (string): The job number of the work order
- `to` (string): Recipient email address (required)
- `cc` (array, optional): Additional recipients
- `subject` (string, optional): Custom email subject

**Example invocations**:
- "send work order #1234 to director@example.com"
- "email the PDF of work order 42 to manager@company.com"
- "send #1234 pdf to test@example.com"

**Validation**: `to` must be a valid email address (basic regex validation)

**Response on success**: "📧 Sent work order #{job_no} PDF to {to}."

**Errors**:
- Invalid email → "Invalid email address: {to}."
- Work order not found → "Work order #{job_no} not found."
- Email backend unavailable → "Email backend not available yet."

---

### send_weekly_summary

Sends a weekly summary email with closed work orders.

**Arguments**:
- `to` (string, optional): Recipient email address (defaults to admin email)

**Example invocations**:
- "email the weekly summary"
- "send weekly summary to manager@example.com"

**Response on success**: "📧 Weekly summary emailed to {to}."

**Errors**:
- Email backend unavailable → "Email backend not available yet."