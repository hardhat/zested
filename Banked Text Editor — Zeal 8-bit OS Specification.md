# Banked Text Editor for Zeal 8-bit OS

## 1. Overview

This document specifies a low-overhead text editor for the Zeal 8-bit computer, targeting the Z80 CPU and a memory architecture organized into 16 KB banks.

The editor is intended primarily for editing large text files such as:

- Z80 assembly source
- C source
- Header files
- Configuration files
- Script files
- Other line-oriented text

The design prioritizes:

1. Low RAM overhead
2. Fast insertion and deletion
3. Minimal copying of existing text
4. Efficient sequential access
5. Efficient search and replace
6. Efficient movement through source files
7. Simple Z80 assembly implementation
8. Efficient use of 16 KB memory banks
9. Recovery from fragmentation without requiring large temporary buffers

The primary data structure is a **paged piece table**.

---

# 2. Design Summary

The file is represented by three major components:

```text
                 ┌────────────────────┐
                 │   Original Text    │
                 │  read-only pages   │
                 └─────────┬──────────┘
                           │
                           │
                 ┌─────────▼──────────┐
                 │     Piece Table    │
                 │ logical file order │
                 └─────────┬──────────┘
                           │
                           │
                 ┌─────────▼──────────┐
                 │     Add Text       │
                 │ append-only pages  │
                 └────────────────────┘
```

The piece table describes which portions of the original file and newly inserted text make up the current document.

Text is stored in fixed-size pages rather than as one contiguous buffer.

Recommended page size:

```text
256 bytes
```

The resulting architecture is:

```text
Document
   │
   ├── Original pages
   │
   ├── Add pages
   │
   ├── Piece index
   │
   ├── Line index
   │
   └── Editor state/cache
```

---

# 3. Memory Model

## 3.1 Bank Size

The fundamental memory allocation unit is:

```text
16 KB = 16384 bytes
```

A bank is identified by an 8-bit bank number where practical.

Within a bank, text is addressed using a 16-bit offset.

A logical text address is therefore:

```text
bank : offset
```

rather than a conventional flat pointer.

---

# 4. Text Pages

Text storage is divided into fixed-size pages.

Recommended size:

```text
PAGE_SIZE = 256
```

A page therefore has a very convenient representation on the Z80:

```text
page offset = 8 bits
```

A page can contain:

```text
256 bytes
```

or, depending on implementation, reserve one byte for special purposes.

## 4.1 Page Address

A page reference should contain:

```asm
PageRef:
    bank        db
    page        db
```

If pages are aligned to 256-byte boundaries, the physical address is:

```text
bank + page << 8
```

This makes page addressing particularly cheap.

If the Zeal memory mapping permits direct mapping of a bank, the page can be accessed as:

```text
BANK + page * 256
```

without requiring a full 16-bit offset in every reference.

---

# 5. Original Text Store

When a file is opened, the original file is copied into pages.

The original pages are thereafter treated as immutable.

Example:

```text
Original file

Bank 10:
    page 0
    page 1
    page 2
    ...
    page 63

Bank 11:
    page 0
    page 1
    ...
```

The original data never needs to be rearranged when editing.

This is a major advantage of the piece-table architecture.

---

# 6. Add Text Store

All newly inserted text is written to an append-only add store.

For example:

```text
Add Store

Bank 20
    page 0
    page 1
    page 2

Bank 21
    page 0
    ...
```

When the user inserts text:

1. Allocate space at the end of the add store.
2. Copy the inserted text there.
3. Add or modify piece descriptors.
4. Do not move existing text.

Deleted text is not immediately removed from the add store.

This intentionally trades unused storage for extremely cheap editing.

---

# 7. Piece Table

The logical document is represented by pieces.

Each piece identifies a range of one of the two text stores:

```text
ORIGINAL
ADD
```

A minimal piece descriptor is:

```asm
Piece:
    source      db      ; 0 = original, 1 = add
    bank        db
    page        db
    offset      db
    length      dw
```

Size:

```text
6 bytes
```

A piece therefore represents:

```text
source + bank + page + offset + length
```

---

# 8. Why Pieces Use Pages

A conventional piece table might store a large arbitrary offset into a file.

The Zeal implementation should instead use page-relative addressing.

For example:

