# escan

Driverless scanning for eSCL / AirScan scanners on macOS. No vendor driver, no Image Capture, no vendor app. Just `curl` and the scanner's own HTTP+XML interface.

Tested on an EPSON L4260. The protocol is the same for any eSCL scanner.

```
scan doc            300 dpi document, PDF            (default)
scan color          300 dpi colour, PDF
scan hi             600 dpi colour, PDF
scan bw             300 dpi pure black and white
scan jpg            300 dpi, JPEG
scan preview        100 dpi JPEG of the whole glass   (~9 s)
scan area X Y L A   scan only that region             (units of 1/300 inch)
scan multi N        N sheets on the glass, merged into one PDF
scan discover       show what was found on the network
scan status         raw ScannerStatus XML
scan wake           Wake-on-LAN magic packet
scan fix            clear jobs stuck in the queue
scan list           resolutions / formats the scanner advertises
```

Flags apply to `doc color hi bw jpg area`:

```
--dpi 100|200|300|600|1200
--fmt pdf|jpg
--cor gray|rgb|bw
--no-open
```

## GUI

`Escanear.app` gives you the workflow the CLI cannot: fast preview, drag a box over the region you actually want, then scan only that region at high resolution.

1. Launch. A 100 dpi preview of the whole glass arrives by itself.
2. Drag over the preview. Everything outside the box dims. The panel reads out the real size in inches and the pixel count at the dpi you picked.
3. Pick dpi, colour mode and format.
4. ESCANEAR.

Geometry is exact. A box marked 5,40 x 7,20 inches at 600 dpi produces a 3238 x 4320 px image.

## Build

```
./build.sh
sudo cp -R Escanear.app /Applications/
```

Needs the Swift compiler that ships with macOS (`/usr/bin/swiftc`). No third-party dependency.

## Finding the scanner

Nothing about your network lives in this repo. Discovery order:

1. `ESCAN_HOST` in the environment, or in `~/.config/escan/escanrc`
2. cache in `~/.config/escan/host`
3. Bonjour: browse `_uscan._tcp`, then look up the instance

The Wake-on-LAN MAC is read from the tail of the UUID that the scanner's own `ScannerCapabilities` returns. The glass size is read from `MaxWidth` / `MaxHeight` in the same response. `scan discover` prints what it found, with the MAC masked.

`~/.config/escan/escanrc` is where your own values go, and it is not tracked by git:

```
ESCAN_HOST="192.168.1.50"
ESCAN_BROADCAST="192.168.1.255"
```

## What the scanner actually requires

Three things that cost hours to find out:

**Path casing.** `/eSCL/` works. `/escl/` returns HTTP 500 for every request.

**Namespace form.** The eSCL namespace must be written with slashes:

```
http://schemas.hp.com/imaging/escl/2011/05/03   -> HTTP 201  (aceito)
http://schemas.hp.com/imaging/escl/2011-05-03   -> HTTP 400  (rejeitado)
```

Confirmed by A/B test on the same body.

**Stuck jobs.** A scan abandoned halfway leaves the scanner in `pwg:State=Processing` permanently, and every later scan is refused. `DELETE /eSCL/ScanJobs/<uuid>` clears the queue entry, but the state only relaxes after the entry ages out. `scan fix` runs the DELETEs; if the scanner is still `Processing`, wait 20-30 s and try again. This is the reason a scanner that worked once appears broken forever.

Flow that works:

```
GET  /eSCL/ScannerCapabilities
POST /eSCL/ScanJobs          -> 201, Location: /eSCL/ScanJobs/<uuid>
GET  <job>/NextDocument      -> the page (404/410/503 while the lamp is still moving)
DELETE <job>
```

## Proxy note

`--noproxy '*'` is not optional. TUN-mode proxies (Clash, Surge) install routes that capture `192.168.x.x` and the connection to the scanner dies before it starts.

## Coordinate math, and the bug that broke it

The preview is 100 dpi, the scanner addresses the glass in units of 1/300 inch, so one preview pixel is 3 units.

`NSImage.size` returns **points**, not pixels: pixels multiplied by 72/dpi. A 100 dpi preview of 850 x 1170 px reports itself as 612 x 842 pt. Using that number as pixels makes every selection 1,394 times too small (100/72). The fix reads `NSBitmapImageRep.pixelsWide` / `pixelsHigh`.

`scanview.swift` holds all of it, with `setDrag(from:to:)` as the single entry point used by both the mouse handlers and the selftest.

```
./scanui --selftest some-preview.jpg
```

Five cases: whole glass, a 540 x 720 px box, a drag drawn backwards, a 1 inch square, and a drag started outside the image. Expect `SELFTEST: 5/5 ok`.

## Output

`~/Documents/Scans/` by default. Override with `ESCAN_OUT`.

## Multi-page merging

`scan multi N` needs `pdfmerge` (Swift + PDFKit, built by `build.sh`). Without it the pages stay as separate files.

## Requirements

macOS 12 or newer. `curl`, `nc`, `perl`, `dns-sd` (all part of the system).

## License

MIT.
