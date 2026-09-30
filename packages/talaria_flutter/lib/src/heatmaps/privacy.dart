/// What [TalariaScreenCapture] paints over in a snapshot.
///
/// The default leaves the screenshot as the app rendered it. Password fields
/// are still covered. [TalariaMask] always covers, and [TalariaUnmask] opts
/// a subtree back out.
class TalariaHeatmapPrivacy {
  const TalariaHeatmapPrivacy({
    this.maskInputs = false,
    this.maskText = false,
    this.maskImages = false,
  });

  /// Cover text fields. Off by default so forms stay readable.
  final bool maskInputs;

  /// Cover [Text] and [RichText]. Off by default.
  final bool maskText;

  /// Cover [Image] widgets. Off by default.
  final bool maskImages;
}
