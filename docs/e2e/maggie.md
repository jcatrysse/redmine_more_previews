# maggie

Run 2026-10-12T08:04:55.579Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](maggie-settings.png) | admin | `/settings/plugin/redmine_more_previews` | Maggie turned on for .pdf (to png) and .png (to jpg), Peek off for .pdf |
| ![](maggie-manager-disguised-pdf.png) | manager | `/attachments/25` | manager: disguised.pdf gets no preview: PostScript disguised as a PDF never reaches ImageMagick |
| ![](maggie-manager-sample-pdf.png) | manager | `/attachments/8` | manager: sample.pdf still converted by Maggie |
| ![](maggie-manager-sample-png.png) | manager | `/attachments/9` | manager: sample.png still converted by Maggie |
| ![](maggie-manager-results.png) | manager | `/attachments/9` | manager: the disguised PDF returns no image, the real PDF a PNG, the PNG a JPEG |
| ![](maggie-reporter-disguised-pdf.png) | reporter | `/attachments/25` | reporter: disguised.pdf gets no preview: PostScript disguised as a PDF never reaches ImageMagick |
| ![](maggie-reporter-sample-pdf.png) | reporter | `/attachments/8` | reporter: sample.pdf still converted by Maggie |
| ![](maggie-reporter-sample-png.png) | reporter | `/attachments/9` | reporter: sample.png still converted by Maggie |
| ![](maggie-reporter-results.png) | reporter | `/attachments/9` | reporter: the disguised PDF returns no image, the real PDF a PNG, the PNG a JPEG |
| ![](maggie-outsider.png) | outsider | `/attachments/25` | outsider (non-member, public project): same result, no preview of the disguised PDF |
