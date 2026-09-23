/// The back-off policy for one host: how many retryable failures activate a
/// cooldown, and how long each successive cooldown lasts.
///
/// Three step lists rather than one, because the three kinds of failure
/// deserve different patience: a transport error is often a blip, a 5xx says
/// the server is struggling, and a 429 is the host explicitly asking to be
/// left alone.
class HostCooldownProfile {
  final int activationThreshold;
  final List<Duration> transportCooldownSteps;
  final List<Duration> responseCooldownSteps;
  final List<Duration> rateLimitCooldownSteps;

  const HostCooldownProfile({
    required this.activationThreshold,
    required this.transportCooldownSteps,
    required this.responseCooldownSteps,
    required this.rateLimitCooldownSteps,
  });
}

/// How hard the app backs off from each external host it talks to, and after
/// how many failures.
///
/// A table, not logic: adding a host is a row here, and nothing in
/// `HostCooldownTracker` has to be opened to add it. Hosts the table does
/// not name fall back to the tracker's own defaults, which is why most of
/// the app never appears in it.
///
/// The numbers differ per host because their rate limits do. iNaturalist's
/// API is the strictest and the one the enrichment pipeline leans on
/// hardest, so it activates after two failures rather than three and waits
/// longest after a 429.
const Map<String, HostCooldownProfile> hostCooldownProfiles = {
  'api.inaturalist.org': HostCooldownProfile(
      activationThreshold: 2,
      transportCooldownSteps: <Duration>[
        Duration(seconds: 10),
        Duration(seconds: 20),
        Duration(seconds: 45),
        Duration(seconds: 90),
      ],
      responseCooldownSteps: <Duration>[
        Duration(seconds: 15),
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
      ],
      rateLimitCooldownSteps: <Duration>[
        Duration(seconds: 45),
        Duration(minutes: 2),
        Duration(minutes: 5),
        Duration(minutes: 10),
      ],
  ),
  // The website host and the photo bucket share a budget: both are the
  // public iNaturalist site rather than the API, and hitting one hard is
  // what gets the other throttled.
  'www.inaturalist.org': _iNaturalistWeb,
  'inaturalist-open-data.s3.amazonaws.com': _iNaturalistWeb,
  'raw.githubusercontent.com': HostCooldownProfile(
      activationThreshold: 2,
      transportCooldownSteps: <Duration>[
        Duration(seconds: 20),
        Duration(seconds: 45),
        Duration(minutes: 2),
        Duration(minutes: 4),
      ],
      responseCooldownSteps: <Duration>[
        Duration(seconds: 20),
        Duration(seconds: 45),
        Duration(minutes: 2),
        Duration(minutes: 4),
      ],
      rateLimitCooldownSteps: <Duration>[
        Duration(minutes: 1),
        Duration(minutes: 3),
        Duration(minutes: 6),
        Duration(minutes: 10),
      ],
  ),
};

const HostCooldownProfile _iNaturalistWeb = HostCooldownProfile(
      activationThreshold: 2,
      transportCooldownSteps: <Duration>[
        Duration(seconds: 8),
        Duration(seconds: 20),
        Duration(seconds: 45),
        Duration(seconds: 90),
      ],
      responseCooldownSteps: <Duration>[
        Duration(seconds: 12),
        Duration(seconds: 25),
        Duration(seconds: 45),
        Duration(minutes: 2),
      ],
      rateLimitCooldownSteps: <Duration>[
        Duration(seconds: 30),
        Duration(seconds: 90),
        Duration(minutes: 3),
        Duration(minutes: 6),
      ],
);