```text
Piece:
    source = ADD
    bank   = 21
    page   = 14
    offset = 32
    length = 87
```

means:

```text
Bank 21
Page 14
Offset 32
Length 87
```

This avoids large file offsets and makes bank switching explicit.

---

# 9. Piece List Organization

The initial implementation should use an **array of pieces**.

For example:

```text
Piece 0
Piece 1
Piece 2
...
Piece N
```

This is preferable to a general-purpose linked list because:

- Sequential traversal is faster.
- Metadata is compact.
- No pointer chasing is required.
- Searching is simpler.
- Z80 address arithmetic is easier.
- Pieces can be compacted in-place.

A piece descriptor is only 6 bytes.

---

# 10. Piece Insertion

Suppose the document contains:

```text
AAAA BBBB CCCC
```

and the cursor is between:

```text
AAAA | BBBB
```

The existing piece:

```text
AAAA BBBB
```

can be split into:

```text
AAAA
BBBB
```

The inserted text becomes another piece:

```text
AAAA
XXXX
BBBB
```

Only the piece metadata changes.

The existing text does not move.

---

# 11. Piece Merging

Adjacent compatible pieces should be merged automatically.

Two pieces can be merged when:

```text
same source
same bank
same page
first.end == second.start
```

For example:

```text
ADD page 12 offset 0 length 20
ADD page 12 offset 20 length 15
```

becomes:

```text
ADD page 12 offset 0 length 35
```

This is important because repeated typing can otherwise generate a large number of tiny pieces.

---

# 12. Typed Character Optimization

Typing one character at a time must not generate one piece per character.

The editor should maintain an active insertion piece.

For example, while typing:

```text
HELLO WORLD
```

the text should preferably remain one contiguous add-buffer region:

```text
ADD page 7 offset 20 length 11
```

rather than:

```text
H
E
L
L
O
...
```

The editor should append characters to the current insertion region whenever possible.

---

# 13. Page Allocation

The add store should allocate pages sequentially.

Maintain:

```asm
AddCurrentBank
AddCurrentPage
AddCurrentOffset
```

When the current page becomes full:

```text
offset >= 256
```

allocate the next page.

Because pages are 256 bytes, the offset can be represented as an 8-bit value.

---

# 14. Handling Large Insertions

For pasted or loaded text:

```text
while bytes remain:
    allocate page space
    copy as much as possible
    create/extend piece
```

The editor should avoid requiring the entire inserted block to exist in a temporary buffer.

This allows insertion of text substantially larger than the currently mapped RAM window.

---

# 15. Deletion

Deletion should normally modify only the piece table.

For example:

```text
AAAA BBBB CCCC
```

delete:

```text
BBBB
```

results in:

```text
AAAA CCCC
```

The deleted data remains in the original/add store.

The corresponding piece is removed or shortened.

---

# 16. Partial Piece Deletion

If a deletion begins or ends in the middle of a piece, split the piece.

Example:

```text
AAAAAAAAAAAAAAAA
```

Delete the middle four characters:

```text
AAAA[AAAA]AAAAAAAA
```

Result:

```text
AAAA AAAAAAAA
```

represented by two pieces referring to the same underlying page.

No text copying is necessary.

---

# 17. Line-Oriented Operations

Because source code is primarily line-oriented, the editor should treat newline characters as an important indexing point.

The underlying storage remains byte-oriented.

The editor should recognize:

```text
'\n'
```

as the canonical line terminator.

If CR/LF files are supported, they should be normalized when loaded or handled consistently according to an editor configuration flag.

---

# 18. Sparse Line Index

A complete line table could consume considerable RAM for very large files.

Instead, maintain a sparse index.

Recommended:

```text
one entry every 16 lines
```

Each entry identifies approximately where that line begins.

Example:

```text
Line 0
Line 16
Line 32
Line 48
Line 64
...
```

A line-index entry can contain:

```asm
LineIndex:
    piece       dw
    offset      dw
```

or, if piece count permits:

```asm
LineIndex:
    piece       db
    offset      dw
```

The exact representation should be selected based on maximum supported piece count.

---

# 19. Line Navigation

To locate line N:

```text
index = N / 16
base_line = index * 16
```

Load the nearest sparse index entry.

