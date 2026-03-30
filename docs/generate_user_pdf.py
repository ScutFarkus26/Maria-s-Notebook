#!/usr/bin/env python3
"""Convert UserManual.md to a professionally formatted PDF with TOC."""

import re
import os
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.colors import HexColor, black, white, grey
from reportlab.lib.units import inch, cm
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle,
    Preformatted, KeepTogether, Flowable, NextPageTemplate, BaseDocTemplate,
    PageTemplate, Frame
)
from reportlab.platypus.tableofcontents import TableOfContents


# ── Color Palette (warm, teacher-friendly) ──
COVER_BG = HexColor("#2d3a4a")
ACCENT = HexColor("#e07a5f")       # Warm terracotta
ACCENT_LIGHT = HexColor("#fdf0ed")  # Light peach
CODE_BG = HexColor("#f7f5f2")       # Warm gray
BORDER_COLOR = HexColor("#d4cfc9")
HEADING_COLOR = HexColor("#2d3a4a")
SUBHEADING_COLOR = HexColor("#4a5568")
TEXT_COLOR = HexColor("#333333")
MUTED_COLOR = HexColor("#718096")
TABLE_HEADER = HexColor("#5b7a9d")  # Muted blue


# ── Custom Flowables ──
class HRule(Flowable):
    def __init__(self, width=None, thickness=0.5, color=BORDER_COLOR):
        Flowable.__init__(self)
        self._width = width
        self.thickness = thickness
        self.color = color

    def wrap(self, availWidth, availHeight):
        self._width = self._width or availWidth
        return (self._width, self.thickness + 4)

    def draw(self):
        self.canv.setStrokeColor(self.color)
        self.canv.setLineWidth(self.thickness)
        self.canv.line(0, 2, self._width, 2)


def make_code_block(text, styles):
    """Create code block(s) as tables with background. Splits if too tall."""
    MAX_LINES = 55
    all_lines = text.split('\n')
    chunks = []
    for i in range(0, len(all_lines), MAX_LINES):
        chunks.append('\n'.join(all_lines[i:i + MAX_LINES]))

    flowables = []
    code_style = ParagraphStyle(
        'CodeBlockText', parent=styles['Normal'],
        fontSize=7.5, leading=10, fontName='Courier',
        textColor=TEXT_COLOR, wordWrap='CJK',
        leftIndent=0, rightIndent=0,
    )
    for chunk in chunks:
        escaped = chunk.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
        escaped = escaped.replace(' ', '&nbsp;')
        escaped = escaped.replace('\n', '<br/>')
        para = Paragraph(escaped, code_style)
        t = Table([[para]], colWidths=[letter[0] - 2 * inch - 12])
        t.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, -1), CODE_BG),
            ('BOX', (0, 0), (-1, -1), 0.5, BORDER_COLOR),
            ('TOPPADDING', (0, 0), (-1, -1), 8),
            ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
            ('LEFTPADDING', (0, 0), (-1, -1), 8),
            ('RIGHTPADDING', (0, 0), (-1, -1), 8),
            ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ]))
        flowables.append(t)
    return flowables


# ── Styles ──
def build_styles():
    styles = getSampleStyleSheet()

    styles.add(ParagraphStyle(
        'Part', parent=styles['Heading1'],
        fontSize=22, leading=28, textColor=HEADING_COLOR,
        spaceBefore=30, spaceAfter=12, fontName='Helvetica-Bold',
        borderWidth=0, borderPadding=0, borderColor=None,
    ))
    styles.add(ParagraphStyle(
        'Section', parent=styles['Heading2'],
        fontSize=16, leading=20, textColor=SUBHEADING_COLOR,
        spaceBefore=20, spaceAfter=8, fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'SubSection', parent=styles['Heading3'],
        fontSize=13, leading=16, textColor=SUBHEADING_COLOR,
        spaceBefore=14, spaceAfter=6, fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'SubSubSection', parent=styles['Heading4'],
        fontSize=11, leading=14, textColor=SUBHEADING_COLOR,
        spaceBefore=10, spaceAfter=4, fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'BodyText2', parent=styles['Normal'],
        fontSize=10.5, leading=15, textColor=TEXT_COLOR,
        spaceAfter=6, alignment=TA_JUSTIFY, fontName='Helvetica'
    ))
    styles.add(ParagraphStyle(
        'BulletItem', parent=styles['Normal'],
        fontSize=10.5, leading=15, textColor=TEXT_COLOR,
        spaceAfter=3, leftIndent=20, bulletIndent=8,
        fontName='Helvetica'
    ))
    styles.add(ParagraphStyle(
        'TOCHeading', parent=styles['Heading1'],
        fontSize=20, leading=26, textColor=HEADING_COLOR,
        spaceBefore=0, spaceAfter=20, fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'toc1', parent=styles['Normal'],
        fontSize=12, leading=20, leftIndent=0,
        textColor=HEADING_COLOR, fontName='Helvetica-Bold'
    ))
    styles.add(ParagraphStyle(
        'toc2', parent=styles['Normal'],
        fontSize=10, leading=17, leftIndent=20,
        textColor=SUBHEADING_COLOR, fontName='Helvetica'
    ))
    styles.add(ParagraphStyle(
        'toc3', parent=styles['Normal'],
        fontSize=9, leading=14, leftIndent=40,
        textColor=MUTED_COLOR, fontName='Helvetica'
    ))
    return styles


