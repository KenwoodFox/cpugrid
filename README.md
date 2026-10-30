# cpugrid (pure QML)

A better plasma 6 widget for BIG cpu distrubutions

## Install

Will need `QML_XHR_ALLOW_FILE_READ`

```sh
install -Dm644 qml-xhr-file-read.sh ~/.config/plasma-workspace/env/qml-xhr-file-read.sh
```

Log out and back in, then:

```sh
kpackagetool6 -t Plasma/Applet -i plasmoid     # -u to upgrade later
```

Add "CPU Grid (fast)" from the widget picker. To test in a window:
`QML_XHR_ALLOW_FILE_READ=1 plasmawindowed net.snowsune.cpugrid`

## Tuning

Edit `fps` and `windowMs` at the top of `contents/ui/main.qml`. 200 ms is
about ±5% accurate; 100 ms is twitchier, about ±10%.
