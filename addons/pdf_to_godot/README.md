# PDF to Godot — native editor plugin

Import a fillable PDF into an ordinary, editable Godot scene. The entire
conversion runs **inside Godot** through the bundled native PDF engine.
There is no converter executable, Poppler installation, shell command, or PATH
configuration in the authoring workflow.

## Install

1. In Godot's AssetLib tab, choose **Import** and select the plugin ZIP, or
   extract its `addons/pdf_to_godot` folder into your project.
2. Enable **PDF to Godot** under Project Settings → Plugins.
3. Choose **Project → Tools → Import PDF as Scene…**.
4. Select a PDF, a new destination folder, and a page layout, then click **Create Scene**.
5. Edit the generated controls normally and press F6 to try the scene.

Godot 4.4 or newer is required. Use the package matching your OS and CPU.
Packages are available for **Linux x86_64, glibc 2.34 or newer**, and
**Windows x86_64**. Other platforms require matching compiled native libraries;
their availability is checked before import.
Restart the editor when updating native plugin binaries.

Imports never overwrite an existing folder. Output contains page PNGs, an
editable scenes, and a layout inspection file. Editable field indices are
independent of node names and positions. Optional tags support partial migration.
Generated scenes use ordinary Godot controls, scripts, fonts, and textures;
PDF conversion is an editor operation.

Choose one of three **Page layout** options:

- **Side by side (stretch w)** puts every page in a horizontal row in
  `sheet.tscn`. Artwork and controls scale together to fit the window width;
  tall pages can still scroll vertically.
- **Scrollable (standard)** is the default `sheet.tscn` with stacked pages,
  Previous/Next buttons, a page counter, and scrollbars. In the editor, pan down
  to edit later pages. Set `show_page_navigation` to false to supply your own UI;
  use `go_to_page(2)`, `get_current_page()`, and `get_page_count()`.
- **Separate scenes** creates `page_1.tscn`, `page_2.tscn`, etc. The first opens
  automatically. Each scene has its own sheet save API and independent state;
  assign distinct save paths when using autosave.

## Fields

Text, multiline text, checkboxes, radio groups, and single-selection choices are
detected automatically. Pushbuttons emit an activation signal for game behavior.
Optional JSON overrides can map a field to an image picker or symbol control.
PDF JavaScript and PDF actions are not executed.

Optional document profiles are included under `profiles`. Select the matching
JSON as **Field overrides** to get the document's toggle and image-picker behavior:

- `SNS1.9CS.pdf`: `sns-1.9.json`.
- `SNS1.9CSinteractiveupdated.pdf`: `sns-1.9-updated.json`.
- `ITMP-CSinteractive.pdf`: `itmp-interactive.json`.
- `ITMP-CSinteractivewithimage.pdf`: `itmp-with-image.json`.

The updated SNS PDF renamed and rearranged fields; the two SNS profiles are
not interchangeable. Its character-name field is `Text Field 216`.

Text fields avoid printed captions, use a regular-weight bundled font, and keep
text inside clipping containers. Small cells center values. Checkbox indicators
and hitboxes fit their PDF rectangles. Fields and the shared input theme remain
editable in Godot's Inspector.

Saving does not require SNS or an adapter. For built-in saving, select the root
PdfSheet and set **Save Path** to a distinct path such as
`user://characters/ada.json`. This enables debounced JSON autosave and restores
the file when the scene opens.

To use your existing save system, connect the sheet's `value_changed(index, value)`
signal through Godot's Signals panel, or store `snapshot()` and restore it with
`apply_snapshot(state)`. The optional `sns_adapter.gd` only bridges the existing
SNS `CharacterSaveData` API; general projects do not need it. Document profiles
configure field behavior independently of which save system you choose. Use
`apply_snapshot(old_state, true)` to transfer compatible tagged values to a fresh
import. Untagged values are not migrated by that operation.

Flat PDFs produce artwork without detected inputs. There is no OCR, automatic
scene merging, PDF export, digital signing, or PDF calculation/script translation.
Encrypted and XFA PDFs are rejected. Unsupported widgets are reported for manual
authoring. The PDF engine and dependency notices are under `native/*/licenses`;
the font's license is under `fonts`.
