plugin_id="vt.grok-usage"
plugins=$(omarchy-plugin-catalog)

if jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' <<<"$plugins" >/dev/null; then
  echo "Grok Usage is already installed; keeping its settings."
else
  omarchy-plugin-add https://github.com/vitally/omarchy-grok-usage.git --enable --yes
fi
