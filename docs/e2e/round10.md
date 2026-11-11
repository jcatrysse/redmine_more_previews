# round10

Run 2026-11-11T11:24:16.836Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](round10-round10-jp.png) | manager | `/attachments/49` | Cliff: round10-jp.eml shows "日本語の本文です" (was mojibake: the charset of the part was not converted) |
| ![](round10-round10-w1252.png) | manager | `/attachments/50` | Cliff: round10-w1252.eml shows "café naïve € 5" (was mojibake: the charset of the part was not converted) |
| ![](round10-inline-deep.png) | manager | `/attachments/51` | Inline textile with 500 nested <div>: the page stays (Redmine 7 sanitizes with HTML4: libxml2 drops what lies deeper than 256 levels, no error; under the HTML5 vendor the "too complex" notice) |
| ![](round10-frame-0-text.png) | manager | `/attachments/53` | <object>: round10-long.txt in a pane of the window's height minus 320px, scrolled inside its frame with the wheel |
| ![](round10-frame-0-pdf.png) | manager | `/attachments/56` | <object>: round10 Offerte.docx in a pane of the window's height minus 320px (the frame, outlined in red, fills it: with <iframe> it was a 16px strip; headless Chromium shows no PDF) |
| ![](round10-frame-1-text.png) | manager | `/attachments/53` | <iframe>: round10-long.txt in a pane of the window's height minus 320px, scrolled inside its frame with the wheel |
| ![](round10-frame-1-pdf.png) | manager | `/attachments/56` | <iframe>: round10 Offerte.docx in a pane of the window's height minus 320px (the frame, outlined in red, fills it: with <iframe> it was a 16px strip; headless Chromium shows no PDF) |
| ![](round10-image-failed.png) | manager | `/attachments/54` | Maggie: a PNG of 20000x1 pixels, beyond ImageMagick's 16,000: the message replaces the broken image |
| ![](round10-zip-index.png) | manager | `/attachments/55` | Zippy: an archive with an entry index.html and a folder 日本 (UTF-8 listing); index.html is served as a download |
| ![](round10-zip-private.png) | manager | `/attachments/64` | Zippy in e2e-private: clicking index.html in the sandboxed frame downloads the entry (target _top, the page stays) |
| ![](round10-round10-private-docx.png) | manager | `/attachments/62` | Libre docx as HTML in e2e-private: the image is embedded as a data: URI and shown (it was not loaded in the frame before) |
| ![](round10-round10-private-eml.png) | manager | `/attachments/63` | Cliff email with an inline image in e2e-private: the image is embedded as a data: URI and shown (it was not loaded in the frame before) |
| ![](round10-maggie-settings.png) | admin | `/settings/plugin/redmine_more_previews` | Maggie settings: the HEIC/TIFF size limit (64 megapixels), and a check for the HEIC and TIFF coders of the ImageMagick Redmine runs |
| ![](round10-round10-plain-heic.png) | manager | `/attachments/57` | Maggie: round10-plain.heic previewed as jpg once enabled (first image, rotated as the file says) |
| ![](round10-round10-plain-heif.png) | manager | `/attachments/58` | Maggie: round10-plain.heif previewed as jpg once enabled (first image, rotated as the file says) |
| ![](round10-round10-rotated-tif.png) | manager | `/attachments/59` | Maggie: round10-rotated.tif previewed as jpg once enabled (first image, rotated as the file says) |
| ![](round10-heic-huge.png) | manager | `/attachments/60` | Maggie: a HEIC declaring 100000x100000 is refused with 413 before ImageMagick; the page shows the message |
| ![](round10-outsider.png) | outsider | `/attachments/62` | outsider (no membership): the private docx is refused (403) |
| ![](round10-reporter.png) | reporter | `/attachments/49` | reporter (core Reporter role, no plugin permissions; the view permission is public): the ISO-2022-JP email is shown |
| ![](round10-results.png) | reporter | `/attachments/49` | Round 10 results |
