# dmgbuild settings for the installer disk image. dmgbuild writes the window
# layout (.DS_Store) itself instead of scripting Finder, so it works on a
# headless runner. Geometry must match Scripts/make-dmg-background.swift:
# 640x400 art, icons at 160 and 480, plus ~28pt of title bar in the window.
#
#   dmgbuild -s Packaging/dmgbuild-settings.py -D app=<ClipFormat.app> \
#            -D background=<background.png> ClipFormat <output.dmg>

import os.path

app = defines["app"]  # noqa: F821 (injected by dmgbuild)
background = defines["background"]  # noqa: F821

format = "UDZO"
filesystem = "HFS+"
compression_level = 9
size = None

files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    os.path.basename(app): (160, 212),
    "Applications": (480, 212),
}

background = background
window_rect = ((400, 240), (640, 428))
default_view = "icon-view"
icon_size = 128
text_size = 12
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
