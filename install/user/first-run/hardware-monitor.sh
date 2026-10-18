plugin_id="io.github.edgarsilva.hw-monitor"
plugins=$(omarchy-plugin-catalog)

if jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' <<<"$plugins" >/dev/null; then
  echo "Hardware Monitor is already installed; keeping its settings."
else
  omarchy-plugin-add https://github.com/edgarsilva/omarchy-hw-monitor.git --enable --yes
fi