Then scan forward until the requested line is reached.

For example:

```text
Line 1024 requested

nearest indexed line:
1024

scan:
1024
```

For an unindexed line:

```text
Line 1030 requested

index:
1024

scan six newline characters
```

This gives predictable memory use while making normal source navigation fast.

---

# 20. Cursor Cache

The editor should maintain a cached current position.

Recommended state:

```asm
CursorPiece        dw
CursorOffset       dw
CursorLine         dw
CursorColumn       dw
```

Additionally cache:

```asm
CurrentPieceBank
CurrentPiecePage
```

When moving one character at a time, the editor should not repeatedly search from the beginning of the piece table.

Typical cursor movement becomes:

```text
increment offset
```

until the piece boundary is reached.

---

# 21. Bank Cache

The editor should maintain the currently mapped text bank.

Example:

```asm
CurrentBank       db
```

Before accessing text:

```text
if requested_bank != CurrentBank:
    switch bank
    CurrentBank = requested_bank
```

This avoids unnecessary bank-switch operations.

---

# 22. Text Access API

All editor operations should access text through a small set of primitives.

Suggested API:

```asm
text_get_char
text_next
text_prev
text_seek
text_copy
text_compare
text_insert
text_delete
```

Higher-level operations should not directly manipulate bank registers.

This isolates bank-management code from editor algorithms.

---

# 23. Sequential Text Iterator

Search, display, saving, and many other operations benefit from a common iterator.

Conceptually:

```asm
TextIterator:
    piece       dw
    offset      dw
    remaining   dw
    bank        db
    page        db
```

Operations:

```asm
iterator_init
iterator_next
iterator_prev
iterator_peek
iterator_seek
```

The iterator should automatically cross:

```text
piece boundaries
page boundaries
bank boundaries
```

---

# 24. Screen Rendering

The editor should render from the logical document rather than directly from the underlying storage.

For each visible line:

```text
locate line
    ↓
iterate pieces
    ↓
render characters
    ↓
advance to newline
```

The renderer should retain a small line cache if useful.

For example:

```text
Visible text
     ↓
Line cache
     ↓
Video output
```

This prevents repeated piece traversal during cursor redraws.

---

# 25. Search

Search should operate directly on the logical text iterator.

The basic algorithm can initially be a straightforward substring search.

For each candidate position:

```text
compare search string
```

using the iterator.

The important optimization is that the search must not copy the entire logical document into a contiguous buffer.

---

# 26. Search Across Piece Boundaries

A search string must be allowed to cross:

```text
piece boundaries
page boundaries
bank boundaries
```

Example:

```text
Piece A: "MOV HL,"
Piece B: "1234"
```

Search:

```text
"HL,1234"
```

must find the match even though the characters are stored in separate pieces.

Therefore search should operate on the logical character stream.

---

# 27. Search Optimization

For short source-code searches, a simple algorithm is probably sufficient.

Typical search strings are relatively short:

```text
main
printf
LD HL
TODO
#include
```

The implementation should initially use:

```text
naive substring search
```

rather than immediately implementing a complex algorithm.

If profiling demonstrates a need for faster searches, a Boyer-Moore-family algorithm can be added later.

The search pattern should remain in ordinary RAM.

---

# 28. Search and Replace

Replace should use the existing piece-table operations.

For each match:

```text
delete matched range
insert replacement text
```

However, repeated modifications can make the piece table grow rapidly.

Therefore replace-all should preferably process matches from **end to beginning**.

Example:

```text
match 1
match 2
match 3
match 4
```

Process:

```text
match 4
match 3
match 2
match 1
```

This prevents earlier replacements from invalidating the locations of later matches.

---

# 29. Replace-All Add Buffer Optimization

The replacement string should be stored once when practical.

For example:

```text
search:
"foo"

replace:
"bar"
```

Every replacement can reference the same add-buffer data.

This avoids storing:

```text
bar
bar
bar
bar
...
```

multiple times.

Thus identical replacement text can share a single piece source region.

---

# 30. Undo

The piece-table architecture naturally supports undo if edit operations are recorded.

An undo record can describe:

```text
INSERT:
    position
    inserted piece(s)

DELETE:
    position
    removed piece(s)
```

Rather than storing the deleted text again, the undo system can retain references to the pieces that were removed from the active document.

