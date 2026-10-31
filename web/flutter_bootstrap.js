{{flutter_js}}
{{flutter_build_config}}

// One renderer (CanvasKit, full variant) so the preview ships a single
// engine; the app is drawn in a phone-width column (#app).
_flutter.loader.load({
  config: {
    renderer: "canvaskit",
    canvasKitVariant: "full",
    hostElement: document.getElementById("app"),
  },
});
