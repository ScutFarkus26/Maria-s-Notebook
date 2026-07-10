# Documentation

Project documentation lives outside the synchronized Xcode source folders so it is not compiled or copied into the app bundle.

## Contents

- `Architecture/` - system design, data model, CloudKit, AI, backup, ownership conventions, and technical reference material.
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

## Checking repository structure

Run the lightweight structure check from the repository root after moving files or changing folders:

```bash
Scripts/check_repository_structure.sh
```

It checks that the completed organization remains intact without compiling the app.
