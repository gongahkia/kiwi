# K1 ETF A/B Record

Date: 2026-06-21.
Build: `build/ci/strok`.
Host: MacBook Air `Mac15,12`, Apple M3, macOS 26.5.1.

Fixture:

```sh
expr='lt(abs(Y-70),2)*gte(X,90)*lte(X,210)+lt(abs(Y-170),2)*gte(X,90)*lte(X,210)+lt(abs(X-90),2)*gte(Y,70)*lte(Y,170)+lt(abs(X-210),2)*gte(Y,70)*lte(Y,170)+lt(abs(Y-40),2)*gte(X,130)*lte(X,250)+lt(abs(Y-140),2)*gte(X,130)*lte(X,250)+lt(abs(X-130),2)*gte(Y,40)*lte(Y,140)+lt(abs(X-250),2)*gte(Y,40)*lte(Y,140)+lt(abs(-30*X-40*Y+5500),100)*gte(X,90)*lte(X,130)*gte(Y,40)*lte(Y,70)+lt(abs(-30*X-40*Y+17500),100)*gte(X,210)*lte(X,250)*gte(Y,40)*lte(Y,70)+lt(abs(-30*X-40*Y+9500),100)*gte(X,90)*lte(X,130)*gte(Y,140)*lte(Y,170)+lt(abs(-30*X-40*Y+21500),100)*gte(X,210)*lte(X,250)*gte(Y,140)*lte(Y,170)'
ffmpeg -hide_banner -loglevel error -f lavfi -i "nullsrc=s=320x240:d=0.3:r=10,geq=lum='if(gt($expr,0),255,0)':cb='128':cr='128'" -frames:v 3 -pix_fmt yuv420p -y /tmp/strok-k1-wire-cube.mp4
```

Commands:

```sh
./build/ci/strok --mode structure --edge-threshold 0.02 --dog-sigma 0 --width 80 --height 30 --fps 1000 --color-mode mono --export /tmp/strok-k1-raw.ansi --log /tmp/strok-k1-raw.log /tmp/strok-k1-wire-cube.mp4
./build/ci/strok --mode structure --etf-iters 3 --edge-threshold 0.02 --dog-sigma 0 --width 80 --height 30 --fps 1000 --color-mode mono --export /tmp/strok-k1-etf.ansi --log /tmp/strok-k1-etf.log /tmp/strok-k1-wire-cube.mp4
```

Results:

| Variant | Frames | Cells | Bytes | SHA-256 | render_us | shape_match_cells |
|---|---:|---:|---:|---|---:|---:|
| raw Sobel | 3 | 7200 | 20634 | `d8001a154c33c3826e3dac2eaf029fa8a1fffe76d0751e199f27e6b5bcbb9c60` | 214944 | 762 |
| ETF + CLD, 3 iters | 3 | 7200 | 20634 | `a523d64714e768282fe2f978484a824e23f2bbb11e29579bf47c2d0f6e30bb79` | 237155 | 771 |

Graph proof:

```text
sobel(cpu)  structure-luminance:LuminanceField -> raw-gradients:GradientField
etf(cpu)  raw-gradients:GradientField -> gradients:GradientField
edge-field(cpu)  gradients:GradientField -> edge-field:EdgeField
```
