/// A second host for image hosts that publish the same files under the same
/// path elsewhere, keyed by the host the image URL names.
///
/// A table, not logic: adding a mirror is a row here, and nothing in
/// `ImageService` has to be opened to add it. `ImageService` asks the mirror
/// only when the original host has a problem (unreachable, refusing, or
/// skipped while cooling down) — never for a 404, which says the image is
/// missing, not the host.
///
/// A copy fetched from the mirror is saved under the original URL's name.
/// The local cache is keyed by the URL the reference database names, so a
/// file saved under the mirror's URL would never be found again by the next
/// lookup, and would sit on disk unreferenced.
///
/// SeaLifeBase has no entry: its only other host sits behind a Cloudflare
/// challenge that turns an app away with a 403.
const Map<String, String> imageHostFallbacks = {
  'www.fishbase.se': 'fishbase.de',
};