---

# 31. Undo Record

A possible compact structure:

```asm
UndoRecord:
    type        db
    piece       dw
    count       db
    position    dw
```

The exact format should be optimized after the maximum supported piece count and undo depth are established.

Undo history should be bounded by configurable memory usage.

---

# 32. Redo

Redo can use the same operation representation.

The simplest implementation is:

```text
Undo stack
Redo stack
```

After a new edit:

```text
redo stack = empty
```

After undo:

```text
undo → redo
```

After redo:

```text
redo → undo
```

---

# 33. Piece Table Compaction

Over time, editing can produce many pieces.

The editor should therefore provide a compaction operation.

Compaction creates a new logical representation:

```text
Current document
      ↓
new text pages
      ↓
new compact piece table
```

The resulting document can have:

```text
large contiguous pieces
```

instead of thousands of small fragments.

---

# 34. Compaction Strategy

Compaction should occur:

- When the piece table approaches its maximum capacity
- When add-store waste becomes excessive
- When explicitly requested
- Optionally when the editor is idle

Compaction should not occur after every edit.

---

# 35. Incremental Compaction

A full compaction may take a noticeable amount of time.

Therefore the architecture should permit incremental compaction.

Conceptually:

```text
old document
     ↓
process a few pages
     ↓
yield
     ↓
process more pages
     ↓
yield
     ↓
complete
```

This allows the UI to remain responsive.

---

# 36. Saving

Saving should stream the logical document to the output file.

Algorithm:

```text
iterator_init
while not EOF:
    copy logical text to file
```

No complete contiguous copy of the document is required.

The output file therefore contains a normal linear text file regardless of the internal representation.

---

# 37. Loading

Loading should stream the source file directly into original pages.

Algorithm:

```text
allocate page
read data
repeat
```

At the end:

```text
create initial piece covering entire file
```

A newly loaded file therefore normally starts with:

```text
1 piece
```

or a small number of pieces if page boundaries are explicitly represented.

---

# 38. Maximum File Size

The maximum logical file size should not be constrained by a single 16 KB bank.

The logical document may span:

```text
multiple banks
```

The practical maximum is determined by:

```text
available banks
+
piece-table capacity
+
line-index capacity
+
filesystem limits
```

The editor should expose a compile-time configurable maximum.

---

# 39. Piece Table Capacity

The piece table itself should reside in dedicated editor RAM when possible.

For example:

```text
256 pieces × 6 bytes = 1536 bytes
512 pieces × 6 bytes = 3072 bytes
1024 pieces × 6 bytes = 6144 bytes
```

This makes the trade-off explicit.

A practical initial target is:

```text
512 pieces
```

with compaction triggered before the table becomes full.

---

# 40. Optional Piece Blocks

If a single large piece array is insufficient, pieces can be divided into fixed-size blocks.

For example:

```text
PieceBlock = 32 pieces
```

At 6 bytes per piece:

```text
32 × 6 = 192 bytes
```

A block can therefore fit comfortably within a 256-byte page.

The piece index then becomes:

```text
block
piece within block
```

This permits the piece table to grow without requiring one contiguous RAM allocation.

---

# 41. Recommended Piece-Block Architecture

The preferred scalable implementation is:

```text
Piece Directory
       │
       ├── Block 0
       ├── Block 1
       ├── Block 2
       └── ...
```

Each block contains a fixed number of piece records.

Insertion only requires shifting pieces within a block and occasionally splitting a block.

This is effectively a small B-tree-like structure without the overhead of a general-purpose tree.

A full balanced rope is unnecessary.

---

# 42. Recommended Initial Implementation

For the first version, simplify this further:

```text
Fixed piece array
+
paged text stores
+
sparse line index
+
cursor cache
```

Only introduce piece blocks if real-world files demonstrate that the fixed array is insufficient.

This keeps the first implementation manageable in Z80 assembly.

---

# 43. Why Not a Rope?

A conventional rope provides efficient insertion and deletion, but has undesirable properties for this target:

- More pointers
- More metadata
- Tree balancing
- More random memory accesses
- More complicated traversal
- More bank switching
- More complicated undo

A piece table provides most of the useful benefits with substantially less machinery.

---

# 44. Why Not a Traditional Gap Buffer?

