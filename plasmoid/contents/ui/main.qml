import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

// Pure-QML per-core CPU grid. Reads /proc/stat directly at `fps`.
// Requires QML_XHR_ALLOW_FILE_READ=1 in plasmashell's environment (see README).
PlasmoidItem {
    id: root

    readonly property int fps: 24
    // /proc/stat counts in 10 ms ticks, so a single 42 ms frame is only ~4
    // ticks per core and jumps in ~25% steps. Measure over a short window
    // instead; it still updates every frame. 200 ms is about +/-5%.
    readonly property int windowMs: 200
    // Jerk: second difference of usage over windowMs steps. Steady ramps
    // (50 -> 60 -> 70) score 0; reversals (0 -> 100 -> 10) score high.
    readonly property real jerkDeadzone: 0.15   // ignore noise below this (0..1)
    readonly property real jerkDecay: 0.85      // per frame, ~1 s to fade

    property var usage: []
    property var history: []   // [{t, busy: [...], total: [...]}]
    property var frames: []    // recent usage arrays, newest last
    property var jitter: []    // per-core 0..1, drives shake and yellow fringe

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    function readStat() {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "file:///proc/stat", false);   // ~50 us, sync is fine
        xhr.send();
        const busy = [], total = [];
        for (const line of xhr.responseText.split("\n")) {
            if (!line.startsWith("cpu")) break;
            if (line[3] === " ") continue;             // skip aggregate line
            const f = line.split(/\s+/);
            // user nice system idle iowait irq softirq steal (guest is in user)
            let tot = 0;
            for (let i = 1; i <= 8; i++) tot += Number(f[i]) || 0;
            const idle = (Number(f[4]) || 0) + (Number(f[5]) || 0);
            busy.push(tot - idle);
            total.push(tot);
        }
        return { t: Date.now(), busy: busy, total: total };
    }

    function sample() {
        const now = readStat();
        const h = history;
        h.push(now);
        // Keep exactly one sample at or older than the window edge.
        while (h.length > 2 && now.t - h[1].t >= windowMs) h.shift();
        const old = h[0];
        if (old.total.length !== now.total.length) {   // CPU hotplug
            history = [now];
            frames = [];
            jitter = [];
            return;
        }
        if (h.length < 2) return;
        const out = new Array(now.total.length);
        for (let i = 0; i < out.length; i++) {
            const dt = now.total[i] - old.total[i];
            const db = now.busy[i] - old.busy[i];
            out[i] = dt > 0 ? Math.max(0, Math.min(100, 100 * db / dt)) : 0;
        }
        usage = out;
        updateJitter(out);
    }

    function updateJitter(u) {
        const lag = Math.max(1, Math.round(windowMs * fps / 1000));
        const f = frames;
        f.push(u);
        while (f.length > 2 * lag + 1) f.shift();
        const j = new Array(u.length);
        for (let i = 0; i < u.length; i++) {
            let k = 0;
            if (f.length === 2 * lag + 1) {
                // |u(t) - 2u(t-W) + u(t-2W)| maxes at 200 for 0 -> 100 -> 0.
                const d2 = Math.abs(f[2 * lag][i] - 2 * f[lag][i] + f[0][i]) / 200;
                k = Math.max(0, (d2 - jerkDeadzone) / (1 - jerkDeadzone));
            }
            j[i] = Math.max((jitter[i] ?? 0) * jerkDecay, k);
        }
        jitter = j;
    }

    function heat(pct) {
        // 0% transparent -> 100% red, curved so light loads stay faint.
        const t = Math.pow(Math.max(0, Math.min(1, pct / 100)), 0.8);
        return Qt.rgba(1, 0, 0, t);
    }

    Timer {
        interval: Math.round(1000 / root.fps)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 40
        Layout.minimumHeight: 40
        Layout.preferredWidth: 240
        Layout.preferredHeight: 240
        Layout.fillWidth: true
        Layout.fillHeight: true

        Grid {
            id: grid
            anchors.fill: parent
            readonly property int n: Math.max(1, root.usage.length)
            columns: Math.ceil(Math.sqrt(n * width / Math.max(1, height)))
            readonly property int rowCount: Math.ceil(n / columns)
            spacing: 2

            Repeater {
                model: root.usage.length
                Rectangle {
                    id: cell
                    required property int index
                    readonly property real j: root.jitter[index] ?? 0
                    width: (grid.width - (grid.columns - 1) * grid.spacing) / grid.columns
                    height: (grid.height - (grid.rowCount - 1) * grid.spacing) / grid.rowCount
                    radius: 2
                    color: root.heat(root.usage[index] ?? 0)
                    border.width: j > 0.01 ? Math.max(1, j * Math.min(width, height) * 0.15) : 0
                    border.color: Qt.rgba(1, 0.85, 0, Math.min(1, j * 1.5))
                    // Glide between samples so 24 fps reads as continuous motion.
                    Behavior on color {
                        ColorAnimation { duration: Math.round(1000 / root.fps) }
                    }
                    // Re-rolled whenever j changes, i.e. every frame while it decays.
                    transform: Translate {
                        readonly property real amp: cell.j * Math.min(cell.width, cell.height) * 0.08
                        x: (Math.random() * 2 - 1) * amp
                        y: (Math.random() * 2 - 1) * amp
                    }
                }
            }
        }
    }
}
