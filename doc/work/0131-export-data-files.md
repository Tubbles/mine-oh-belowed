# 0131: Export the data files and one way sync of the edits

Status: todo

## Goal

Asked on 2026-09-30: "an 'export all data files' option for android build (including overlays) so i can export things to my syncthing dir so you can see them. Maybe even have automatic one way file sync so it happens automatically when edits happen". The phone's own files folder (`Android/data/<package>/files`) is out of reach for Syncthing under scoped storage, so the export writes to a directory the user names, on shared storage.

## Change

- Two settings (`Settings`, `configuration.odin`, written by `write_settings_file` like the others, so `settings_file_text` learns strings): `export_directory` (string, default empty, no export while empty) and `export_on_save` (bool, default off). Both sit on the Data files screen (0129): a text field with the on screen keyboard for the directory (the keyboard's last row gains `/`; `TEXT_FIELD_CAPACITY` is 512 since 0130, so a shared storage path fits) and a toggle. They are ordinary configuration keys, so the phone's `config.d/90-settings.sjson` can be edited over USB too.
- An Export button on the Data files screen copies every file under the data directory to `<export_directory>/data/` and every overlay copy to `<export_directory>/data_edits/` (directories made with `make_directory_path`, files overwritten, nothing deleted), then writes `<export_directory>/export.txt` with the build stamp and the time, and toasts the counts or the first problem. It works on every platform; the couch can use it as well. The copy runs in the frame loop between frames (a request like the screenshot's).
- One way sync: with `export_on_save` on and a directory set, every save (0130) and every discard (0129) also writes or deletes that one file under `<export_directory>/data_edits/` at once, and reports a failure in a toast once. Nothing is read back from the export directory.
- Android: the manifest gets `android.permission.MANAGE_EXTERNAL_STORAGE`. Before an export or a synced save, `Environment.isExternalStorageManager()` is asked through JNI (`haptics_android.odin` is the precedent, new table indices go into `jni_indices.odin` and its test); when it is false the game starts the settings activity `android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION` with the app's package URI through the activity's `startActivity` and toasts "allow All files access, then export again". A file system error after the permission is granted (a path outside shared storage, a missing volume) is toasted with the path.
- Docs: `doc/build.md` (Android app: All files access, the export directory, what Syncthing sees), `doc/architecture.md` (the two settings), `doc/ui.md` (the Export button, the settings on the Data files screen).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: an export of a temporary data directory with one overlay copy produces `data/`, `data_edits/` and `export.txt` with the expected files; a synced save writes the one file and a synced discard removes it; an empty `export_directory` exports nothing and says so; the keyboard's rows contain `/`; a settings file with both keys round trips; the JNI index test covers the new indices.
- The user, on the phone: set the Syncthing folder's path, Export, find `data/`, `data_edits/` and `export.txt` on the couch through Syncthing; turn on export on save, save an edit, see the file arrive.