A conventional gap buffer is attractive because it is simple and very fast for local typing.

However, moving a large gap through a banked file can require substantial copying.

The problem becomes particularly noticeable when:

```text
cursor moves long distances
```

or edits occur in many different parts of a large file.

A gap buffer can still be used as a **small temporary editing cache**, but it should not be the primary document representation.

---

# 45. Optional Local Gap Buffer

An optimization for later versions is a small gap buffer around the cursor.

For example:

```text
logical document
       ↓
piece table
       ↓
small local editing buffer
```

The local buffer could be:

```text
256–1024 bytes
```

Typing can occur entirely within this buffer.

When the cursor moves away or the buffer fills:

```text
flush → add store → update piece table
```

This is optional and should only be implemented after profiling.

The basic piece table should work without it.

---

# 46. Memory Allocation

The editor should use separate allocation domains:

```text
ORIGINAL STORE
ADD STORE
PIECE STORAGE
LINE INDEX
UNDO STORAGE
TEMPORARY STORAGE
```

This prevents one subsystem from unexpectedly consuming memory required by another.

---

# 47. Bank Allocation Bitmap

If banks are dynamically allocated, maintain a compact bank allocation bitmap.

For example:

```text
bit = 1 → bank allocated
bit = 0 → bank available
```

One byte describes eight banks.

This is substantially cheaper than maintaining a large linked-list allocator.

---

# 48. Bank Types

The OS/editor should distinguish between:

```text
BANK_FREE
BANK_ORIGINAL
BANK_ADD
BANK_METADATA
BANK_TEMP
```

The exact implementation may use separate allocation pools instead of storing an explicit type.

---

# 49. Bank Lifetime

Original-file banks should remain allocated until:

```text
file closed
```

Add-store banks remain allocated until:

```text
file closed
```

or until compaction produces a new representation and the old add store is no longer referenced.

---

# 50. Dirty State

The document should maintain:

```asm
DocumentDirty:
    db
```

Set when the logical document changes.

Clear after successful save.

The editor should not consider modifications to the add store alone sufficient to determine dirty state; the piece table represents the current document.

---

# 51. File Format Independence

The internal representation should not depend on the input file format.

The document model should represent:

```text
raw bytes
```

with optional editor-level interpretation of:

```text
LF
CRLF
tabs
```

This makes the editor suitable for source code as well as arbitrary text files.

---

# 52. Tabs

Tabs should remain stored as actual:

```text
0x09
```

characters.

The display layer determines the visual tab width.

This prevents formatting information from being lost.

---

# 53. Character Encoding

The initial implementation should treat text as bytes.

For ASCII-compatible source files:

```text
1 byte = 1 character
```

If Zeal OS later supports another character encoding, the editor's rendering and cursor logic can be extended without changing the underlying piece-table representation.

---

# 54. Z80 Register Strategy

Hot text operations should minimize register pressure.

A useful convention is:

```text
HL = current address/offset
DE = destination/source
BC = length
A  = flags/source type
```

Bank number can be stored in a dedicated variable or temporarily in an alternate register where practical.

The exact calling convention should be established globally for the editor.

---

# 55. LDIR Usage

Where source and destination are physically contiguous in the currently mapped memory, use:

```asm
LDIR
```

for copying.

However, the editor must not assume a copy can cross a 16 KB bank boundary.

A copy operation should therefore be split into bank-local operations:

```text
calculate bytes remaining in bank
copy that amount
switch bank
continue
```

---

# 56. Page-Aligned Optimization

Whenever possible, allocate add-store pages on 256-byte boundaries.

This provides:

- Cheap offset calculation
- Simple page rollover
- Easy copying
- Small page descriptors
- Efficient bank accounting

It also allows high/low address calculations to be simplified considerably.

---

# 57. Search Across Banks

Search must not assume the target text is contiguous in physical memory.

The iterator abstracts this:

```text
logical character
      ↓
piece
      ↓
page
      ↓
bank
```

The search algorithm sees only:

```text
next character
```

This keeps the search implementation simple.

---

# 58. Search Acceleration

An optional secondary index can later be added for source-code searches.

Possible candidates include:

```text
line-start index
symbol index
word index
```

However, these should not be part of the initial implementation.

