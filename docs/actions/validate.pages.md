# `actions/validate.pages.sh`

Fetches the published GitHub Pages files and compares them with this checkout.
Use it after a Pages deployment to confirm that the served setup runners,
Ansible content, and action documentation match the committed source.

```bash
bash actions/validate.pages.sh
```

The default site is `https://devs-guide.github.io/debian`. To validate another
published environment, set `BASE_URL`:

```bash
BASE_URL=https://example.invalid/debian bash actions/validate.pages.sh
```

It requires `curl` and network access. Downloads are stored only in a temporary
directory and are removed by the operating system's normal temporary-file
cleanup policy.
