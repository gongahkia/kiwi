# Support bundles

`kiwi doctor` is a local, offline diagnostic command. It reports the build
version/revision, operating-system and LuaJIT summary, display-session kind,
safe terminal configuration summary, terminfo availability, a best-effort
adapter probe, known feature availability, and explicit unavailable live-session
state. It does not attach to an existing terminal window.

For a source checkout, run:

```sh
make doctor
make doctor ARGS='--json'
make doctor ARGS='--bundle kiwi-support.json --json'
```

For an extracted release artifact, run:

```sh
./kiwi-<version>-linux-x86_64/bin/kiwi doctor
./kiwi-<version>-linux-x86_64/bin/kiwi doctor --bundle kiwi-support.json --json
```

The default report and bundle make no network request. They exclude terminal,
clipboard, shell, and arbitrary environment content. File paths and extension
module names are represented only as configured/count booleans; known
configuration values are allowlisted. Bundle JSON has schema version 1 and a
fixed 64 KiB maximum. Attach the generated JSON to an issue only after you have
reviewed it. If the report says an adapter, terminfo, renderer, or terminal
state is unavailable, that is an explicit observation rather than an omitted
field. Kiwi does not retain live diagnostic history between processes, so a
doctor invocation cannot recover terminal content or historical frame data.

For reproducible reports, include the doctor JSON, the exact command used, and
the observed behavior. Do not attach recordings, screenshots, shell history,
or custom extension source unless you have separately reviewed their content.