A full inverted-text index would consume too much RAM and complicate editing.

---

# 59. Symbol Index

For source-code editing, a lightweight symbol index may eventually be useful.

For example:

```text
label → line
function → line
```

It should be treated as a rebuildable cache rather than authoritative document state.

If memory is exhausted, the symbol index can simply be discarded and rebuilt.

---

# 60. Crash/Power-Failure Considerations

The piece-table architecture is suitable for future journaling.

An edit journal could record:

```text
operation
position
piece information
```

Because inserted text is append-only, a journaled version could potentially recover the logical document after an interrupted operation.

This should be considered a future feature rather than part of the minimal editor.

---

# 61. Core Data Structures

Recommended initial definitions:

```asm
;------------------------------------------------
; Text page reference
;------------------------------------------------

PageRef:
    bank        db
    page        db


;------------------------------------------------
; Logical document piece
;------------------------------------------------

Piece:
    source      db      ; 0 = original, 1 = add
    bank        db
    page        db
    offset      db
    length      dw


;------------------------------------------------
; Sparse line index
;------------------------------------------------

LineIndex:
    piece       dw
    offset      dw
```

Additional global state:

```asm
CurrentPiece       dw
CurrentOffset      dw
CurrentLine        dw
CurrentColumn      dw

CurrentBank        db

AddBank             db
AddPage             db
AddOffset           db

PieceCount          dw
LineIndexCount      dw

DocumentDirty       db
```

---

# 62. Core API

The first implementation should provide:

```asm
document_create
document_load
document_save
document_close

text_get_char
text_put_char
text_seek
text_next
text_prev

text_insert
text_delete

piece_split
piece_merge
piece_compact

line_find
line_next
line_prev

search
replace
replace_all

undo
redo
```

---

# 63. Editor Startup

Opening a file:

```text
1. Allocate document state.
2. Allocate original pages.
3. Read file into original pages.
4. Create initial piece.
5. Build sparse line index.
6. Initialize cursor.
7. Mark document clean.
```

---

# 64. Editing a Character

For insertion:

```text
1. Locate cursor piece.
2. Append character to active add region.
3. Extend/modify current piece.
4. Update cursor.
5. Update line information if newline.
6. Mark dirty.
```

If the insertion is not adjacent to the current add region:

```text
allocate new add region
create new piece
```

---

# 65. Editing a Line

For inserting a complete line:

```text
append line to add store
insert piece at cursor
update sparse line index
```

The existing file contents do not move.

---

# 66. Deleting a Line

Deleting a line should generally be implemented as:

```text
find line start
find next line start
delete logical range
```

The underlying text remains untouched.

---

# 67. Newline Accounting

Whenever an edit contains newline characters, the editor should update the line index.

For small changes, update nearby entries directly.

For large changes, mark the index dirty:

```asm
LineIndexDirty:
    db
```

and rebuild it incrementally.

This avoids expensive index maintenance during large paste operations.

---

# 68. Line Index Rebuild

A complete rebuild scans the logical document:

```text
line = 0

while not EOF:
    if line % 16 == 0:
        add index entry

    read character

    if character == '\n':
        line++
```

The scan is sequential and therefore efficient even across many banks.

---

# 69. Large Paste

Large paste operations should be treated as one logical transaction.

Example:

```text
BEGIN_UNDO_GROUP

append data to add store
create pieces
update line information

END_UNDO_GROUP
```

Undo should then remove the entire paste with one operation.

---

# 70. Search/Replace Transaction

Similarly:

```text
BEGIN_UNDO_GROUP

find match
replace
find match
replace
...

END_UNDO_GROUP
```

A user should normally be able to undo an entire Replace All with one undo command.

---

# 71. Fragmentation Metrics

The editor should track approximately:

```text
piece count
add-store bytes
unused add-store bytes
line-index size
undo memory
```

This allows compaction decisions to be made intelligently.

---

# 72. Compaction Trigger

An initial policy could be:

```text
if PieceCount > 75% of maximum:
    request compaction
```

or:

```text
if AddStore waste > configurable threshold:
    compact
```

The thresholds should be tunable.

---

# 73. Performance Goals

The implementation should aim for:

### Cursor movement

Adjacent character:

```text
O(1)
```

### Local insertion

