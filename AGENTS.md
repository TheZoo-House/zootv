# ZooTV development

Native Apple TV client only. Keep scheduling and transcoding in Tunarr. Do not add Plex credentials, server mutations, analytics, payment SDKs or a new streaming backend.

`project.yml` owns project configuration; regenerate with XcodeGen. Core has no third-party dependencies and must pass `swift test`. Run `swift run zootv-check` only on the home network. UI tests use real streams; stop playback at the end.

Never claim physical-TV validation from simulator results. Preserve automatic channel discovery and remote-operable focus, future program details, error/retry states and playback cleanup. No commits, pushes, app uploads or signing changes without appropriate permission. Record durable work in the Kanvil project ZTV.
