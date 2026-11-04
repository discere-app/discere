/// The smallest picture still worth comparing by; below it, a short screen
/// scrolls instead.
const double _minImageHeight = 140;

/// The tallest picture, so a tablet shows its species rather than a wall of
/// image.
const double _maxImageHeight = 360;

/// What a species' card takes besides its pictures: the card's margins and
/// padding, the names beside the remove button, and two lines of facts. Two
/// lines rather than one, so that a card whose facts wrap still fits.
const double _cardHeightBesidesImage = 210;

/// How tall the pictures of a species are on the comparison page, so that
/// [rowsPerScreen] rows of species fit whole into [viewportHeight] — two
/// rows in portrait, one below the other, and one row of two columns in
/// landscape — within bounds that keep a picture useful.
double comparisonImageHeight({
  required double viewportHeight,
  required int rowsPerScreen,
}) {
  final perRow = viewportHeight / rowsPerScreen;
  return (perRow - _cardHeightBesidesImage).clamp(
    _minImageHeight,
    _maxImageHeight,
  );
}
