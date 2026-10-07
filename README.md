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