# ── Page Templates ──
class ManualDocTemplate(BaseDocTemplate):
    def __init__(self, filename, **kwargs):
        self.toc_entries = []
        BaseDocTemplate.__init__(self, filename, **kwargs)

    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph):
            style = flowable.style.name
            text = flowable.getPlainText()
            if style == 'Part':
                self.toc_entries.append((1, text, self.page))
                self.notify('TOCEntry', (0, text, self.page))
            elif style == 'Section':
                self.toc_entries.append((2, text, self.page))
                self.notify('TOCEntry', (1, text, self.page))
            elif style == 'SubSection':
                self.toc_entries.append((3, text, self.page))
                self.notify('TOCEntry', (2, text, self.page))


def header_footer(canvas, doc):
    canvas.saveState()
    w, h = letter

    # Footer
    canvas.setFont('Helvetica', 8)
    canvas.setFillColor(MUTED_COLOR)
    canvas.drawString(inch, 0.5 * inch, "Maria's Notebook — User Guide for Teachers")
    canvas.drawRightString(w - inch, 0.5 * inch, f"Page {doc.page}")

    # Top accent line
    canvas.setStrokeColor(ACCENT)
    canvas.setLineWidth(1.5)
    canvas.line(inch, h - 0.6 * inch, w - inch, h - 0.6 * inch)

    canvas.restoreState()


def title_page(canvas, doc):
    canvas.saveState()
    w, h = letter

    # Background accent block
    canvas.setFillColor(COVER_BG)
    canvas.rect(0, h - 4.2 * inch, w, 4.2 * inch, fill=1, stroke=0)

    # Accent stripe
    canvas.setFillColor(ACCENT)
    canvas.rect(0, h - 4.2 * inch, w, 4, fill=1, stroke=0)

    # Title
    canvas.setFillColor(white)
    canvas.setFont('Helvetica-Bold', 38)
    canvas.drawString(inch, h - 1.6 * inch, "Maria's Notebook")

    canvas.setFont('Helvetica', 20)
    canvas.drawString(inch, h - 2.2 * inch, "User Guide for Teachers")

    # Accent line
    canvas.setStrokeColor(ACCENT)
    canvas.setLineWidth(3)
    canvas.line(inch, h - 2.6 * inch, 3.5 * inch, h - 2.6 * inch)

    # Tagline
    canvas.setFillColor(HexColor("#b0bec5"))
    canvas.setFont('Helvetica-Oblique', 13)
    canvas.drawString(inch, h - 3.1 * inch, "A complete guide to managing your")
    canvas.drawString(inch, h - 3.4 * inch, "Montessori classroom")

    # Version
    canvas.setFillColor(HexColor("#8899aa"))
    canvas.setFont('Helvetica', 11)
    canvas.drawString(inch, h - 3.9 * inch, "March 2026")

    # Below the dark block — feature highlights
    y = h - 5.2 * inch
    canvas.setFillColor(TEXT_COLOR)

    features = [
        "Students & Profiles",
        "Lesson Library & Presentations",
        "Work Tracking & Practice",
        "Observations & Notes",
        "Attendance & Scheduling",
        "Planning & Curriculum Progression",
        "AI-Powered Insights",
        "Backup & iCloud Sync",
    ]

    canvas.setFont('Helvetica-Bold', 12)
    canvas.drawString(inch, y, "What's Inside:")
    y -= 24

    canvas.setFont('Helvetica', 10.5)
    for feat in features:
        # Draw a small terracotta bullet
        canvas.setFillColor(ACCENT)
        canvas.circle(inch + 5, y + 3, 2.5, fill=1, stroke=0)
        canvas.setFillColor(TEXT_COLOR)
        canvas.drawString(inch + 16, y, feat)
        y -= 18

    # Footer
    canvas.setFont('Helvetica', 9)
    canvas.setFillColor(MUTED_COLOR)
    canvas.drawString(inch, 0.75 * inch, "iOS & macOS")
    canvas.drawRightString(w - inch, 0.75 * inch, "mariasnotebook.app")

    canvas.restoreState()


