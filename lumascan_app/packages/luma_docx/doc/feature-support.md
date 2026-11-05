# luma_docx: Word feature support

Checked against `test/fixtures/Word_Feature_Test.docx` (the Word feature test
file: 139 features, 125 with a sample). `test/reader_test.dart` checks
what the reader takes out of the file for every feature with a sample, and
`test/render_test.dart` lays out every page in both views. The rendering was also
checked by eye from the screenshots that `test/preview` writes.

| Result | Features |
|---|---|
| Supported | 111 |
| Partial | 13 |
| Not supported | 1 |
| No sample in the file (needs Word, another program or an add-in) | 7 |
| Not in file (Word app feature, nothing saved) | 7 |

Of the 125 features with a sample, 111 are supported, 13 are partial and
1 is not supported.

**Biggest gap:** the viewer starts a new page only at page and section breaks
(Word also breaks when a page is full). Page numbers, repeated header rows and
the keep-with-next options depend on that, so they are marked partial.

What the "No sample" rows would show if a file had them: SmartArt shows a
labelled placeholder box of the right size; embedded objects and signature lines
show their PNG or JPEG preview picture, or a placeholder when the preview is
EMF/WMF; macros are never run.

## Every feature

| # | Where in Word | Feature | Result | Notes |
|---|---|---|---|---|
| 1 | Home > Font | Font family (serif, sans serif, monospace, script) | Supported |  |
| 2 | Home > Font | Theme fonts (+Headings and +Body) | Supported |  |
| 3 | Home > Font | Font size (8 to 36 pt) | Supported |  |
| 4 | Home > Font | Bold, italic, bold italic | Supported |  |
| 5 | Home > Font | Underline styles (single, double, thick, words only, dotted, dash, wave, coloured) | Supported |  |
| 6 | Home > Font | Strikethrough and double strikethrough | Supported |  |
| 7 | Home > Font | Superscript and subscript | Supported |  |
| 8 | Home > Font | Small caps and all caps | Supported |  |
| 9 | Home > Font | Font colour: standard and custom RGB | Supported |  |
| 10 | Home > Font | Font colour: theme colours with tints and shades | Supported |  |
| 11 | Home > Font | Text highlight colours (all 15) | Supported |  |
| 12 | Home > Font | Character shading and character border | Supported |  |
| 13 | Home > Font | Text effects: outline, shadow, glow, reflection, gradient fill | Partial | Outline, shadow, glow and gradient fill are drawn. Reflection is read but not drawn. |
| 14 | Home > Font | Legacy outline and shadow, emboss and engrave | Supported |  |
| 15 | Home > Font | Character spacing (expanded, condensed), scale, raised and lowered position | Supported |  |
| 16 | Home > Font | OpenType ligatures and number forms | Partial | Ligatures and number forms are passed to the font; the effect depends on the font on the phone. |
| 17 | Home > Font | Hidden text | Supported | Hidden by default, shown with "Show hidden text" (dotted underline). |
| 18 | Home > Font | Change case (Aa) | Supported |  |
| 19 | Home > Font | Clear formatting | Not in file | Word app feature; nothing is saved in a .docx to read. |
| 20 | Home > Paragraph | Align left, center, right, justify, distributed | Partial | Distributed is shown as justify (the last line is not spread). |
| 21 | Home > Paragraph | Left, right, first-line, hanging and negative indent | Partial | All indents are read. A hanging indent on a plain paragraph (no list) wraps from the left indent; on lists it is exact. |
| 22 | Home > Paragraph | Line spacing (single, 1.5, double, exactly, at least) | Supported |  |
| 23 | Home > Paragraph | Space before and after | Supported |  |
| 24 | Home > Paragraph | Paragraph borders (box, left bar, rule, dashed, double, 3-D) | Supported |  |
| 25 | Home > Paragraph | Paragraph shading (solid and pattern) | Supported |  |
| 26 | Home > Paragraph | Tab stops: left, center, right, decimal, bar | Partial | Left, center, right and bar tabs are exact. Decimal tabs are lined up like right tabs (on the end of the number, not the decimal point). |
| 27 | Home > Paragraph | Tab leaders: dots, hyphens, underline; positional tab | Supported |  |
| 28 | Home > Paragraph | Bulleted lists: multi-level, custom symbol, Wingdings, picture bullet | Supported | Symbol bullets (Wingdings, Symbol) are mapped to Unicode; picture bullets are drawn. |
| 29 | Home > Paragraph | Numbered lists: 1, a, i, I, A, (1), 1st | Supported |  |
| 30 | Home > Paragraph | Multilevel outline list (1.1.1) | Supported |  |
| 31 | Home > Paragraph | Restart numbering | Supported |  |
| 32 | Home > Paragraph | Manual line break (Shift+Enter) | Supported |  |
| 33 | Home > Paragraph | Right-to-left paragraphs (Arabic, Hebrew) | Supported | Right-to-left paragraphs and runs. |
| 34 | Home > Paragraph | Sort | Not in file | Word app feature; nothing is saved in a .docx to read. |
| 35 | Home > Paragraph | Show/hide formatting marks | Not in file | Word app feature; nothing is saved in a .docx to read. |
| 36 | Home > Styles | Title and Subtitle styles | Supported |  |
| 37 | Home > Styles | Heading 1 to Heading 4 | Supported |  |
| 38 | Home > Styles | Quote, Intense Quote, Caption, No Spacing styles | Supported |  |
| 39 | Home > Styles | Strong and Emphasis character styles | Supported |  |
| 40 | Home > Styles | Custom paragraph styles | Supported |  |
| 41 | Home > Styles | Custom character style | Supported |  |
| 42 | Home > Editing | Find, Replace, Select | Not in file | Word app feature; nothing is saved in a .docx to read. |
| 43 | Insert > Pages | Cover page | Supported |  |
| 44 | Insert > Pages | Page break | Supported |  |
| 45 | Insert > Tables | Table with header row and banded rows | Supported |  |
| 46 | Insert > Tables | Merged cells (horizontal and vertical) | Supported |  |
| 47 | Insert > Tables | Cell vertical alignment and rotated text direction | Supported |  |
| 48 | Insert > Tables | Cell borders (double, dotted, dashed, wave, thick-thin, none, diagonal) | Supported |  |
| 49 | Insert > Tables | Cell pattern shading | Supported |  |
| 50 | Insert > Tables | Nested table; list and picture inside a cell | Supported |  |
| 51 | Insert > Tables | Centered table, fixed column widths, cell margins | Supported |  |
| 52 | Insert > Tables | Floating table with text wrapping | Partial | The table is read with its position, but shown as a normal table (text does not wrap around it). |
| 53 | Insert > Tables | Table formula (=SUM(ABOVE)) | Supported | Shows the result Word saved (no recalculation). |
| 54 | Insert > Tables | Header row repeats on each page; rows do not split | Partial | "Rows do not split" is read. The viewer starts a new page only at page and section breaks, so a header row is never repeated. |
| 55 | Table Design | Table style with header row, total row, first column and banded rows | Supported |  |
| 56 | Table Layout | Spacing between cells | Supported |  |
| 57 | Insert > Illustrations | Pictures: PNG and JPEG, inline | Supported |  |
| 58 | Insert > Illustrations | Alt text on pictures | Supported | Used as the screen reader label and shown if the picture cannot be drawn. |
| 59 | Insert > Illustrations | Text wrapping: square, tight, top and bottom, behind text, in front of text | Supported | Square, tight and through wrap text beside the picture; top and bottom puts it on its own line; behind and in front of text are drawn over the paragraph without moving the text. |
| 60 | Picture Format | Rotate and flip | Supported |  |
| 61 | Picture Format | Crop, crop to shape, border with shadow, grayscale, transparency | Supported |  |
| 62 | Insert > Illustrations | Icons (SVG with PNG fallback) | Partial | The PNG fallback is shown; the SVG itself is not drawn. |
| 63 | Insert > Illustrations | Shapes: rectangle, rounded, ellipse, triangle, diamond, arrow, star, callout, heart, hexagon, line | Supported |  |
| 64 | Shape Format | Shape gradient fill, shadow, rotation, dashed outline | Supported |  |
| 65 | Insert > Illustrations | Charts: native column chart and pie chart | Supported |  |
| 66 | Insert > Illustrations | SmartArt | No sample | Needs word's diagram engine to create. |
| 67 | Insert > Illustrations | 3D models | No sample | Needs a 3d model file. |
| 68 | Insert > Media | Online video | No sample | Needs a live web embed. |
| 69 | Insert > Links | External, email and phone hyperlinks | Supported |  |
| 70 | Insert > Links | Hyperlink ScreenTip | Supported |  |
| 71 | Insert > Links | Bookmarks | Supported |  |
| 72 | Insert > Links | Internal links to a bookmark and to a heading | Supported |  |
| 73 | Insert > Links | Cross-references (caption text, page number, bookmark text) | Supported | Shows the saved text; tapping jumps to the target. |
| 74 | Insert > Comments | Comments from several reviewers | Supported |  |
| 75 | Insert > Comments | Comment reply (thread) and resolved comment | Supported |  |
| 76 | Insert > Header & Footer | Header and footer | Supported |  |
| 77 | Insert > Header & Footer | Different first page | Supported |  |
| 78 | Insert > Header & Footer | Different odd and even pages | Supported |  |
| 79 | Insert > Header & Footer | Section with its own header (not linked to previous) | Supported |  |
| 80 | Insert > Header & Footer | Page X of Y | Partial | Page X of Y is filled in by the viewer. Numbers can differ from Word because pages are split only at page and section breaks. |
| 81 | Insert > Header & Footer | Page number format and restart (i, ii, iii then 1, 2, 3) | Supported |  |
| 82 | Insert > Text | Text box, including vertical text | Supported |  |
| 83 | Insert > Text | WordArt | Partial | WordArt text, fill and outline are shown. The text curve (warp) is not applied. |
| 84 | Insert > Text | Drop cap (dropped and in margin) | Supported |  |
| 85 | Insert > Text | Quick Parts: document property fields | Supported |  |
| 86 | Insert > Text | Date and time fields | Supported | Shows the value Word saved. |
| 87 | Insert > Text | Signature line | No sample | Needs a signature provider. |
| 88 | Insert > Text | Embedded object (Excel sheet, PDF) | No sample | Ole objects need the source program. |
| 89 | Insert > Symbols | Equations: fraction, root, sum, integral, matrix, limit, accent, inline | Supported |  |
| 90 | Insert > Symbols | Symbols and special characters | Supported |  |
| 91 | Design | Theme: theme colours and theme fonts (Office theme) | Supported |  |
| 92 | Design | Page colour | Supported |  |
| 93 | Design | Watermark | Supported | Taken from the header and drawn behind every page that uses that header. |
| 94 | Design | Page borders | Supported |  |
| 95 | Layout > Page Setup | Margins and gutter | Supported |  |
| 96 | Layout > Page Setup | Portrait and landscape in one file | Supported |  |
| 97 | Layout > Page Setup | Paper size (A4) | Supported |  |
| 98 | Layout > Page Setup | Columns: two with a line between, three of unequal width | Supported |  |
| 99 | Layout > Breaks | Column break and text wrapping break | Supported |  |
| 100 | Layout > Breaks | Section breaks: next page, continuous, odd page | Supported |  |
| 101 | Layout > Page Setup | Line numbers | Partial | Line numbering is read and shown as a margin hint, not as a number on every line. |
| 102 | Layout > Page Setup | Vertical page alignment | Supported |  |
| 103 | Layout > Page Setup | Automatic hyphenation | Not supported | No hyphenation; long words wrap whole. |
| 104 | Layout > Paragraph | Widow/orphan control, keep with next, keep lines together, page break before | Partial | Page break before is applied. Widow/orphan control, keep with next and keep lines together are read but have no effect, because pages are split only at breaks. |
| 105 | Layout > Arrange | Position, wrap text, bring forward, send backward, rotate | Partial | Pictures are placed left, right, centered or at their offset. Exact page positions and stacking order are approximate. |
| 106 | References | Table of contents | Supported | Shows the saved contents with dot leaders; entries are links to the headings. |
| 107 | References | Footnotes | Supported |  |
| 108 | References | Endnotes | Supported |  |
| 109 | References | Captions with SEQ numbering (Figure, Table) | Supported |  |
| 110 | References | Table of figures | Supported |  |
| 111 | References | Citations and bibliography from a source list | Supported |  |
| 112 | References | Mark entry and index | Supported |  |
| 113 | References | Mark citation and table of authorities | Supported |  |
| 114 | Mailings | Merge fields, address block, greeting line, IF rule | Supported | Shows the saved merge field text, address block, greeting line and IF result. |
| 115 | Mailings | Envelopes, labels, finish and merge | Not in file | Word app feature; nothing is saved in a .docx to read. |
| 116 | Review | Tracked insertions and deletions | Supported |  |
| 117 | Review | Tracked formatting change and paragraph change | Supported |  |
| 118 | Review | Tracked inserted paragraph and moved text | Supported |  |
| 119 | Review | Tracked inserted and deleted table rows | Supported |  |
| 120 | Review | Several reviewers with their own colours | Supported |  |
| 121 | Review | Spelling and grammar, word count, translate, read aloud | Not in file | Word app feature; nothing is saved in a .docx to read. |
| 122 | Review | Restrict editing / protect document | No sample | It would lock this test file. |
| 123 | View | Navigation pane (built from headings) | Supported |  |
| 124 | View | Read mode, print layout, web layout, focus, zoom | Not in file | Word app feature; nothing is saved in a .docx to read. |
| 125 | File > Info | Document properties: title, subject, author, keywords, category, description | Supported |  |
| 126 | File | Macros (VBA) | No sample | Needs a .docm file. |
| 127 | Developer > Controls | Rich text and plain text content controls | Supported |  |
| 128 | Developer > Controls | Drop-down list and combo box content controls | Supported |  |
| 129 | Developer > Controls | Date picker content control | Supported |  |
| 130 | Developer > Controls | Check box content control | Supported |  |
| 131 | Developer > Controls | Picture content control | Supported | The picture inside the control is shown. |
| 132 | Developer > Controls | Repeating section and building block gallery content controls | Supported | The content of each repeated item and the building block is shown. |
| 133 | Developer > Controls | Legacy form fields: text, check box, drop-down | Supported |  |
| 134 | Fields | PAGE, NUMPAGES, SECTION, DATE, TIME, CREATEDATE, SAVEDATE | Supported | PAGE, NUMPAGES and SECTION are filled in by the viewer; the others show the saved value. |
| 135 | Fields | AUTHOR, TITLE, SUBJECT, KEYWORDS, FILENAME, NUMWORDS | Supported | Show the saved value. |
| 136 | Fields | Formula (=), IF, QUOTE | Supported | Show the saved result. |
| 137 | Language | Other scripts: Greek, Cyrillic, Devanagari, Tamil, CJK, Arabic, Hebrew | Supported | Needs a font on the phone with these scripts (Android and iOS have them). |
| 138 | Language | Unicode symbols and emoji | Supported |  |
| 139 | Language | Non-breaking space, soft hyphen, non-breaking hyphen, em and en spaces | Supported |  |
