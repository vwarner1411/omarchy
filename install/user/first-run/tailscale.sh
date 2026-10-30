plugin_id="igor-alexandrov.tailscale"
plugins=$(omarchy-plugin-catalog)

if jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' <<<"$plugins" >/dev/null; then
  echo "Tailscale is already installed; keeping its settings."
else
  omarchy-plugin-add https://github.com/igor-alexandrov/omarchy-tailscale.git --enable --yes
fi
