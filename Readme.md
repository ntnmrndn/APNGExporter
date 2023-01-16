#Asset Exporter

Convert animated PNG to .mov, preserving alpha channel.

Tip: You can mux PNGs into an APNG with ffmpeg:

```
ffmpeg -framerate 24 -i 'XXXX_%03d.png' XXXX.apng
```

Where files are following the pattern XXXX_001.png and framerate is 24fps
