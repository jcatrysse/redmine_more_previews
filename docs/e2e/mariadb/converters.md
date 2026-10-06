# converters

Run 2026-10-06T20:15:38.799Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](converters-sample-docx.png) | manager | `/attachments/3` | Libre: docx converted to PDF by LibreOffice (headless Chromium shows no PDF viewer; the PDF itself is checked through its URL) |
| ![](converters-sample-odt.png) | manager | `/attachments/7` | Libre: odt converted to HTML by LibreOffice |
| ![](converters-sample-xlsx.png) | manager | `/attachments/15` | Libre: xlsx converted to HTML (the sheet as a table) |
| ![](converters-sample-csv.png) | manager | `/attachments/2` | Libre: csv rendered as a PNG image |
| ![](converters-sample-eml.png) | manager | `/attachments/4` | Cliff: mail headers in a box above the body, "Unsafe reload" link |
| ![](converters-sample-vcf.png) | manager | `/attachments/14` | Vince: business card from a vcf |
| ![](converters-sample-md.png) | manager | `/attachments/6` | Mark: markdown converted to HTML by pandoc |
| ![](converters-sample-textile.png) | manager | `/attachments/11` | Mark: textile rendered inline in the page (was HTTP 500 before this branch) |
| ![](converters-sample-html.png) | manager | `/attachments/5` | Pass: html shown as is, sandboxed |
| ![](converters-sample-txt.png) | manager | `/attachments/13` | Teddie: text file |
| ![](converters-sample-pdf.png) | manager | `/attachments/8` | Peek: the PDF itself (no viewer in headless Chromium; checked through its URL) |
| ![](converters-sample-png.png) | manager | `/attachments/9` | Maggie: png converted to jpg by ImageMagick |
| ![](converters-sample-zip.png) | manager | `/attachments/16` | Zippy: zip content table with folders |
| ![](converters-sample-tar.png) | manager | `/attachments/10` | Zippy: tar content table rendered inline |
| ![](converters-sample-tgz.png) | manager | `/attachments/12` | Zippy: tgz content table |
| ![](converters-navigation-next.png) | manager | `/attachments/7/sample.odt` | "Next »" leads from sample.md to the next attachment of the issue (sample.odt) |
| ![](converters-reload.png) | manager | `/attachments/7/sample.odt?reload=1` | The "Update" link (SVG reload icon) reconverts the file |
| ![](converters-issue-attachments.png) | manager | `/issues/7` | The issue with its sample attachments; the plugin adds file-type icons through a CSS hook |
