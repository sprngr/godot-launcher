export DISPLAY=:0

RESOLUTION=`xdpyinfo | awk '/dimensions/{print $2}'`

#feh --bg-center --randomize ~/godot-launcher/wallpaper/*.png
feh --bg-center --randomize ~/godot-launcher/wallpaper/wallpaper_industrial.png

mplayer -volume 50 /home/cpi/music/gameboy-startup.mp3 2>&1 &

exec ~/godot-launcher/compton --vsync opengl --paint-on-overlay > /tmp/compton.log 2>&1 &
exec ~/godot-launcher/godot --resolution $RESOLUTION --audio-driver Dummy ~/godot-launcher/project.godot > /tmp/godot-launcher.log 2>&1