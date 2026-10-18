plugin_id="cdelcollado.bluetooth"
plugins=$(omarchy-plugin-catalog)

if ! jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' <<<"$plugins" >/dev/null; then
  omarchy-plugin-add https://github.com/cdelcollado/btomarchy.git --enable --yes
fi

# Activate the replacement in the stock position before removing the old icon.
config="$HOME/.config/omarchy/shell.json"
if [[ -f $config ]] && jq -e '
  any(.bar.layout[][]?; (if type == "object" then .id else . end) == "omarchy.bluetooth")
' "$config" >/dev/null; then
  omarchy-plugin-enable "$plugin_id" --before omarchy.bluetooth
  omarchy-plugin-disable omarchy.bluetooth
fi
