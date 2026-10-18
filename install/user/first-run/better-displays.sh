plugin_id="io.github.dragosol.better-displays-pro"
plugins=$(omarchy-plugin-catalog)

if ! jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' <<<"$plugins" >/dev/null; then
  omarchy-plugin-add https://github.com/dragosol/omarchy-better-displays.git --enable --yes
fi

# Keep the stock control until the replacement is installed and enabled.
# A relative placement also preserves a stock icon moved to another section.
config="$HOME/.config/omarchy/shell.json"
if [[ -f $config ]] && jq -e '
  any(.bar.layout[][]?; (if type == "object" then .id else . end) == "omarchy.monitor")
' "$config" >/dev/null; then
  omarchy-plugin-enable "$plugin_id" --before omarchy.monitor
  omarchy-plugin-disable omarchy.monitor
fi