```text
O(1)
```

apart from piece metadata management.

### Local deletion

```text
O(1)
```

apart from piece metadata management.

### Search

```text
O(N × M)
```

for the initial naive implementation, where:

```text
N = document length
M = search-string length
```

### Save

```text
O(N)
```

### Line lookup

Approximately:

```text
O(16)
```

logical line scans after using the sparse index.

### Compaction

```text
O(N)
```

---

# 74. Important Performance Principle

The most important optimization is:

> **Do not move existing document text unless performing explicit compaction.**

Normal editing should modify metadata and append new text.

This is the fundamental reason for using the piece-table architecture.

---

# 75. Recommended Final Architecture

The complete editor architecture is:

```text
                    ┌──────────────────────┐
                    │      Editor UI       │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │   Cursor / Lines     │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │   Text Iterator      │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │     Piece Table      │
                    └───────┬───────┬──────┘
                            │       │
             ┌──────────────┘       └──────────────┐
             ▼                                     ▼
     ┌────────────────┐                    ┌────────────────┐
     │ Original Pages │                    │   Add Pages    │
     │ 256-byte pages │                    │ 256-byte pages │
     └────────────────┘                    └────────────────┘

                    ┌──────────────────────┐
                    │  Sparse Line Index  │
                    └──────────────────────┘

                    ┌──────────────────────┐
                    │    Undo / Redo      │
                    └──────────────────────┘
```

---

# 76. Implementation Priorities

## Phase 1 — Core document

- [x] Implement bank allocator
- [x] Implement 256-byte text pages
- [x] Implement original text store
- [x] Implement add text store
- [x] Implement 6-byte piece descriptor
- [x] Implement fixed piece array
- [x] Implement piece splitting
- [x] Implement piece merging
- [x] Implement logical text iterator
- [x] Implement file loading
- [x] Implement file saving

## Phase 2 — Editor operations

- [ ] Implement cursor movement
- [ ] Implement character insertion
- [ ] Implement character deletion
- [ ] Implement line insertion
- [ ] Implement line deletion
- [ ] Implement scrolling
- [ ] Implement cursor cache
- [ ] Implement sparse line index

## Phase 3 — Search

- [ ] Implement forward search
- [ ] Implement backward search
- [ ] Support searches across piece boundaries
- [ ] Support searches across bank boundaries
- [ ] Implement replace
- [ ] Implement replace-all
- [ ] Group Replace All into one undo operation

## Phase 4 — Undo

- [ ] Implement undo records
- [ ] Implement undo stack
- [ ] Implement redo stack
- [ ] Implement grouped operations
- [ ] Ensure deleted text can be restored without copying

## Phase 5 — Maintenance

- [ ] Implement piece-table compaction
- [ ] Implement incremental compaction
- [ ] Implement line-index rebuild
- [ ] Add fragmentation metrics
- [ ] Add automatic compaction thresholds

## Phase 6 — Optimization

- [ ] Profile bank switching
- [ ] Optimize page iteration
- [ ] Optimize cursor movement
- [ ] Use LDIR where appropriate
- [ ] Optimize piece insertion
- [ ] Optimize search
- [ ] Consider piece blocks if the fixed piece table is insufficient
- [ ] Consider a small local gap buffer if profiling justifies it

---

# 77. Initial Configuration

The recommended first implementation should use:

```text
Text page size:             256 bytes
Piece size:                 6 bytes
Initial piece capacity:     512 pieces
Line index interval:        16 lines
Text representation:        raw bytes
Original store:             immutable
Add store:                  append-only
Search:                     naive substring search
Undo:                       enabled
Compaction:                 explicit + automatic threshold
Piece structure:            flat array
```

This provides a relatively simple implementation while leaving room for future scaling.

---

# 78. Design Principle

The editor should be designed around the following rule:

> **The physical organization of the text should be allowed to become messy so that editing remains cheap.**

The piece table provides the logical organization.

The 256-byte pages provide efficient physical storage.

The sparse line index provides fast source-code navigation.

The iterator hides bank and piece boundaries.

Compaction is the mechanism that occasionally restores physical locality.

This combination is well suited to a Z80 system where CPU cycles, RAM, and bank-switching overhead are substantially more important than the sophistication of the underlying data structure.