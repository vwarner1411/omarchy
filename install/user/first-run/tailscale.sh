plugin_id="igor-alexandrov.tailscale"
plugins=$(omarchy-plugin-catalog)

if jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' <<<"$plugins" >/dev/null; then
  echo "Tailscale is already installed; keeping its settings."
else
  omarchy-plugin-add https://github.com/igor-alexandrov/omarchy-tailscale.git --enable --yes
fi

# Keep the replacement's placement and settings; only remove the extra icon
# after activation succeeds. Respect an explicitly disabled replacement.
config="$HOME/.config/omarchy/shell.json"
if [[ -f $config ]] && jq -e --arg id "$plugin_id" '
  any(.bar.layout[][]?; (if type == "object" then .id else . end) == "omarchy.tailscale") and
  ((.disabledPlugins // []) | index($id) == null)
' "$config" >/dev/null; then
  omarchy-plugin-enable "$plugin_id"
  omarchy-plugin-disable omarchy.tailscale
fi
