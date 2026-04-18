# ~/.config/git

Chezmoi-managed files that live alongside `~/.gitconfig`. Current contents:

| File | Purpose |
|---|---|
| `allowed-signers` | whitelist consumed by `gpg.ssh.allowedSignersFile` so `git log --show-signature` verifies commits locally |

## Credential helper chain — what to know

`~/.gitconfig` wires up the helper chain per-URL for `github.com` and
`bitbucket.org`:

```
helper = ""                         # reset inherited osxkeychain
helper = cache --timeout 1800       # 30-min in-memory cache
helper = <home>/.local/bin/git-credential-op   # falls through on cache miss
```

`git-credential-op` reads a PAT/App-Password from 1Password via a service-account
token stored in the macOS keychain. One read per (host, user) per 30-min window;
after that the cache serves subsequent operations locally.

### Worth knowing

- **Rate-limit window is rolling, not calendar-bound.** 1Password's 60-minute
  per-SA-token limit starts at the *first* request, not at the top of the hour.
  If you burn budget at 2:00 pm, the window that matters is 2:00–3:00, not
  "until 3:00."

- **Cache is per-user, per-session, at `~/.cache/git/credential/socket`.**
  A reboot wipes it, which just means the next push does one more `op read` —
  harmless (2 reads vs. the 1,000/hr budget). The daemon terminates itself
  after the configured timeout.

- **Force a fresh read** (e.g. right after rotating a PAT in 1Password) with:

  ```sh
  git credential-cache exit
  ```

  Next git push refills the cache with the new credential.

### Normal-usage read budget

```
2 reads per cache fill (username + credential fields)
× 2 cache fills per hour per host (30-min timeout, worst case)
× 2 hosts (github.com + bitbucket.org)
= 8 reads/hr ceiling vs. 1,000/hr SA budget → ~0.8% utilization
```

Scripted `op` activity outside `git-credential-op` (loops of `op read`,
`op item list`, bulk `,op-sa-health` calls) consumes the same budget, so keep
those deliberate.
