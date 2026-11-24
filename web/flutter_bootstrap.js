{{flutter_js}}
{{flutter_build_config}}

// Ohne Flutters eigenen Service Worker laden: Der ist nur noch ein
// Aufräum-Worker, der sich selbst abmeldet – und dabei den Offline-Worker
// der App (sw.js) mit abmelden würde.
_flutter.loader.load();
