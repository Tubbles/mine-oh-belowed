#+build !linux:android
package game

// Outside Android the export writes wherever the file system lets it
// (work item 0131): these stand in for export_access_android.odin.

all_files_access_granted :: proc() -> bool {return true}

open_all_files_access_settings :: proc() {}
