#!/usr/bin/env python3
"""Generate a well-formatted A4 PDF from customer-overview.md."""

import pathlib
import markdown
import weasyprint

DOCS_DIR = pathlib.Path(__file__).resolve().parent
MD_FILE = DOCS_DIR / "customer-overview.md"
PDF_FILE = DOCS_DIR / "customer-overview.pdf"

CSS = """
@page {
    size: A4;
    margin: 22mm 20mm 25mm 20mm;

    @bottom-center {
        content: "Page " counter(page) " of " counter(pages);
        font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
        font-size: 8pt;
        color: #999;
    }
}

@page :first {
    @bottom-center { content: none; }
}

/* ── Base typography ── */

body {
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    font-size: 10.5pt;
    line-height: 1.55;
    color: #222;
    orphans: 3;
    widows: 3;
}

/* ── Cover / title block ── */

h1:first-of-type {
    font-size: 22pt;
    font-weight: 700;
    color: #111;
    border-bottom: 3px solid #cc0000;
    padding-bottom: 10px;
    margin-top: 60px;
    margin-bottom: 6px;
}

/* ── Headings ── */

h1 {
    font-size: 18pt;
    font-weight: 700;
    color: #111;
    border-bottom: 2px solid #cc0000;
    padding-bottom: 6px;
    margin-top: 32px;
    margin-bottom: 10px;
    page-break-after: avoid;
}

h2 {
    font-size: 14pt;
    font-weight: 600;
    color: #222;
    border-bottom: 1px solid #ddd;
    padding-bottom: 4px;
    margin-top: 24px;
    margin-bottom: 8px;
    page-break-after: avoid;
}

h3 {
    font-size: 12pt;
    font-weight: 600;
    color: #333;
    margin-top: 18px;
    margin-bottom: 6px;
    page-break-after: avoid;
}

h4 {
    font-size: 10.5pt;
    font-weight: 600;
    color: #444;
    margin-top: 14px;
    margin-bottom: 4px;
    page-break-after: avoid;
}

/* ── Paragraphs and lists ── */

p {
    margin: 6px 0;
}

ul, ol {
    margin: 6px 0 6px 18px;
    padding: 0;
}

li {
    margin-bottom: 3px;
}

/* ── Links ── */

a {
    color: #0056b3;
    text-decoration: none;
}

/* ── Tables ── */

table {
    border-collapse: collapse;
    width: 100%;
    margin: 12px 0;
    font-size: 9.5pt;
    line-height: 1.4;
    page-break-inside: auto;
}

thead {
    display: table-header-group;
}

tr {
    page-break-inside: avoid;
}

th {
    background-color: #2d2d2d;
    color: #fff;
    font-weight: 600;
    text-align: left;
    padding: 7px 10px;
    border: 1px solid #2d2d2d;
}

td {
    padding: 6px 10px;
    border: 1px solid #d0d0d0;
    vertical-align: top;
}

tr:nth-child(even) td {
    background-color: #f7f7f7;
}

tr:nth-child(odd) td {
    background-color: #fff;
}

/* ── Code ── */

code {
    font-family: "SF Mono", "Menlo", "Monaco", "Consolas", monospace;
    font-size: 9pt;
    background-color: #f0f0f0;
    padding: 1px 5px;
    border-radius: 3px;
    color: #c7254e;
}

pre {
    background-color: #1e1e1e;
    color: #d4d4d4;
    padding: 14px 16px;
    border-radius: 5px;
    font-size: 8.5pt;
    line-height: 1.45;
    overflow-x: auto;
    page-break-inside: avoid;
    margin: 10px 0;
}

pre code {
    background: none;
    padding: 0;
    border-radius: 0;
    color: inherit;
    font-size: inherit;
}

/* ── Blockquotes ── */

blockquote {
    border-left: 4px solid #cc0000;
    margin: 12px 0;
    padding: 8px 16px;
    color: #555;
    background-color: #fafafa;
}

/* ── Horizontal rules ── */

hr {
    border: none;
    border-top: 1px solid #ddd;
    margin: 24px 0;
}

/* ── Bold emphasis ── */

strong {
    color: #111;
    font-weight: 600;
}
"""


def main():
    md_text = MD_FILE.read_text()
    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "toc", "sane_lists"],
    )

    full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>{CSS}</style>
</head>
<body>
{html_body}
</body>
</html>"""

    doc = weasyprint.HTML(string=full_html, base_url=str(DOCS_DIR))
    doc.write_pdf(str(PDF_FILE))
    print(f"Generated {PDF_FILE}  ({PDF_FILE.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
