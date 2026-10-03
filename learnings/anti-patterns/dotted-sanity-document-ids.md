# Anti-pattern: a `.` in a Sanity document id (silently private in production)

**Seen in:** a mission on a private project, at production deploy

## What happened

A publish script wrote a catalogue of generated documents to Sanity with deterministic ids of the form `<type>.<slug>`, a natural-looking namespace.

Every write succeeded. The Studio listed every document. An authenticated GROQ query returned every document. Production rendered its empty state, as if nothing had been published.

Sanity treats a `.` in a document id as a **private namespace**: the document is readable with a token and invisible to the anonymous reader that a *public* dataset serves a website with. `drafts.` is the familiar instance of the same rule; it is not the only one.

The tell, once looked for: of all the anonymously readable documents in that dataset, **none** contained a dot. The only dotted ids were Sanity's own system documents (`_.groups.*`) and ours.

## Why it is so hard to spot

Every diagnostic an engineer reaches for first is authenticated:

- the Studio — authenticated;
- `sanity documents get` — authenticated;
- a `curl` with the write token already exported in the shell — authenticated.

All of them show the data. The one unauthenticated reader is the deployed site, which reports only an empty state. There is no error, no warning, no failed write. The document-fetch endpoint does say `"omitted":[{"reason":"permission"}]`, but only if you request a specific id *without* a token.

## Do this instead

- **Use a separator that is not a dot.** `<type>-<slug>`, matching whatever convention already-public documents use in the same dataset (Sanity's own asset ids look like `image-<hash>-...`).
- **Assert it.** A unit test over the generated documents — no `_id` or `_ref` may contain `.` — costs three lines and fails before anything reaches the CMS.
- **Verify as the anonymous reader.** After any first publish of a new document type, run one unauthenticated query. `curl` *without* the token, in a shell where the token is not exported. Comparing authenticated and anonymous counts is the whole diagnosis.

## Generalisation

When a system has a privileged and an unprivileged read path, **a first-time publish must be verified on the unprivileged one.** The privileged path is the one you have credentials for, so it is the one you will reach for, and it is the one that cannot see the bug.
