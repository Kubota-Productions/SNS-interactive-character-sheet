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
4. Select a PDF and a new destination folder, then click **Create Scene**.
5. Edit the generated controls normally and press F6 to try the scene.

Godot 4.4 or newer is required. Use the package matching your OS and CPU.
Packages are available for **Linux x86_64, glibc 2.34 or newer**, and
**Windows x86_64**. Other platforms require matching compiled native libraries;
their availability is checked before import.
Restart the editor when updating native plugin binaries.

Imports never overwrite an existing folder. Output contains page PNGs, an
editable `sheet.tscn`, and a layout inspection file. Editable field indices are
independent of node names and positions. Optional tags support partial migration.
Generated scenes use ordinary Godot controls, scripts, fonts, and textures;
PDF conversion is an editor operation.

## Fields

Text, multiline text, checkboxes, radio groups, and single-selection choices are
detected automatically. Pushbuttons emit an activation signal for game behavior.
Optional JSON overrides can map a field to an image picker or symbol control.
PDF JavaScript and PDF actions are not executed.

Optional document profiles are included under `profiles`: SNS 1.9, ITMP
interactive, and ITMP with image. Select the matching JSON as **Field overrides**
to get the toggle and image-picker behavior tested with those documents.

Text fields avoid printed captions, use a regular-weight bundled font, and keep
text inside clipping containers. Small cells center values. Checkbox indicators
and hitboxes fit their PDF rectangles. Fields and the shared input theme remain
editable in Godot's Inspector.

To save through your existing system, connect the sheet's `value_changed` signal
or use `snapshot()` / `apply_snapshot(state)`. Set a distinct `save_path` such as
`user://characters/ada.json` to enable built-in debounced JSON autosave. Use
`apply_snapshot(old_state, true)` to transfer compatible tagged values to a fresh
import. Untagged values are not migrated by that operation.

Flat PDFs produce artwork without detected inputs. There is no OCR, automatic
scene merging, PDF export, digital signing, or PDF calculation/script translation.
Encrypted and XFA PDFs are rejected. Unsupported widgets are reported for manual
authoring. The PDF engine and dependency notices are under `native/*/licenses`;
the font's license is under `fonts`.
