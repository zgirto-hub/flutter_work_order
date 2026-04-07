# Quickstart: Link Payment Certificates to Letters

## Prereqs
- Migration `20260407_letter_cert_link_order.sql` applied.
- Backend has `pypdf` installed (`pip install pypdf`).
- Frontend is rebuilt.

## End-to-end test

1. Sign in as a letter author (or admin).
2. Create at least two payment certificates via the existing Payment Certificates screen. Note their certificate numbers.
3. Go to Letters v2 → new letter. Fill the required fields.
4. In the new **Attachments** section, tap **Add Payment Certificate** → picker opens.
5. Search by certificate number, select both certificates, confirm. They appear in the attachments list in the order added.
6. Reorder them by drag handle; remove one with the trash icon and re-add it at the end.
7. Save the letter → backend persists `letter_id` + `letter_link_order`.
8. Reopen the saved letter → both certificates are still linked in the chosen order.
9. Tap **Export PDF** → client generates cert PDFs locally, uploads them with `letter_body`, and receives back a single PDF. Open it — verify the letter comes first, followed by cert pages in the chosen order.
10. Attempt to attach the same certificate to a second new letter → confirmation dialog appears; on confirm, the cert moves to the second letter and is absent from the first.
11. Delete the second letter → both certificates are unlinked (verify in DB: `letter_id IS NULL` and `letter_link_order IS NULL`).

## Verification checklist

- [ ] Multipart request stays under Nginx's 50 MB cap for typical letters.
- [ ] Activity log has `attached_certificate`, `detached_certificate`, and `exported` entries.
- [ ] A non-author non-admin user receives 403 when attempting to attach.
- [ ] Deleting a certificate that is linked to a letter removes it from the letter's attachments list on next load (and does not crash export).
