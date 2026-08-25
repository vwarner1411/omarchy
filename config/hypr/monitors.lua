-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- Workstation layout: portrait 1080p left monitor, landscape 1440p right monitor.
hl.env("GDK_SCALE", "2")
hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "-1080x-360", scale = 1, transform = 3 })
hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@120", position = "0x0", scale = 1 })
