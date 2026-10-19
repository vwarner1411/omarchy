plugin_id="tmn73.calendar"
plugins=$(omarchy-plugin-catalog)

if ! jq -e --arg id "$plugin_id" 'any(.[]; .id == $id)' <<<"$plugins" >/dev/null; then
  omarchy-plugin-add https://github.com/tmn73/omarchy-calendar.git --enable --yes
fi

config="$HOME/.config/omarchy/shell.json"
if [[ -f $config ]] && jq -e '
  any(.bar.layout[][]?; (if type == "object" then .id else . end) == "omarchy.clock")
' "$config" >/dev/null; then
  # The clone inherits the stock clock's settings when it replaces its entry.
  omarchy-plugin-enable "$plugin_id"
  if jq -e '
    any(.bar.layout[][]?; (if type == "object" then .id else . end) == "omarchy.clock")
  ' "$config" >/dev/null; then
    omarchy-plugin-disable omarchy.clock
  fi
fi

# Plugin installation can place the clock after the tray. Only move it when
# needed, preserving its settings and every other widget's relative order.
if [[ -f $config ]] && jq -e --arg id "$plugin_id" '
  def entry_id: if type == "object" then .id else . end;
  any(.bar.layout[][]?; entry_id == $id) and
  ((.bar.layout.right[-1] | entry_id) != $id)
' "$config" >/dev/null; then
  end_index=$(jq '.bar.layout.right | length' "$config")
  omarchy-bar move "$plugin_id" --section right --index "$end_index"
fi
