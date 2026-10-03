# Using a Windows camera from strok in WSL 2

`strok --input cam` uses FFmpeg's Linux V4L2 input while it runs under WSL. A
Windows camera is not automatically available to the WSL virtual machine, so
there is no `/dev/video0` until the camera is passed through with
[`usbipd-win`](https://learn.microsoft.com/en-us/windows/wsl/connect-usb).

## Prerequisites

- WSL 2 with a current WSL kernel (`wsl --update` from Windows PowerShell).
- Windows 11 on x64 or ARM64. Current Store-based WSL also supports updated
  Windows 10 installations; see Microsoft's USB-device guidance for details.
- An integrated or external camera that appears in `usbipd list`. External UVC
  webcams are the most reliable choice.

Install the Windows USB/IP service once from PowerShell:

```powershell
winget install --interactive --exact dorssel.usbipd-win
```

## Attach the camera

1. Keep a WSL 2 terminal open.
2. Open **Windows PowerShell as Administrator** and find the camera's bus ID:

   ```powershell
   usbipd list
   ```

   Look for an entry such as `Integrated Camera`, `USB Video Device`, or the
   webcam's model name. Substitute its `BUSID` below.

3. Share it once (administrator PowerShell):

   ```powershell
   usbipd bind --busid <BUSID>
   ```

4. Attach it to the running WSL 2 VM (a normal PowerShell is sufficient):

   ```powershell
   usbipd attach --wsl --busid <BUSID>
   ```

5. Back in WSL, confirm that the Linux video device appeared:

   ```sh
   ls /dev/video*
   ```

   If `/dev/video0` is present, run strok:

   ```sh
   ./build/ci/strok --input v4l2:/dev/video0 \
     --profile structure --style hatch --fit --max-fps 15
   ```

   Use `q` to quit. For a one-shot diagnostic instead of reconnecting when the
   camera disappears, add `--no-reconnect`.

## Detach when finished

In Windows PowerShell:

```powershell
usbipd detach --busid <BUSID>
```

While a device is attached to WSL, Windows cannot use it. Screen recording is
unaffected, but the Windows Camera app and other Windows camera clients cannot
use that camera until it is detached.

## Troubleshooting

- **The camera is absent from `usbipd list`.** Its driver or firmware does not
  expose an attachable USB device. Use a USB UVC webcam, or run strok in a
  native Windows build when one is available.
- **`usbipd attach` succeeds but no `/dev/video*` appears.** The WSL kernel
  did not bind a compatible Linux camera driver. Update WSL with `wsl --update`,
  detach and reattach the device, then check again.
- **The camera reconnects forever.** WSL cannot currently open the selected
  V4L2 device. Stop strok with `q` or `Ctrl-C`, verify `/dev/video0`, and use
  `--no-reconnect` while diagnosing.

This guide applies only to the Linux CLI running in WSL. It does not grant a
WSL process direct access to Windows' DirectShow or Media Foundation camera
APIs.
