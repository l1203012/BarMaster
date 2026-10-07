# BarMaster
An application for the old MacBooks with the old TouchBar that barely uses resources in order to have a better Touchbar for applications such as Google Chrome, Slack and Generally

## Build

Needs only the Command Line Tools (no Xcode), macOS 13+.

```sh
Scripts/build.sh app   # → .build/BarMaster.app
Scripts/build.sh run   # build, quit the running copy, open it
python3 Scripts/make_logo.py   # regenerate the icon (needs Pillow)
```

See [Docs/PLAN.md](Docs/PLAN.md) for the design and milestones.

## Chrome buttons per website

Menu bar bottle → **Edit Chrome Buttons…** opens
`~/Library/Application Support/BarMaster/Chrome.json`. Saving it updates the
Touch Bar right away.

```json
{
  "domains": {
    "github.com": [
      { "title": "PRs", "symbol": "arrow.triangle.pull", "url": "https://github.com/pulls" },
      { "title": "Copy URL", "shell": "printf %s \"$BARMASTER_URL\" | pbcopy" }
    ],
    "youtube.com": [
      { "symbol": "playpause.fill", "keys": "k" },
      { "title": "2×", "js": "document.querySelector('video').playbackRate = 2" }
    ],
    "*": [ { "title": "Archive", "url": "https://web.archive.org/save/{url}" } ]
  }
}
```

- A domain also covers its subdomains (`github.com` → `gist.github.com`), and
  `www.` is ignored. `"*"` buttons show on every site.
- Each button has a `title`, an SF Symbol `symbol`, or both, plus one action:
  - `js`: runs in the page. Needs Chrome → View → Developer →
    **Allow JavaScript from Apple Events**.
  - `url`: opens in the current tab. `{url}` and `{host}` are filled in.
  - `keys`: a shortcut like `cmd+shift+c`, `k` or `alt+left`.
  - `shell`: runs with your login shell. Gets `$BARMASTER_URL`,
    `$BARMASTER_HOST` and `$BARMASTER_TITLE`.
- If the file has a mistake, a **⚠ Chrome.json** button appears instead. Tap it
  to open the file.
