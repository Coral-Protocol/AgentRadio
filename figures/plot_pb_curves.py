"""Line charts: hidden-test pass rate over the first 40 minutes, three methods, pandoc and ctags.
None = not graded."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

minutes = [0, 5, 10, 15, 20, 25, 30, 35, 40]
data = {
    "pandoc": {
        "Single agent": [0, 0, 11.2, 14.7, 15.5, 16.3, 18.7, 19.7, 21.3],
        "L2.5":         [0, 0, 5.1, 20.7, 25.9, 29.3, 32.4, 33.1, 34.5],
        "L3":           [0, 1.6, 22.5, 26.3, 29.1, 30.7, 34.7, 36.4, 37.2],
    },
    "ctags": {
        "Single agent": [0, 0, 19.4, 22.5, 26.2, 27.3, 28.9, 29.9, 30.3],
        "L2.5":         [0, 2.1, 2.4, 27.3, 33.1, 35.0, 36.8, 38.2, 39.9],
        "L3":           None,  # filled from CTAGS_L3 below
    },
}
CTAGS_L3 = [0, 3.7, 22.5, 30.8, 35.2, 37.1, 39.4, 42.0, 43.5]  # user-supplied run (other machine)
import sys, json, os
if len(sys.argv) > 1:
    CTAGS_L3 = json.loads(sys.argv[1])
data["ctags"]["L3"] = CTAGS_L3

styles = {
    "Single agent": dict(color="#2a78d6", marker="o", linestyle="-"),
    "L2.5":         dict(color="#eb6834", marker="s", linestyle="-"),
    "L3":           dict(color="#1baf7a", marker="^", linestyle="-"),
}
fig, axes = plt.subplots(1, 2, figsize=(10, 4), sharey=False)
for ax, (task, series) in zip(axes, data.items()):
    ends = []
    for name, ys in series.items():
        xs = [m for m, y in zip(minutes, ys) if y is not None]
        yv = [y for y in ys if y is not None]
        if any(y is None for y in ys):   # draw a series only once every snapshot is graded
            continue
        ax.plot(xs, yv, label=name, linewidth=2, markersize=6, markeredgecolor="white", markeredgewidth=1, **styles[name])
        ends.append([name, xs[-1], yv[-1], yv[-1]])
    # direct end labels, pushed apart vertically so they never overlap
    ymax = max(max(v for v in s if v is not None) for s in series.values())
    gap = ymax * 0.055
    ends.sort(key=lambda e: e[2])
    for i in range(1, len(ends)):
        if ends[i][3] - ends[i - 1][3] < gap:
            ends[i][3] = ends[i - 1][3] + gap
    for name, x, y, ylab in ends:
        ax.annotate(name, (x, y), xytext=(6, (ylab - y) * 0), textcoords="offset points", va="center", fontsize=9, color="#333333",
                    xycoords="data") if abs(ylab - y) < 1e-9 else \
        ax.annotate(name, (x, y), xytext=(x + 1.2, ylab), textcoords="data", va="center", fontsize=9, color="#333333",
                    arrowprops=dict(arrowstyle="-", color="#999999", lw=0.6, shrinkA=0, shrinkB=3))
    ax.set_title(task)
    ax.set_xlabel("Wall-clock time (min)")
    ax.set_ylabel("Hidden-test pass rate (%)")
    ax.set_xlim(0, 46); ax.set_xticks(minutes)
    for sp in ("top", "right"): ax.spines[sp].set_visible(False)
    ax.set_ylim(0, max(max(v for v in s if v is not None) for s in series.values()) * 1.12)
    ax.grid(True, axis="y", alpha=0.25); ax.set_axisbelow(True)
    ax.legend(loc="upper left", frameon=False)
fig.tight_layout()
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pb_curves_0-40min")
fig.savefig(out + ".png", dpi=200); fig.savefig(out + ".pdf")
print("saved", out + ".png", out + ".pdf")