# ── Markdown Parser ──
def inline_format(text):
    # Bold + italic
    text = re.sub(r'\*\*\*(.+?)\*\*\*', r'<b><i>\1</i></b>', text)
    # Bold
    text = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', text)
    # Italic
    text = re.sub(r'\*(.+?)\*', r'<i>\1</i>', text)
    # Inline code — styled as bold with warm highlight for user manual
    text = re.sub(r'`([^`]+)`', r'<font face="Helvetica-Bold" size="10" color="#c0392b">\1</font>', text)
    # Escape ampersands
    text = text.replace('&', '&amp;')
    text = text.replace('&amp;amp;', '&amp;')
    text = text.replace('&amp;lt;', '&lt;')
    text = text.replace('&amp;gt;', '&gt;')
    return text


def parse_table(lines):
    rows = []
    for line in lines:
        line = line.strip()
        if line.startswith('|') and line.endswith('|'):
            cells = [c.strip() for c in line.split('|')[1:-1]]
            if all(re.match(r'^[-:]+$', c) for c in cells):
                continue
            rows.append(cells)
    return rows


def md_to_flowables(md_text, styles):
    story = []
    lines = md_text.split('\n')
    i = 0

    while i < len(lines):
        line = lines[i]

        # Skip the very first title and metadata block
        if i == 0 and line.startswith('# Maria'):
            while i < len(lines):
                if lines[i].startswith('# ') and not lines[i].startswith('# Maria'):
                    break
                if lines[i].strip() == '---' and i > 2:
                    i += 1
                    # Find the next # heading
                    while i < len(lines) and not lines[i].startswith('# '):
                        i += 1
                    break
                i += 1
            continue

        # Horizontal rule
        if line.strip() == '---':
            story.append(Spacer(1, 6))
            story.append(HRule())
            story.append(Spacer(1, 6))
            i += 1
            continue

        # Code blocks
        if line.strip().startswith('```'):
            code_lines = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith('```'):
                code_lines.append(lines[i])
                i += 1
            i += 1
            code_text = '\n'.join(code_lines)
            if code_text.strip():
                story.append(Spacer(1, 4))
                for cb in make_code_block(code_text, styles):
                    story.append(cb)
                story.append(Spacer(1, 4))
            continue

        # Tables
        if '|' in line and i + 1 < len(lines) and '---' in lines[i + 1]:
            table_lines = []
            while i < len(lines) and '|' in lines[i]:
                table_lines.append(lines[i])
                i += 1
            rows = parse_table(table_lines)
            if rows:
                formatted_rows = []
                for ri, row in enumerate(rows):
                    formatted_cells = []
                    for cell in row:
                        cell_text = inline_format(cell)
                        if ri == 0:
                            formatted_cells.append(Paragraph(
                                cell_text,
                                ParagraphStyle('TH', parent=styles['Normal'],
                                    fontSize=9.5, leading=13, fontName='Helvetica-Bold',
                                    textColor=white)
                            ))
                        else:
                            formatted_cells.append(Paragraph(
                                cell_text,
                                ParagraphStyle('TD', parent=styles['Normal'],
                                    fontSize=9.5, leading=13, fontName='Helvetica')
                            ))
                    formatted_rows.append(formatted_cells)

                if formatted_rows:
                    ncols = len(formatted_rows[0])
                    col_width = (letter[0] - 2 * inch) / ncols
                    col_widths = [col_width] * ncols

                    t = Table(formatted_rows, colWidths=col_widths, repeatRows=1)
                    t.setStyle(TableStyle([
                        ('BACKGROUND', (0, 0), (-1, 0), TABLE_HEADER),
                        ('TEXTCOLOR', (0, 0), (-1, 0), white),
                        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
                        ('FONTSIZE', (0, 0), (-1, 0), 9.5),
                        ('BOTTOMPADDING', (0, 0), (-1, 0), 8),
                        ('TOPPADDING', (0, 0), (-1, 0), 8),
                        ('BACKGROUND', (0, 1), (-1, -1), white),
                        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [white, ACCENT_LIGHT]),
                        ('FONTSIZE', (0, 1), (-1, -1), 9.5),
                        ('TOPPADDING', (0, 1), (-1, -1), 6),
                        ('BOTTOMPADDING', (0, 1), (-1, -1), 6),
                        ('LEFTPADDING', (0, 0), (-1, -1), 6),
                        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
                        ('GRID', (0, 0), (-1, -1), 0.5, BORDER_COLOR),
                        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                    ]))
                    story.append(Spacer(1, 6))
                    story.append(t)
                    story.append(Spacer(1, 6))
            continue

        # Headings
        if line.startswith('# '):
            text = line[2:].strip()
            if story:
                story.append(PageBreak())
            story.append(Paragraph(inline_format(text), styles['Part']))
            story.append(HRule(thickness=1.5, color=ACCENT))
            story.append(Spacer(1, 8))
            i += 1
            continue

        if line.startswith('## '):
            text = line[3:].strip()
            story.append(Spacer(1, 4))
            story.append(Paragraph(inline_format(text), styles['Section']))
            i += 1
            continue

        if line.startswith('### '):
            text = line[4:].strip()
            story.append(Paragraph(inline_format(text), styles['SubSection']))
            i += 1
            continue

        if line.startswith('#### '):
            text = line[5:].strip()
            story.append(Paragraph(inline_format(text), styles['SubSubSection']))
            i += 1
            continue

        # Bullet lists
        if re.match(r'^[-*] ', line.strip()):
            text = re.sub(r'^[-*] ', '', line.strip())
            story.append(Paragraph(
                f'<bullet>&bull;</bullet> {inline_format(text)}',
                styles['BulletItem']
            ))
            i += 1
            continue

        # Numbered lists
        m = re.match(r'^(\d+)\. (.+)', line.strip())
        if m:
            num, text = m.group(1), m.group(2)
            story.append(Paragraph(
                f'<bullet>{num}.</bullet> {inline_format(text)}',
                styles['BulletItem']
            ))
            i += 1
            continue

        # Empty lines
        if not line.strip():
            i += 1
            continue

        # Regular paragraph
        para_lines = []
        while i < len(lines):
            l = lines[i]
            if not l.strip():
                break
            if l.startswith('#') or l.startswith('```') or l.startswith('---'):
                break
            if re.match(r'^[-*] ', l.strip()) or re.match(r'^\d+\. ', l.strip()):
                break
            if '|' in l and i + 1 < len(lines) and '---' in lines[min(i+1, len(lines)-1)]:
                break
            para_lines.append(l.strip())
            i += 1

        if para_lines:
            text = ' '.join(para_lines)
            story.append(Paragraph(inline_format(text), styles['BodyText2']))
            continue

        i += 1

    return story


