# Release Corpus Smoke

Issue: [#1269](https://github.com/mihaelamj/cupertino/issues/1269)

This is the on-demand promotion gate for proving that the current checkout's
`cupertino` binary still works against an already prepared release corpus, such
as `~/.cupertino`.

It is intentionally read-only:

- It builds `cupertino` from this checkout.
- It copies the built executable into a temporary directory.
- It writes a temporary sibling `cupertino.config.json` beside that copy.
- It points the copy at the supplied corpus directory.
- It runs read/search/list smoke commands only.
- It never runs `setup`, `fetch`, `save`, or any reindex command.

Run it locally:

```bash
scripts/eval/release-corpus-smoke.sh ~/.cupertino
```

The corpus argument defaults to `$CUPERTINO_RELEASE_CORPUS`, then
`~/.cupertino`.

Script syntax, argument, and option docs live under
[`docs/scripts/eval/release-corpus-smoke/`](../scripts/eval/release-corpus-smoke/).

## What It Checks

The smoke fails when:

- One of the eight core release databases is missing or empty.
- `cupertino doctor` reports a schema or health failure.
- Search/read commands fail.
- JSON commands return invalid or empty typed payloads.
- A monitored release DB file changes size or mtime, or a sidecar file appears,
  disappears, or changes size during the run.

The command matrix covers:

- `doctor`
- `search`
- `read`
- `list-frameworks`
- `list-documents`
- `list-children`
- `list-samples`
- `read-sample`
- `package-search`
- package-backed `read --source packages`
- `search-symbols`
- `search-conformances`
- `search-generics`
- `inheritance`

## GitHub Workflow

Trigger **Release Corpus Smoke** from the Actions tab when a promotion or
release candidate touches read/search surfaces.

For a runner with the corpus already on disk, set:

- `runner-label`: a runner with Swift and the corpus, default `macos-15`
- `corpus-path`: the prepared corpus directory, default `~/.cupertino`

For a corpus stored as a workflow artifact, set:

- `artifact-run-id`: the workflow run containing the artifact
- `artifact-name`: the artifact to download
- `artifact-subdirectory`: optional directory inside the downloaded artifact

The artifact root, or the selected subdirectory, must contain the release DB
files directly.

## Release Use

Use this after normal build/test/lint verification and before tagging or
promoting a release that could affect runtime reads. Paste the final
`Release-corpus smoke passed` summary into the release PR or issue comment.
