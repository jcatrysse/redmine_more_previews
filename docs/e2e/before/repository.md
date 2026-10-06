# repository

Run 2026-10-06T20:38:25.736Z against http://127.0.0.1:3000.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](repository-sample-md.png) | manager | `/projects/e2e-project/repository/samples/entry/sample.md` | Markdown file in the repository, converted by Mark |
| ![](repository-docs-sample-docx.png) | manager | `/projects/e2e-project/repository/samples/entry/docs/sample.docx` | docx in a folder of the repository, converted to PDF by LibreOffice (no PDF viewer in headless Chromium; checked through its URL) |
| ![](repository-sample-vcf.png) | manager | `/projects/e2e-project/repository/samples/entry/sample.vcf` | vcard in the repository |
| ![](repository-sample-txt.png) | manager | `/projects/e2e-project/repository/samples/entry/sample.txt` | Text file in the repository (Teddie) |
| ![](repository-sample-zip.png) | manager | `/projects/e2e-project/repository/samples/entry/sample.zip` | Zip in the repository: its files are listed (the preview was empty before this branch) |
| ![](repository-outsider-public.png) | outsider | `/projects/e2e-project/repository/samples/entry/sample.md` | Outsider on the public project (non-member role) can browse and preview the repository like core allows |

## Problems

- /projects/e2e-project/repository/samples/entry/sample.md as manager: JS e.indexOf is not a function
- /projects/e2e-project/repository/samples/entry/docs/sample.docx as manager: JS e.indexOf is not a function
- /projects/e2e-project/repository/samples/entry/sample.vcf as manager: JS e.indexOf is not a function
- /projects/e2e-project/repository/samples/entry/sample.vcf as manager: 404 stylesheet /stylesheets/tribute-3.7.3.css
- /projects/e2e-project/repository/samples/entry/sample.vcf as manager: 404 stylesheet /stylesheets/jquery/jquery-ui-1.11.0.css
- /projects/e2e-project/repository/samples/entry/sample.txt as manager: JS e.indexOf is not a function
- /projects/e2e-project/repository/samples/entry/sample.zip as manager: JS e.indexOf is not a function
- zip table empty
- /projects/e2e-project/repository/samples/entry/sample.md as outsider: JS e.indexOf is not a function