def build_pdf():
    md_path = os.path.join(os.path.dirname(__file__), 'UserManual.md')
    pdf_path = os.path.join(os.path.dirname(__file__), 'UserManual.pdf')

    with open(md_path, 'r') as f:
        md_text = f.read()

    styles = build_styles()

    frame = Frame(inch, 0.8 * inch, letter[0] - 2 * inch, letter[1] - 1.6 * inch, id='main')

    doc = ManualDocTemplate(
        pdf_path,
        pagesize=letter,
        title="Maria's Notebook — User Guide for Teachers",
        author="Danny DeBerry",
        subject="User Guide",
    )

    cover_template = PageTemplate(id='Cover', frames=[frame], onPage=title_page)
    content_template = PageTemplate(id='Content', frames=[frame], onPage=header_footer)
    doc.addPageTemplates([cover_template, content_template])

    story = []

    # Cover page
    story.append(NextPageTemplate('Content'))
    story.append(PageBreak())

    # Table of Contents
    story.append(Paragraph("Table of Contents", styles['TOCHeading']))
    toc = TableOfContents()
    toc.levelStyles = [styles['toc1'], styles['toc2'], styles['toc3']]
    story.append(toc)
    story.append(PageBreak())

    # Content
    content = md_to_flowables(md_text, styles)
    story.extend(content)

    # Build (two passes for TOC)
    doc.multiBuild(story)
    print(f"PDF generated: {pdf_path}")


if __name__ == '__main__':
    build_pdf()
