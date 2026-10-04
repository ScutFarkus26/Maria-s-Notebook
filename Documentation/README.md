# Documentation

Project documentation lives outside the synchronized Xcode source folders so it is not compiled or copied into the app bundle.

## Contents

Start at [INDEX.md](INDEX.md): every plan and progress file with its status, date and where it lives.

- `Architecture/` - system design, data model, CloudKit, AI, backup, albums, Siri, build settings, ownership conventions, and technical reference material (including the detailed feature notes that used to live in `Cosmic Daybook/CLAUDE.md`).
- `ADRs/` - architecture decision records.
- `Implementation/` - active implementation plans and handoffs; finished plans move to `Implementation/Archive/`. Each plan opens with a status line, and `INDEX.md` lists them all.
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
