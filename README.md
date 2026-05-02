# file-history.sh

`file-history.sh` is a lightweight, file-local history tool for situations where you want commit-like history for one file without putting that file into a Git repository yet.

It stores two artifacts next to the target file:

- `.${FILE}.base`: the last committed snapshot of the file
- `.${FILE}.patches.mbox`: an mbox archive containing one patch email per recorded change

Later, that mbox can be replayed with `git am` to reconstruct real Git commits.

## Motivation

This is useful when you are iterating on a standalone script or scratch file and want:

- small, incremental checkpoints
- readable diffs before recording a change
- a simple local log of changes
- the ability to turn those checkpoints into real Git history later

Typical cases:

- editing scripts in `~/bin`
- building up a patch series for a single file
- keeping history for a file before moving it into a repository
- reconstructing the evolution of a script from a local mbox archive

## Commands

```bash
file-history.sh commit FILE [message...]
file-history.sh ci FILE [message...]
file-history.sh diff FILE
file-history.sh vimdiff FILE
file-history.sh log FILE
file-history.sh show FILE
```

### `commit` / `ci`

Records the current diff between `FILE` and `.${FILE}.base` as one patch email appended to `.${FILE}.patches.mbox`, then updates `.${FILE}.base` to the current file contents.

Examples:

```bash
file-history.sh commit file-history.sh "Initial import"
file-history.sh ci file-history.sh "Add log subcommand"
```

If the message is omitted, the script uses `no message`.

If there is no diff, nothing is recorded.

### `diff`

Shows the working diff between the current file and the saved base snapshot.

Examples:

```bash
file-history.sh diff file-history.sh
file-history.sh diff get_test_output_v2.sh
```

If no base snapshot exists yet, it shows an add-from-empty diff using `/dev/null`.

### `vimdiff`

Opens an interactive diff between the base snapshot and the current file.

Example:

```bash
file-history.sh vimdiff file-history.sh
```

If no base snapshot exists yet, it opens an add-from-empty view.

### `log`

Lists recorded commits from the mbox archive in order.

Example:

```bash
file-history.sh log file-history.sh
```

Example output:

```text
   1  Fri, 01 May 2026 11:55:40 -0400  Initial import
   2  Fri, 01 May 2026 12:24:45 -0400  Add diff, checkin subcommands
   3  Fri, 01 May 2026 12:32:50 -0400  Added vimdiff subcommand
```

### `show`

Prints the last recorded patch entry from the mbox archive, similar to `git show` on the latest commit.

Example:

```bash
file-history.sh show file-history.sh
```

This prints the full last mbox entry, including headers and unified diff.

## Default behavior

Running the script without a command prints usage.

```bash
file-history.sh
```

## Base reconstruction behavior

If `.${FILE}.base` is missing but `.${FILE}.patches.mbox` exists, the script reconstructs the base automatically.

It does this by:

1. creating a temporary directory
2. initializing a temporary Git repository there
3. applying the mbox with `git am`
4. copying the reconstructed file back as `.${FILE}.base`
5. cleaning up the temporary directory

This is used for commands that need a base snapshot, such as `commit`, `diff`, and `vimdiff`.

The `log` command does not need reconstruction; it reads the mbox directly.

## How patches are stored

Each `commit`/`ci` appends a mail-style patch to the mbox. The stored patch includes:

- a synthetic `From` line with a pseudo commit id
- `From`, `Date`, and `Subject` headers
- a unified diff with `a/FILE` and `b/FILE` labels

The first recorded patch uses `/dev/null` as the old side so replaying the series creates the file cleanly.

## Import into a real Git repository later

To turn the local file history into actual Git commits:

```bash
mkdir my-repo
cd my-repo
git init
cp /path/to/.script.py.patches.mbox .
git am .script.py.patches.mbox
```

Important:

- copy the mbox, not the target file first
- let `git am` create and evolve the file from the patch series

## Requirements

- `bash`
- standard utilities: `diff`, `cp`, `date`, `mktemp`, `awk`
- a SHA-1 tool: `sha1sum` or `shasum`
- `git` when reconstructing a missing base from the mbox
- `vimdiff` if you want to use the `vimdiff` command

## Practical workflow

```bash
# record the initial version
file-history.sh ci myscript.sh "Initial import"

# inspect local changes
file-history.sh diff myscript.sh

# inspect interactively
file-history.sh vimdiff myscript.sh

# record another change
file-history.sh ci myscript.sh "Handle missing base reconstruction"

# inspect history
file-history.sh log myscript.sh
```

## Notes and limitations

- This is file-local history, not a replacement for a full Git repository.
- It tracks one file at a time.
- If the mbox is malformed, base reconstruction or later `git am` replay can fail.
- `vimdiff` requires an interactive terminal/editor environment.

## Related files

For a file named `example.sh`, the script will use:

- `.example.sh.base`
- `.example.sh.patches.mbox`

stored in the same directory as `example.sh`.