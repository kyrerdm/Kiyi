# Sources and attribution

Kıyı is a GPL-3.0 fork of TheBoredTeam/boring.notch (https://github.com/TheBoredTeam/boring.notch). It retains the upstream code and notices. Kıyı contains the NotchShape implementation from TheBoredTeam/boring.notch, preserving the authorship of Kai Azim and Alexander. Its original source is DynamicNotchKit. The referenced worktree is in App. The applicable GPL-3.0 license and upstream third-party license notices are included in this project and the application bundle.

The MediaRemoteAdapter Perl helper and framework are taken unchanged from that worktree. MediaRemoteAdapter is Copyright (c) 2025 Jonas van den Berg and contributors, BSD-3-Clause. Its full license appears in THIRD_PARTY_LICENSES. Framework ad-hoc signing is performed locally when building.

The Now Playing integration follows the structure and documented protocol in boring.notch/MediaControllers/NowPlayingController.swift. Shelf/AirDrop composition and interactions were studied in the running application and its Shelf components; Ada's lightweight implementations are maintained in Sources/Extras.swift.

No claim of affiliation or endorsement by Canopy, TheBoredTeam, or the upstream authors is made.

## WinMin

Gelgit’s Dock hover observation is adapted from WinMin by the WinMin Contributors (Copyright 2025), under the MIT License: https://github.com/Bittabola/winmin. The complete license is preserved in `App/BoringNotchXPCHelper/WinMin-LICENSE.txt` and included in the helper’s application resources.
