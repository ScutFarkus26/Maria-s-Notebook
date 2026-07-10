# Documentation

Project documentation lives outside the synchronized Xcode source folders so it is not compiled or copied into the app bundle.

## Contents

- `Architecture/` - system design, data model, CloudKit, AI, and technical reference material.
- `ADRs/` - architecture decision records.
- `Implementation/` - active and completed implementation plans and handoffs.
- `Manuals/` - Markdown sources and PDF generation scripts for the developer and user manuals.
- `Generated/` - generated PDF manuals.

## Regenerating manuals

Run either generator from the repository root:

```bash
python3 Documentation/Manuals/generate_pdf.py
python3 Documentation/Manuals/generate_user_pdf.py
```

Each script reads its Markdown source from `Manuals/` and writes the PDF to `Generated/`.
