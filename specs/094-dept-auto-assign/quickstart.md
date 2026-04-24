# Quickstart — 094-dept-auto-assign manual test plan

Prereqs: spec 092 is deployed; at least one admin, one technician with a department, one technician without a department, and at least two departments exist.

## 1. Admin sees and uses the picker (US2)

1. Log in as admin.
2. Open Files → Upload.
3. Expect: "Department (optional)" dropdown is visible, default "None (global)".
4. Pick department **Engineering**, upload any PDF.
5. Verify in Supabase: `files.department_id = <Engineering.id>`.
6. Repeat leaving the dropdown at "None (global)"; verify `files.department_id IS NULL`.

## 2. Technician with a department — picker hidden, auto-assigned (US1)

1. Log in as a technician whose `users.department_id` is set to **Maintenance**.
2. Open Files → Upload.
3. Expect: no department field anywhere on the form.
4. Upload a file.
5. Verify in Supabase: `files.department_id = <Maintenance.id>`.

## 3. Reporter / Supervisor / Superintendent — same as US1

Repeat test 2 for each role. Supervisor and Superintendent are treated as non-admin for this feature even though they are global *viewers*.

## 4. Spoofed `department_id` ignored (US3)

1. As a technician in **Maintenance**, open browser devtools → Network.
2. Craft a `POST /api/files/upload` with a multipart form that includes `department_id=<Engineering.id>`. (Use `curl` with a valid cookie/session.)
3. Verify the stored row has `files.department_id = <Maintenance.id>` — not Engineering.
4. Variant: send `department_id` empty / null. Same result.

```bash
curl -X POST https://<host>/api/files/upload \
  -F "file=@test.pdf" -F "title=spoof" -F "file_type=General" \
  -F "uploaded_by=tech@example.com" \
  -F "department_id=<Engineering.id>"
```

## 5. Non-admin without a department is blocked (US4)

1. Log in as a technician whose `users.department_id` is NULL.
2. Open Files → Upload.
3. Expect: upload button disabled, helper text *"Contact your admin to assign a department before uploading files."*
4. Attempt to bypass by crafting a direct API call:

```bash
curl -X POST https://<host>/api/files/upload \
  -F "file=@test.pdf" -F "title=blocked" -F "file_type=General" \
  -F "uploaded_by=no-dept-tech@example.com"
```

Expect HTTP 400 with body `{"detail":"User has no department assigned; contact your administrator."}`.

## 6. `/api/departments/mine` response shape

```bash
curl "https://<host>/api/departments/mine?user_email=tech@example.com"
```

Expect keys `departments`, `is_global_viewer`, `is_admin`, `primary_department_id`. For an admin: `is_admin=true`. For a non-admin with a department: `primary_department_id` non-null. For a non-admin without: `primary_department_id=null`.

## 7. No regression on existing files

1. Before any upload, snapshot count of `files.department_id IS NULL`.
2. Perform all tests above.
3. Recount; pre-existing null rows must be unchanged.
