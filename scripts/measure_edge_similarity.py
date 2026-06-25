#!/usr/bin/env python3
import argparse
import math
import struct
import zlib


def paeth(a, b, c):
  p = a + b - c
  pa = abs(p - a)
  pb = abs(p - b)
  pc = abs(p - c)
  if pa <= pb and pa <= pc:
    return a
  if pb <= pc:
    return b
  return c


def read_png_gray(path):
  with open(path, "rb") as handle:
    data = handle.read()
  if data[:8] != b"\x89PNG\r\n\x1a\n":
    raise ValueError(f"not a PNG: {path}")
  offset = 8
  width = height = bit_depth = color_type = None
  idat = bytearray()
  while offset < len(data):
    size = struct.unpack(">I", data[offset:offset + 4])[0]
    kind = data[offset + 4:offset + 8]
    payload = data[offset + 8:offset + 8 + size]
    offset += 12 + size
    if kind == b"IHDR":
      width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", payload)
      if bit_depth != 8 or interlace != 0:
        raise ValueError(f"unsupported PNG encoding: {path}")
    elif kind == b"IDAT":
      idat.extend(payload)
    elif kind == b"IEND":
      break
  channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
  if channels is None:
    raise ValueError(f"unsupported PNG color type {color_type}: {path}")
  raw = zlib.decompress(bytes(idat))
  stride = width * channels
  rows = []
  previous = [0] * stride
  index = 0
  for _ in range(height):
    filter_type = raw[index]
    index += 1
    row = list(raw[index:index + stride])
    index += stride
    for i, value in enumerate(row):
      left = row[i - channels] if i >= channels else 0
      up = previous[i]
      up_left = previous[i - channels] if i >= channels else 0
      if filter_type == 1:
        row[i] = (value + left) & 255
      elif filter_type == 2:
        row[i] = (value + up) & 255
      elif filter_type == 3:
        row[i] = (value + ((left + up) // 2)) & 255
      elif filter_type == 4:
        row[i] = (value + paeth(left, up, up_left)) & 255
      elif filter_type != 0:
        raise ValueError(f"unsupported PNG filter {filter_type}: {path}")
    rows.append(row)
    previous = row
  gray = [0.0] * (width * height)
  out = 0
  for row in rows:
    for x in range(width):
      base = x * channels
      if color_type in (0, 4):
        gray[out] = row[base] / 255.0
      else:
        gray[out] = (0.2126 * row[base] + 0.7152 * row[base + 1] + 0.0722 * row[base + 2]) / 255.0
      out += 1
  return width, height, gray


def resize_bilinear(width, height, pixels, out_width, out_height):
  if width == out_width and height == out_height:
    return pixels
  output = [0.0] * (out_width * out_height)
  for y in range(out_height):
    src_y = 0.0 if out_height == 1 else y * (height - 1) / (out_height - 1)
    y0 = int(src_y)
    y1 = min(y0 + 1, height - 1)
    fy = src_y - y0
    for x in range(out_width):
      src_x = 0.0 if out_width == 1 else x * (width - 1) / (out_width - 1)
      x0 = int(src_x)
      x1 = min(x0 + 1, width - 1)
      fx = src_x - x0
      top = pixels[y0 * width + x0] * (1.0 - fx) + pixels[y0 * width + x1] * fx
      bottom = pixels[y1 * width + x0] * (1.0 - fx) + pixels[y1 * width + x1] * fx
      output[y * out_width + x] = top * (1.0 - fy) + bottom * fy
  return output


def sobel(width, height, pixels):
  edges = [0.0] * (width * height)
  peak = 0.0
  for y in range(height):
    ym = max(0, y - 1)
    yp = min(height - 1, y + 1)
    for x in range(width):
      xm = max(0, x - 1)
      xp = min(width - 1, x + 1)
      gx = (
        pixels[ym * width + xp] + 2.0 * pixels[y * width + xp] + pixels[yp * width + xp]
        - pixels[ym * width + xm] - 2.0 * pixels[y * width + xm] - pixels[yp * width + xm]
      )
      gy = (
        pixels[yp * width + xm] + 2.0 * pixels[yp * width + x] + pixels[yp * width + xp]
        - pixels[ym * width + xm] - 2.0 * pixels[ym * width + x] - pixels[ym * width + xp]
      )
      value = math.hypot(gx, gy)
      edges[y * width + x] = value
      peak = max(peak, value)
  if peak > 0.0:
    inv = 1.0 / peak
    edges = [value * inv for value in edges]
  return edges


def mse(lhs, rhs):
  return sum((a - b) * (a - b) for a, b in zip(lhs, rhs)) / len(lhs)


def ncc(lhs, rhs):
  mean_l = sum(lhs) / len(lhs)
  mean_r = sum(rhs) / len(rhs)
  num = den_l = den_r = 0.0
  for a, b in zip(lhs, rhs):
    da = a - mean_l
    db = b - mean_r
    num += da * db
    den_l += da * da
    den_r += db * db
  den = math.sqrt(den_l * den_r)
  return num / den if den else 0.0


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("reference")
  parser.add_argument("candidate")
  args = parser.parse_args()
  ref_w, ref_h, ref = read_png_gray(args.reference)
  cand_w, cand_h, cand = read_png_gray(args.candidate)
  ref = resize_bilinear(ref_w, ref_h, ref, cand_w, cand_h)
  ref_edges = sobel(cand_w, cand_h, ref)
  cand_edges = sobel(cand_w, cand_h, cand)
  print(f"width={cand_w}")
  print(f"height={cand_h}")
  print(f"edge_ncc={ncc(ref_edges, cand_edges):.6f}")
  print(f"edge_mse={mse(ref_edges, cand_edges):.6f}")
  print(f"luma_mse={mse(ref, cand):.6f}")
  print(f"edge_energy={sum(cand_edges) / len(cand_edges):.6f}")


if __name__ == "__main__":
  main()
